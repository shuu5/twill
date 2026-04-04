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
| 2.4 | crg-auto-build | next-step 判定 → atomic |
| — | arch-ref コンテキスト取得 | next-step 判定 → SKILL.md 固有 |
| 3 | opsx-propose | next-step 判定 → atomic |
| 3.5 | ac-extract | next-step 判定 → atomic |
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

### Step 1: init（開発状態判定）【機械的 → runner】
```bash
bash scripts/chain-runner.sh init "$ISSUE_NUM"
```
出力の JSON から `recommended_action` を記録。

### Step 2: worktree-create（worktree 作成）【機械的 → runner】
init の `recommended_action` が `worktree` の場合のみ。
```bash
bash scripts/chain-runner.sh worktree-create "$ARGUMENTS"
```

### Step 2.3: project-board-status-update（Project Board 更新）【機械的 → runner】
ISSUE_NUM がある場合のみ。
```bash
bash scripts/chain-runner.sh board-status-update "$ISSUE_NUM"
```

### Step 2.4: crg-auto-build（CRG グラフビルド）【next-step 判定 → LLM 判断】
以下で次ステップを確認し、`crg-auto-build` を返した場合のみ実行:
```bash
NEXT=$(bash scripts/chain-runner.sh next-step "$ISSUE_NUM" "board-status-update")
```
`NEXT=crg-auto-build` → `commands/crg-auto-build.md` を Read → 実行。それ以外 → スキップ。

### Step 2.5: arch-ref コンテキスト取得【next-step 判定 → runner】
```bash
NEXT=$(bash scripts/chain-runner.sh next-step "$ISSUE_NUM" "crg-auto-build")
```
`NEXT=arch-ref` の場合のみ実行:
```bash
bash scripts/chain-runner.sh arch-ref "$ISSUE_NUM"
```
出力されたパスがあれば Read して ARCH_CONTEXT として保持。

### Step 3: opsx-propose（OpenSpec 提案）【next-step 判定 → LLM 判断】
```bash
NEXT=$(bash scripts/chain-runner.sh next-step "$ISSUE_NUM" "arch-ref")
```
`NEXT=opsx-propose` の場合のみ: init の `recommended_action` に基づき「ドメインルール > OpenSpec 分岐条件」に従い実行。
`commands/opsx-propose.md` を Read → 実行。

### Step 3.5: ac-extract（AC 抽出）【next-step 判定 → runner】
```bash
NEXT=$(bash scripts/chain-runner.sh next-step "$ISSUE_NUM" "opsx-propose")
```
`NEXT=ac-extract` の場合のみ:
```bash
bash scripts/chain-runner.sh ac-extract
```

### Step 4: workflow-test-ready へ遷移【quick 判定 → autopilot 判定 → runner + LLM】

以下の bash スニペットを実行して quick 状態と autopilot 状態を判定すること:

```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
IS_AUTOPILOT=false
IS_QUICK=false
if [ -n "$ISSUE_NUM" ]; then
  AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
  IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
  # NOTE: このスニペットは skills/workflow-test-ready/SKILL.md の quick ガードと同一ロジック。
  # どちらかを変更した場合は両ファイルを同期すること。
  QUICK_STATE=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field is_quick 2>/dev/null || echo "")
  if [[ "$QUICK_STATE" == "true" ]]; then
    IS_QUICK=true
  elif [[ -z "$QUICK_STATE" ]]; then
    # fallback: gh API でラベル確認
    if gh issue view "$ISSUE_NUM" --json labels --jq '.labels[].name' 2>/dev/null | grep -qxF "quick"; then
      IS_QUICK=true
    fi
  fi
fi
```

**【MUST NOT】** `IS_QUICK=true` かつ `IS_AUTOPILOT=true` の場合、`/dev:workflow-test-ready` を Skill tool で実行してはならない。

分岐（IS_QUICK チェックを IS_AUTOPILOT チェックより先に評価すること）:

- IS_QUICK=true かつ IS_AUTOPILOT=true → workflow-test-ready を呼び出さずに、「直接実装 → commit → push → `gh pr create --fill --label quick` → `commands/merge-gate.md` を Read して merge-gate のみ実行せよ」と案内せよ。プロンプトで停止するな。
- IS_QUICK=false かつ IS_AUTOPILOT=true → 即座に `/dev:workflow-test-ready` を Skill tool で実行せよ。プロンプトで停止するな。
- IS_AUTOPILOT=false → 「setup chain 完了。次のステップ: `/dev:workflow-test-ready` を実行してください」と案内。

## compaction 復帰プロトコル

compaction 後に chain を再開する場合、各ステップ実行前に以下を確認すること:

```bash
ISSUE_NUM=<N>
bash scripts/compaction-resume.sh "$ISSUE_NUM" "<step>" || { echo "スキップ"; continue; }
# exit 0 → 実行、exit 1 → スキップ（完了済み）
```

