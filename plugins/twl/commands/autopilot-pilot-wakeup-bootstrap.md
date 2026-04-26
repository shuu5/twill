---
type: atomic
tools: [Bash]
effort: medium
maxTurns: 10
---
# Pilot Wake-up Bootstrap（autopilot-pilot-wakeup-bootstrap）

orchestrator を nohup/disown で起動する one-shot atomic。Step A に相当。

## 前提変数（呼出元から引き継ぐ MUST）

- `$AUTOPILOT_DIR`: state file ディレクトリの SSOT
- `$PROJECT_DIR`: bare repo の親ディレクトリ
- `$PHASE_NUM`: 現在の Phase 番号
- `$REPOS_ARG`: クロスリポジトリ引数（省略可）

## Step A: orchestrator 起動（nohup/disown）

Pilot の Bash context 外で持続実行するため **nohup/disown** を使用すること（不変条件 M — Pilot timeout/cancel による chain 停止防止）。`--session` には `$AUTOPILOT_DIR` を使った絶対パスを指定すること（相対パス・セッション ID 直接渡しは不可）:

<!-- HOTFIX #732 (commit bf5add9): 下記コードブロックの nohup 行は ${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-orchestrator.sh 絶対パスを維持すること。相対パスに戻すと Wave 遷移で即死する。-->

> ⚠️ **HOTFIX #732**: 下記コードブロックの `nohup bash "${CLAUDE_PLUGIN_ROOT}/...` は絶対パス指定を維持すること。相対パスに戻すと Wave 遷移で即死する。

```bash
mkdir -p "${AUTOPILOT_DIR}/trace"
# session_id を取得（Wave 間ログ分離のため）。session.json 不在時は unknown にフォールバックし警告を出す
SESSION_ID=$(jq -r '.session_id // "unknown"' "${AUTOPILOT_DIR}/session.json" 2>/dev/null || echo "unknown")
if [[ "$SESSION_ID" == "unknown" ]]; then
  echo "WARN: session.json が不在またはパース失敗。Wave ログ分離が無効になります" >&2
elif [[ ! "$SESSION_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "WARN: SESSION_ID に不正な文字が含まれています。unknown にフォールバックします: $SESSION_ID" >&2
  SESSION_ID="unknown"
fi
_ORCH_LOG="${AUTOPILOT_DIR}/trace/orchestrator-phase-${PHASE_NUM}-${SESSION_ID}.log"
cd "${PROJECT_DIR}/main" 2>/dev/null || cd "${PROJECT_DIR}" || true
nohup bash "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-orchestrator.sh" \
  --plan "${AUTOPILOT_DIR}/plan.yaml" \
  --phase "$PHASE_NUM" \
  --session "${AUTOPILOT_DIR}/session.json" \
  --project-dir "$PROJECT_DIR" \
  --autopilot-dir "$AUTOPILOT_DIR" \
  ${REPOS_ARG:+"$REPOS_ARG"} \
  >> "$_ORCH_LOG" 2>&1 &
disown
_ORCH_PID=$!
echo "[autopilot-pilot-wakeup-bootstrap] orchestrator PID=${_ORCH_PID} 起動 (nohup) → ログ: ${_ORCH_LOG}" >&2
```

## 出力

起動した orchestrator の PID とログパスを stderr に出力する。`$_ORCH_LOG` と `$_ORCH_PID` は呼出元スコープに引き継ぐこと（`autopilot-pilot-wakeup-poll` が参照する）。

<!-- NOTE: Pilot 用 atomic グループ（autopilot-pilot-precheck / autopilot-pilot-rebase / autopilot-multi-source-verdict 等）の一員。設計原則 P1 (ADR-010) 参照。不変条件 M は nohup/disown の維持として本ファイルに体現される。 -->
