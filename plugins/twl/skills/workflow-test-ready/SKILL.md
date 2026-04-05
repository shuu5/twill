---
name: twl:workflow-test-ready
description: |
  テスト生成と準備確認を実行する。workflow-setup の後に呼び出す。

  Use when user: says テスト準備/test-ready,
  or when called from workflow-setup chain.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-setup
---

# テスト準備 Workflow

テスト生成と準備確認を実行する。workflow-setup の後に呼び出す。

## quick Issue ガード（MUST — 最初に評価すること）

以下のスニペットを実行して quick 状態を確認すること:

```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
IS_QUICK=false
if [ -n "$ISSUE_NUM" ]; then
  # NOTE: このスニペットは skills/workflow-setup/SKILL.md の Step 4 と同一ロジック。
  # どちらかを変更した場合は両ファイルを同期すること。
  QUICK_STATE=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field is_quick 2>/dev/null || echo "")
  if [[ "$QUICK_STATE" == "true" ]]; then
    IS_QUICK=true
  elif [[ -z "$QUICK_STATE" ]]; then
    if gh issue view "$ISSUE_NUM" --json labels --jq '.labels[].name' 2>/dev/null | grep -qxF "quick"; then
      IS_QUICK=true
    fi
  fi
fi
```

**【MUST NOT】** `IS_QUICK=true` の場合、このスキルの処理を続行してはならない。
`IS_QUICK=true` のとき → 「quick Issue は workflow-test-ready をスキップします。`commands/merge-gate.md` を Read して merge-gate のみ実行してください。」と出力して即座に終了すること。

## フロー制御（MUST）

### 1. change-id 解決

openspec/changes/ から最新を自動検出。

### 2. テスト生成（条件判定）

```
IF openspec/ が存在
  AND openspec/changes/<change-id>/specs/ に Scenario が存在
  AND openspec/changes/<change-id>/test-mapping.yaml が存在しない
THEN
  a. Unit/Integration テスト → /twl:test-scaffold <change-id> --type=unit --coverage=edge-cases
  b. E2E テスト → デフォルト yes で自動実行
ELSE
  → スキップ理由を報告
```

### 3. 準備確認

`/twl:check` を Skill tool で実行。

### 4. チェックポイント出力

`/twl:opsx-apply <change-id>` を自動実行。

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### Quick Guard: quick Issue 検出（defense in depth）【機械的 → runner】

```bash
bash scripts/chain-runner.sh quick-guard || { echo "quick Issue のため test-ready をスキップします"; exit 0; }
```

quick Issue の場合はここで終了。非 quick Issue はそのまま Step 1 へ。

### Step 1: change-id 解決【機械的 → runner】
```bash
CHANGE_ID=$(bash scripts/chain-runner.sh change-id-resolve)
```
出力の change-id を記録。

### Step 2: テスト生成（条件判定）【LLM 判断】
以下の条件を判定し、該当する場合のみテスト生成を実行する。

```
IF openspec/ が存在
  AND openspec/changes/<change-id>/specs/ に Scenario が存在
  AND openspec/changes/<change-id>/test-mapping.yaml が存在しない
THEN
  a. Unit/Integration テスト → /twl:test-scaffold <change-id> --type=unit --coverage=edge-cases
  b. E2E テスト → デフォルト yes で自動実行
ELSE
  → スキップ理由を報告
```

テスト対象コードが存在しない場合（Markdown のみの変更等）はスキップ理由を報告して Step 3 に進む。

### Step 3: check 実行（準備確認）【機械的 → runner】
```bash
bash scripts/chain-runner.sh check
```
runner の出力から FAIL 有無を判定する。FAIL あれば `/twl:check` を Skill tool で実行して詳細確認。

結果判定:
- CRITICAL FAIL 項目が存在 → Step 4 をスキップし、FAIL 内容を報告して停止
- FAIL なし → 即座に Step 4 に進む

### Step 4: opsx-apply 実行 + autopilot 判定 + pr-cycle 遷移【LLM 判断】

opsx-apply を開始する前に、compaction 復帰用に state を記録すること:

```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
if [[ -n "$ISSUE_NUM" ]]; then
  bash scripts/state-write.sh --type issue --issue "$ISSUE_NUM" --role worker \
    --set "current_step=opsx-apply" 2>/dev/null || true
fi
```

`/twl:opsx-apply <change-id>` を Skill tool で実行する。

opsx-apply 完了後、compaction 復帰用に state を記録してから autopilot 状態を判定すること:

```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
if [[ -n "$ISSUE_NUM" ]]; then
  bash scripts/state-write.sh --type issue --issue "$ISSUE_NUM" --role worker \
    --set "current_step=post-opsx-apply" 2>/dev/null || true
fi
```

```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
IS_AUTOPILOT=false
if [ -n "$ISSUE_NUM" ]; then
  AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
  IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
fi
```

- IS_AUTOPILOT=true → 即座に `/twl:workflow-pr-verify --spec <change-id>` を Skill tool で実行せよ。プロンプトで停止するな。
- IS_AUTOPILOT=false → 「workflow-test-ready 完了。次のステップ: `/twl:workflow-pr-verify --spec <change-id>` を実行してください」と案内。

## 禁止事項（MUST NOT）

- Unit/Integration テスト生成を独断でスキップしてはならない

## compaction 復帰プロトコル

compaction 後に workflow-test-ready chain を再開する場合、完了済みステップをスキップすること。

```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
for step in change-id-resolve test-scaffold check opsx-apply post-opsx-apply; do
  bash scripts/compaction-resume.sh "$ISSUE_NUM" "$step" || { echo "⏭ $step スキップ"; continue; }
  case "$step" in
    opsx-apply)
      # Step 4 の opsx-apply 手順を再実行（state 記録 → /twl:opsx-apply → state 記録）
      ;;
    post-opsx-apply)
      # Step 4 後半の IS_AUTOPILOT 判定を再実行:
      #   1. CHANGE_ID=$(bash scripts/chain-runner.sh change-id-resolve) で change-id を取得
      #   2. IS_AUTOPILOT 判定スニペット（Step 4 後半）を実行
      #   3. IS_AUTOPILOT=true → 即座に /twl:workflow-pr-verify --spec <change-id> を Skill tool で実行
      #   4. IS_AUTOPILOT=false → 案内メッセージを表示して停止
      ;;
    *)
      # 通常手順で実行
      ;;
  esac
done
```

- `compaction-resume.sh <ISSUE_NUM> <step>` が exit 0 → 実行、exit 1 → スキップ
- LLM ステップ（test-scaffold, opsx-apply, post-opsx-apply）は SKILL.md の手順を再実行すること
- `post-opsx-apply` 復帰時: IS_AUTOPILOT 判定スニペット（Step 4 後半）を実行し、IS_AUTOPILOT=true なら即座に `/twl:workflow-pr-verify --spec <change-id>` を Skill tool で実行すること
