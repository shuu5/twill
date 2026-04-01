---
name: dev:workflow-setup
description: |
  開発準備ワークフロー（worktree作成 → OpenSpec → テスト準備）。
  setup chain のオーケストレーター。

  Use when user: says 開発準備/setup/ワークフロー開始,
  or when called from co-autopilot workflow.
type: workflow
effort: medium
spawnable_by:
- user
- co-autopilot
---

# 開発準備 Workflow（chain-driven）

setup chain のオーケストレーター。chain ステップの実行順序は deps.yaml で宣言されている。
本 SKILL.md には chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 1 | init | atomic |
| 2 | worktree-create | atomic |
| 2.3 | project-board-status-update | atomic |
| 2.4 | crg-auto-build | atomic |
| — | arch-ref コンテキスト取得 | SKILL.md 固有 |
| 3 | opsx-propose | atomic |
| 3.5 | ac-extract | atomic |
| → | workflow-test-ready | workflow（controller 経由） |

## ドメインルール

### 引数解析

`$ARGUMENTS` から以下を解析:
- `#N` → Issue 番号（`ISSUE_NUM`）。worktree-create にそのまま渡す

### arch-ref コンテキスト取得（Step 2.5）

Issue 起点の場合のみ実行。

- `gh issue view $ISSUE_NUM --json body --jq '.body'` で body 取得
- `gh api repos/{owner}/{repo}/issues/${ISSUE_NUM}/comments` でコメント取得
- `<!-- arch-ref-start -->` タグがあれば、タグ間の `architecture/` パスを Read

**制約**:
- 最大 5 件
- `..` を含むパスは拒否
- ファイル不在は警告のみ
- タグなし → ARCH_CONTEXT = なし

### OpenSpec 分岐条件（Step 3）

init の `recommended_action` に基づき:

| recommended_action | 動作 |
|---|---|
| `propose` | opsx-propose を実行。ARCH_CONTEXT があれば `## Architecture Context` として注入 |
| `apply` | 実装開始を案内 |
| `direct` | 直接実装可能と案内 |

OpenSpec artifact の言語: 構造キーワード・ヘッダーは英語、説明文・要件名は日本語。

### Project Board Status 更新（Step 2.3）

ISSUE_NUM が存在する場合のみ実行。なければスキップ（メッセージ出力なし）。

### 軽微変更

10 行未満の変更は直接実装可。slug 生成は `worktree-create.sh` に委譲。

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### Step 1: init（開発状態判定）
`/dev:init` を Skill tool で実行。結果の `recommended_action` を記録。

### Step 2: worktree-create（worktree 作成）
`commands/worktree-create.md` を Read → 指示に従い実行。
init の `recommended_action` が `worktree` の場合のみ。

### Step 2.3: project-board-status-update（Project Board 更新）
ISSUE_NUM がある場合のみ。`commands/project-board-status-update.md` を Read → 実行。

### Step 2.4: crg-auto-build（CRG グラフビルド）
`commands/crg-auto-build.md` を Read → 実行。

### Step 2.5: arch-ref コンテキスト取得
Issue 起点の場合のみ。上記「ドメインルール > arch-ref コンテキスト取得」に従い実行。

### Step 3: opsx-propose（OpenSpec 提案）
init の `recommended_action` に基づき「ドメインルール > OpenSpec 分岐条件」に従い実行。
`commands/opsx-propose.md` を Read → 実行。

### Step 3.5: ac-extract（AC 抽出）
`commands/ac-extract.md` を Read → 実行。

### Step 4: workflow-test-ready へ遷移

autopilot 判定（ISSUE_NUM は引数解析で取得済み）:
```bash
IS_AUTOPILOT=false
if [ -n "${ISSUE_NUM:-}" ]; then
  AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
  IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
fi
```

- IS_AUTOPILOT=true: 自動的に `/dev:workflow-test-ready` を Skill tool で実行して chain を継続。
- IS_AUTOPILOT=false: 「setup chain 完了。`/dev:workflow-test-ready` で次に進めます」と案内。

