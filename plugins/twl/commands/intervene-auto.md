---
type: atomic
tools: [Bash]
effort: low
---
# Layer 0 自動介入（intervene-auto）

Observer が自動実行する Layer 0 介入。non_terminal_chain_end 回復と Worker PR 未作成に対応する。

## 引数

- `--pattern <id>`: 介入パターン ID（`non-terminal-recovery` | `pr-create`）
- `--issue <num>`: 対象 Issue 番号
- `--branch <name>`: 対象 branch 名

## フロー

### Step 1: パターン検証

引数の `--pattern` を確認し、対応するパターンの前提条件を検証する。

**non-terminal-recovery の前提条件チェック**:

```bash
# PR 存在確認
gh pr list --head "$BRANCH" --json number,url --jq '.[0].url'
```

PR が存在しない場合はエラーを報告して終了。PR URL を記録する。

**pr-create の前提条件チェック**:

```bash
# 二重確認: PR が本当に存在しないか
gh pr list --head "$BRANCH" --json number,url --jq '.[0].url'
```

PR が既に存在する場合は「PR already exists」を報告して正常終了。

### Step 2: 修復実行

**non-terminal-recovery**:

```bash
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$(git rev-parse --show-toplevel)/.autopilot}"

# state を running に戻す
python3 -m twl.autopilot.state write \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "$ISSUE_NUM" --role worker \
  --set "status=running"

# force-done で merge-ready に遷移
python3 -m twl.autopilot.state write \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "$ISSUE_NUM" --role worker \
  --set "status=merge-ready" --force-done

# merge-gate 実行
python3 -m twl.autopilot.mergegate merge --force \
  --issue "$ISSUE_NUM" \
  --autopilot-dir "$AUTOPILOT_DIR"
```

**pr-create**:

```bash
# Issue タイトルを取得して PR 作成
ISSUE_TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title')
gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "$ISSUE_TITLE" \
  --body "Closes #${ISSUE_NUM}"
```

### Step 3: InterventionRecord 記録

```bash
OBSERVATION_DIR="$(git rev-parse --show-toplevel)/.observation/interventions"
mkdir -p "$OBSERVATION_DIR"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
cat > "$OBSERVATION_DIR/${TIMESTAMP}-${PATTERN_ID}.json" <<JSON
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pattern_id": "${PATTERN_ID}",
  "layer": "auto",
  "issue_num": ${ISSUE_NUM},
  "branch": "${BRANCH}",
  "action_taken": "${ACTION_TAKEN}",
  "result": "${RESULT}",
  "notes": ""
}
JSON
```

## 出力

- 成功: `✓ Layer 0 Auto介入完了: <pattern-id> (issue #<num>)`
- 失敗: `✗ 介入失敗: <reason>`（ワークフローを停止しない）
