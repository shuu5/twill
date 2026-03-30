---
name: dev:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  4 Phase 構成: 問題探索 → 分解判断 → Per-Issue 精緻化 → 一括作成。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
spawnable_by:
- user
---

# co-issue

要望→Issue 変換ワークフロー（4 Phase 構成）。Non-implementation controller（chain-driven 不要）。

## explore-summary 検出（起動時チェック）

`.controller-issue/explore-summary.md` の存在を確認する。

```
IF explore-summary.md が存在する:
  → AskUserQuestion: 「前回の探索結果が残っています」
    [A] 継続する → Phase 2 から再開
    [B] 最初から → explore-summary.md を削除し Phase 1 から開始
ELSE:
  → Phase 1 から開始
```

self-improve-review の出力（`.controller-issue/explore-summary.md`）も同一パスで検出される。

## Phase 1: 問題探索（Issue 無関係モード）

TaskCreate 「Phase 1: 問題探索」(status: in_progress)

`/dev:explore` を Skill tool で呼び出す。以下の指示を注入:

> 問題空間の理解に集中してください。Issue 化や実装方法は意識しないでください。

探索完了（「Issue作成して」「まとめて」等）後:
1. `.controller-issue/` ディレクトリを作成
2. `.controller-issue/explore-summary.md` に書き出し:
   - 問題の本質（1-3文）
   - 影響範囲
   - 関連コンテキスト
   - 探索で得た洞察

TaskUpdate Phase 1 → completed

## Phase 2: 分解判断

TaskCreate 「Phase 2: 分解判断」(status: in_progress)

explore-summary.md を読み込み、Issue 候補を判断:

| 判断 | 条件 | 次のステップ |
|------|------|-------------|
| 単一 Issue | 単一の関心事 | Phase 3 を1回実行 |
| 複数 Issue | 複数の独立した関心事 | 分解候補をユーザーに提示 |

複数 Issue の場合は AskUserQuestion で分解内容を確認:
- [A] この分解で進める
- [B] 分解内容を調整
- [C] 単一 Issue のまま続行

TaskUpdate Phase 2 → completed

## Phase 3: Per-Issue 精緻化ループ

TaskCreate 「Phase 3: 精緻化（N件）」(status: in_progress)

各 Issue 候補に対して順に実行:

### Step 3.1: 曖昧点検出

`/dev:issue-dig` を呼び出し。結果:
- PASS → Step 3.2 へ
- WARN → 質問をユーザーに提示、回答反映後 Step 3.2 へ
- FAIL → 質問提示、回答反映後再実行（最大1回。2回 FAIL → WARN 扱いで続行）

### Step 3.2: Issue 構造化

`/dev:issue-structure` を呼び出し。テンプレート（refs/ref-issue-template-bug.md or refs/ref-issue-template-feature.md）に基づき構造化。

### Step 3.2.5: 推奨ラベル抽出

issue-structure の出力に `## 推奨ラベル` セクションが含まれる場合、`ctx/<name>` を抽出し Issue 候補に記録する。

```
IF issue-structure の出力に "## 推奨ラベル" セクションが存在する
THEN
  セクション内の `ctx/<name>` を正規表現で抽出（例: "- `ctx/workflow`" → "ctx/workflow"）
  抽出したラベルを当該 Issue 候補の recommended_labels に記録
ELSE
  recommended_labels = 空（Phase 4 で --label 引数なし）
```

### Step 3.3: 品質評価

`/dev:issue-assess` を呼び出し。結果処理:
- completeness < 100% → 補完して再評価（最大1回）
- duplicates あり → [A] 統合 [B] Related追加 [C] 無関係
- needs_split → 分割後の候補をループ末尾に追加
- tech_debt_decision → Step 3.4 へ
- 全 pass → 次の候補へ

### Step 3.4: tech-debt 棚卸し提案（該当時のみ）

`/dev:issue-tech-debt-absorb` を呼び出し。`includes_issues` と `related_issues` を Phase 4 で使用。

TaskUpdate Phase 3 → completed

## Phase 4: 一括作成

TaskCreate 「Phase 4: Issue 作成」(status: in_progress)

### Step 4.1: ユーザー確認（MUST）

全 Issue 候補の構造化結果をユーザーに提示。承認後に作成。

### Step 4.2: Issue 作成

- 単一 → `/dev:issue-create`
- 複数 → `/dev:issue-bulk-create`
- tech-debt 吸収がある場合は Related セクション（Includes #N / Related to #N）を付加
- Issue 候補に recommended_labels が記録されている場合、`--label` 引数に追加して渡す（例: `--label ctx/workflow`）
- 複数 Issue の場合、各 Issue に対応する個別の推奨ラベルをそれぞれの issue-create 呼び出しに渡す

### Step 4.3: Project Board 同期

各 Issue 作成後 `/dev:project-board-sync N` を実行。失敗時は警告のみ。

### Step 4.4: クリーンアップ

`.controller-issue/` ディレクトリを削除。セッション中止時も同様に削除。

### Step 4.5: 完了通知

Issue URL を表示し `/dev:workflow-setup #N` で開発開始を案内。

TaskUpdate Phase 4 → completed

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない
- Phase 1 完了前に Issue 構造化を開始してはならない
- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
