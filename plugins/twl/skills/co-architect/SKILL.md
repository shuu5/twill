---
name: twl:co-architect
description: |
  対話的アーキテクチャ構築ワークフロー。
  explore を活用し architecture/ に設計意図を段階的にキャプチャ。
  完全性チェックと Issue 候補への分解・整合性チェックを実行。

  Use when user: says アーキテクチャ設計/architecture/全体設計,
  says 設計を構造化したい/Context分解/Phase計画,
  says --group/グループ深堀り/スケルトン精緻化.
type: controller
effort: high
tools:
- Agent(worker-architecture, worker-structure)
spawnable_by:
- user
---

# co-architect

対話的アーキテクチャ構築 → 完全性チェック → Issue 候補分解。Non-implementation controller（chain-driven 不要）。

## Step 0: --group 分岐

`--group <context-name>` が含まれる場合:
→ `/twl:architect-group-refine <context-name>` を実行して終了（Step 1〜8 スキップ）。

`--group` なし → Step 1 へ。

## Step 1: コンテキスト収集

TaskCreate 「Architecture: コンテキスト収集」(status: in_progress)

プロジェクト概要を把握:
- README.md, CLAUDE.md, パッケージマネージャ設定を Read
- 既存 `architecture/` があれば Read して現状把握
- なければ `architecture/` ディレクトリを作成

TaskUpdate → completed

## Step 2: 対話的アーキテクチャ探索

TaskCreate 「Architecture: 対話的探索」(status: in_progress)

`/twl:explore` を Skill tool で呼び出す。以下をコンテキストとして注入:

> アーキテクチャ探索モード: DDD の Bounded Context、ユビキタス言語、Context Map を使い設計を構造化。
> 確定した設計事項は architecture/ の対応ファイルに Write:
> - ビジョン → `architecture/vision.md`
> - ドメインモデル → `architecture/domain/model.md`
> - 用語定義 → `architecture/domain/glossary.md`
> - Bounded Context → `architecture/domain/contexts/<name>.md`
> - 設計判断 → `architecture/decisions/<NNNN>-<title>.md`
> - API 境界 → `architecture/contracts/<name>.md`

TaskUpdate → completed

## Step 3: 完全性チェック

TaskCreate 「Architecture: 完全性チェック」(status: in_progress)

`/twl:architect-completeness-check` を実行。

WARNING がある場合 → ユーザーに不足箇所を提示し補完するか確認。
補完する場合 → Step 2 に戻り explore を再開。

TaskUpdate → completed

## Step 4: Phase 計画確定

TaskCreate 「Architecture: Phase 計画」(status: in_progress)

ユーザーと対話し Phase 計画を確定:
- Context 間の依存関係から実装順序を導出
- 並列実行可能な Issue をグルーピング
- 各 Phase の `phases/<NN>.md` を Write

TaskUpdate → completed

## Step 5: Issue 候補分解

TaskCreate 「Architecture: Issue 分解」(status: in_progress)

`/twl:architect-decompose` を実行。

TaskUpdate → completed

## Step 6: 整合性チェック結果表示

architect-decompose の出力（6項目チェック結果）を表示。
WARNING がある場合は修正を提案。

## Step 7: ユーザー確認

Issue 候補リストの最終確認を AskUserQuestion で求める。
- [A] 承認 → Step 8 へ
- [B] 修正 → 修正後 Step 5 から再実行
- [C] キャンセル → 終了（architecture/ は保持）

## Step 8: Issue 一括作成

TaskCreate 「Architecture: Issue 作成」(status: in_progress)

`/twl:architect-issue-create` を実行。
architect-decompose の出力（Issue 候補リスト、Phase 情報）をコンテキストとして渡す。

### Step 8.5: Project Board 同期

作成された全 Issue 番号に対して `/twl:project-board-sync` を実行。
失敗時は警告のみ（Issue 作成は成功済み）。

TaskUpdate → completed

```
>>> アーキテクチャ構築 + Issue 作成完了

次のステップ:
  - autopilot 実行: /twl:co-autopilot で Issue 群を一括実装
  - 個別実装: /twl:workflow-setup #N で1件ずつ実装
```

## 禁止事項（MUST NOT）

- ユーザー確認なしに Issue を自動作成してはならない（Step 7 の承認必須）
- ユーザーの設計判断を代替してはならない（提案は可、決定はユーザー）
- controller 内に実質処理を記述してはならない（atomic に委譲）
  - 例外: Step 4 の Phase 計画確定は対話的操作のため controller 内で処理
