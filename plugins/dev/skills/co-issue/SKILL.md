---
name: dev:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  4 Phase 構成: 問題探索 → 分解判断 → Per-Issue 精緻化 → 一括作成。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
effort: high
tools:
- Agent(issue-critic, issue-feasibility, context-checker, template-validator)
spawnable_by:
- user
---

# co-issue

要望→Issue 変換ワークフロー（4 Phase 構成）。Non-implementation controller（chain-driven 不要）。

## explore-summary 検出（起動時チェック）

`.controller-issue/explore-summary.md` の存在を確認。存在時は「前回の探索結果が残っています。継続しますか？」と確認:
- [A] 継続する → Phase 1（探索）をスキップし Phase 2 から再開
- [B] 最初から → explore-summary.md を削除し Phase 1 から開始

存在しない場合は通常の Phase 1 から開始（既存動作に影響なし）。self-improve-review 出力も同一パスで検出される。

## Phase 1: 問題探索

TaskCreate 「Phase 1: 問題探索」(status: in_progress)

`/dev:explore` を Skill tool で呼び出し、「問題空間の理解に集中。Issue 化や実装方法は意識しない」と注入。

探索完了後、`.controller-issue/explore-summary.md` に書き出し: 問題の本質（1-3文）、影響範囲、関連コンテキスト、探索で得た洞察。Phase 1 完了前に Issue 構造化を開始してはならない。

TaskUpdate Phase 1 → completed

## Phase 2: 分解判断

TaskCreate 「Phase 2: 分解判断」(status: in_progress)

explore-summary.md を読み込み、単一/複数 Issue を判断。複数の場合は AskUserQuestion で分解内容を確認: [A] この分解で進める [B] 調整 [C] 単一のまま続行。

TaskUpdate Phase 2 → completed

## Phase 3: Per-Issue 精緻化ループ

TaskCreate 「Phase 3: 精緻化（N件）」(status: in_progress)

### Step 3a: 構造化（各 Issue 順次）

各 Issue 候補に対して順に:

1. **構造化**: `/dev:issue-structure` でテンプレート適用（bug/feature）
2. **推奨ラベル抽出**: issue-structure 出力の `## 推奨ラベル` セクションから `ctx/<name>` を抽出し recommended_labels に記録（セクションなし→空）
3. **tech-debt 棚卸し**（該当時のみ）: `/dev:issue-tech-debt-absorb` → Phase 4 で使用

### Step 3b: specialist 並列レビュー

`--quick` 指定時はこのステップをスキップし、Step 3a のみで Phase 3 を完了する。

全 Issue の構造化完了後、全 Issue × 2 specialist を一括並列 spawn（Agent tool）:

```
FOR each structured_issue IN issues:
  Agent(subagent_type="dev:dev:issue-critic", prompt="<review_target>\n{structured_issue.body}\n</review_target>\n\n<target_files>\n{structured_issue.scope_files}\n</target_files>\n\n<related_context>\n{related_issues}\n{deps_yaml_entries}\n</related_context>")
  Agent(subagent_type="dev:dev:issue-feasibility", prompt="<review_target>\n{structured_issue.body}\n</review_target>\n\n<target_files>\n{structured_issue.scope_files}\n</target_files>\n\n<related_context>\n{related_issues}\n{deps_yaml_entries}\n</related_context>")
```

**注意**: Issue body はユーザー入力由来のため、XML タグでコンテキスト境界を明確に分離する。specialist の system prompt（agent frontmatter）とユーザーデータの混同を防ぐ。

**重要**: 全 specialist を単一メッセージで一括発行すること（並列実行）。model は指定不要（agent frontmatter の model: sonnet が適用される）。

### Step 3c: 結果集約・ブロック判定

全 specialist 完了後、結果を集約:

1. **findings 統合**: 全 specialist の findings を Issue 別にマージ
2. **ブロック判定**: `severity == CRITICAL && confidence >= 80` が 1 件以上 → 当該 Issue は Phase 4 ブロック
3. **ユーザー提示**: Issue 別に findings テーブルを表示

```markdown
## specialist レビュー結果

### Issue: <title>

| specialist | status | findings |
|-----------|--------|----------|
| issue-critic | WARN | 2 findings (0 CRITICAL, 1 WARNING, 1 INFO) |
| issue-feasibility | PASS | 0 findings |

#### findings 詳細
| severity | confidence | category | message |
|----------|-----------|----------|---------|
| WARNING | 75 | ambiguity | 受け入れ基準の項目3が定量化されていない |
| INFO | 60 | scope | Phase 2 との境界が明確 |
```

4. **CRITICAL ブロック時**: 「以下の Issue に CRITICAL findings があります。修正後に再実行してください」と表示。修正完了後、Step 3b を再実行可能
5. **split 提案ハンドリング**: `category: scope` の split 提案がある場合、ユーザーに提示し承認を求める。承認後に分割するが、分割後の新 Issue に対して specialist 再レビューは行わない（最大 1 ラウンド）

TaskUpdate Phase 3 → completed

## Phase 4: 一括作成

TaskCreate 「Phase 4: Issue 作成」(status: in_progress)

1. **ユーザー確認（MUST）**: 全候補を提示、承認後に作成
2. **作成**: 単一→`/dev:issue-create`、複数→`/dev:issue-bulk-create`。tech-debt 吸収時は Related セクション付加。recommended_labels がある場合は `--label` 引数に追加
3. **Project Board 同期**: 各 Issue 後 `/dev:project-board-sync N`（失敗は警告のみ）
4. **クリーンアップ**: `.controller-issue/` を削除（中止時も同様）
5. **完了通知**: Issue URL 表示、`/dev:workflow-setup #N` で開発開始を案内

TaskUpdate Phase 4 → completed

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない
- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
