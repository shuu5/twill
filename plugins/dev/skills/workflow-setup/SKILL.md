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
- `--auto` → 自動実行モード（autopilot セッション前提）
- `--auto-merge` → 自動マージモード（--auto を含意）

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

## chain 実行指示（MUST）

以下の順序でステップを実行する。各ステップの COMMAND.md を Read し、Skill tool で自動実行すること。

Step 1: `/dev:init` を Skill tool で実行
→ 以降は各 COMMAND.md のチェックポイントに従い自動進行

### ライフサイクル

| # | 型 | コンポーネント | 説明 |
|---|---|---|---|
| 1 | atomic | init | 開発状態判定 |
| 2 | atomic | worktree-create | worktree 作成 |
| 3 | atomic | project-board-status-update | Project Board Status を In Progress に更新 |
| 4 | atomic | crg-auto-build | CRG グラフ自動ビルド |
| 5 | atomic | opsx-propose | OpenSpec 提案ラッパー |
| 6 | atomic | ac-extract | AC（受け入れ基準）抽出 |

