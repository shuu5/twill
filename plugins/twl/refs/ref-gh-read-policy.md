# gh Issue/PR 読み込みポリシー（ref-gh-read-policy）

## 概要

twill plugin 内で `gh issue view` / `gh pr view` を使用する際の型ルール。
**content-reading**（内容理解目的）と **meta-only**（属性取得目的）を区別し、前者は必ず body + 全 comments を取得する。

## 判定ルール

| 読み込み目的 | 分類 | 必要なフィールド | 実装方法 |
|---|---|---|---|
| Issue/PR の仕様・制約・議論を LLM やスクリプトが読解して判断に使う | **content-reading** | body + 全 comments | `gh_read_issue_full` / `gh_read_pr_full` |
| 属性値の取得（状態確認・ラベル検査・番号確認など） | **meta-only** | 必要な属性フィールドのみ | `gh issue view --json <field>` |

## content-reading: 共通ヘルパー使用（MUST）

content-reading 目的の読み込みは必ず `scripts/lib/gh-read-content.sh` の共通ヘルパーを経由しなければならない（SHALL）。

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/gh-read-content.sh"

# Issue body + 全 comments を取得
content=$(gh_read_issue_full <issue-number> [--repo <owner/repo>])

# PR body + 全 comments を取得
content=$(gh_read_pr_full <pr-number> [--repo <owner/repo>])
```

- 切り詰めは行わない（SHALL NOT）
- エラー時は空文字列を返し、stderr に警告を出力する
- `--repo` フラグで cross-repo 対応

## meta-only: 属性取得のみ（対象外）

以下の読み込みは Issue/PR の内容を読解しないため、本ポリシーの対象外。`gh issue view --json <field>` で必要なフィールドのみ取得して良い。

| フィールド | 用途例 |
|---|---|
| `state` | close 状態チェック（autopilot-phase-sanity, orchestrator, merge-gate 等） |
| `labels` | quick 判定、label 検査（orchestrator, launch, chain-runner, merge-gate 等） |
| `number` | 存在チェック（autopilot-plan, project-board-backfill 等） |
| `id` | GraphQL node id（architect-issue-create 等） |
| `mergeCommit` | PR merge SHA（merge-gate 等） |
| `files` | PR file list for self-improve/retrospective |
| `title` | ログ表示目的（intervene-auto 等） |

## 実装チェックポイント

新しい gh 読み込みコードを書く場合:

1. 「Issue/PR の仕様・制約・議論を読解して判断に使うか？」を確認
2. YES → `gh_read_issue_full` / `gh_read_pr_full` を使用
3. NO (属性取得のみ) → `gh issue view --json <field>` で必要フィールドのみ

静的検査: `rg "gh issue view.*--json body" plugins/twl` の hit が meta-only 箇所のみであることを確認（content-reading 用途は 0 件）。

## 参照

- 実装: `plugins/twl/scripts/lib/gh-read-content.sh`
- アーキテクチャポリシー: `architecture/domain/contexts/issue-mgmt.md` IM-8
- 関連 Issue: #499
