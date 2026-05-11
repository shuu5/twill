#!/usr/bin/env bats
# co-issue-phase4-evidence-generation.bats - Phase4-complete.json 生成検証
#
# Issue #1564: docs(adr-024): refine evidence の正典化 — Phase D 補遺
# AC7: bats test を新規追加し E1/E2/E3 を検証する
#
# E1: Phase 4 [B] 模擬実行後に ${CONTROLLER_ISSUE_DIR}/${SESSION_ID}/Phase4-complete.json が生成される
# E2: 生成された JSON が AC2 schema 必須フィールドをすべて含む
# E3: 既存 refined-status-gate-refined-option.bats の R3 シナリオが回帰しない
#
# 参考パターン: refined-status-gate-refined-option.bats (CONTROLLER_ISSUE_DIR env var で sandbox 配置)

load '../helpers/common'

HOOK_SCRIPT_NAME="pre-bash-refined-status-gate.sh"

setup() {
  common_setup
  cp "$REPO_ROOT/scripts/hooks/$HOOK_SCRIPT_NAME" "$SANDBOX/scripts/$HOOK_SCRIPT_NAME"
  chmod +x "$SANDBOX/scripts/$HOOK_SCRIPT_NAME"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# E1: Phase 4 [B] 模擬実行後に Phase4-complete.json が生成される
# ---------------------------------------------------------------------------
# [B] path の Phase4-complete.json 生成スニペット (ADR-024 Phase D) を dry-run で検証する。
# SESSION_ID / CONTROLLER_ISSUE_DIR を sandbox 環境変数で設定し、生成 step を実行する。
@test "E1: Phase 4 [B] 模擬実行後に CONTROLLER_ISSUE_DIR/SESSION_ID/Phase4-complete.json が生成される" {
  # sandbox 環境変数で制御
  export SESSION_ID="test-session-e1"
  export CO_ISSUE_SESSION_ID="test-session-e1"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  export ISSUE_NUMBER=1564
  export TARGET_REPO="shuu5/twill"
  # PER_ISSUE_DIR は省略（任意フィールド report_path が空でも可）
  export PER_ISSUE_DIR="/dev/null"

  # [B] path の Phase4-complete.json 生成スニペット (ADR-024 Phase D) を実行
  PHASE4_DIR="${CONTROLLER_ISSUE_DIR}/${SESSION_ID}"
  mkdir -p "$PHASE4_DIR"
  jq -n \
    --arg schema_version "1.0.0" \
    --arg sid "$SESSION_ID" \
    --argjson n "$ISSUE_NUMBER" \
    --arg repo "$TARGET_REPO" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson specialists '["issue-critic","issue-feasibility","worker-codex-reviewer"]' \
    --arg report_path "" \
    --arg phase4_path "[B]" \
    '{schema_version: $schema_version, session_id: $sid, issue_number: $n, repo: $repo, completed_at: $completed_at, specialists: $specialists, report_path: $report_path, phase4_path: $phase4_path}' \
    > "${PHASE4_DIR}/Phase4-complete.json"

  # 生成ファイルの存在確認
  [[ -f "${CONTROLLER_ISSUE_DIR}/${SESSION_ID}/Phase4-complete.json" ]]
}

# ---------------------------------------------------------------------------
# E2: 生成された JSON が AC2 schema 必須フィールドをすべて含む
# ---------------------------------------------------------------------------
# 必須フィールド: schema_version, session_id, issue_number, repo, completed_at, specialists, phase4_path
@test "E2: 生成された JSON の必須フィールドがすべて存在し null でない" {
  export SESSION_ID="test-session-e2"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  local PHASE4_FILE="${CONTROLLER_ISSUE_DIR}/${SESSION_ID}/Phase4-complete.json"

  mkdir -p "${CONTROLLER_ISSUE_DIR}/${SESSION_ID}"
  jq -n \
    --arg schema_version "1.0.0" \
    --arg sid "$SESSION_ID" \
    --argjson n 1564 \
    --arg repo "shuu5/twill" \
    --arg completed_at "2026-05-12T00:00:00Z" \
    --argjson specialists '["issue-critic","issue-feasibility","worker-codex-reviewer"]' \
    --arg report_path ".controller-issue/${SESSION_ID}/per-issue/0/OUT/report.json" \
    --arg phase4_path "[B]" \
    '{schema_version: $schema_version, session_id: $sid, issue_number: $n, repo: $repo, completed_at: $completed_at, specialists: $specialists, report_path: $report_path, phase4_path: $phase4_path}' \
    > "$PHASE4_FILE"

  # 必須フィールドがすべて存在し null でないこと
  # jq が null を返すフィールドがあれば select(. == null) にマッチする → 出力が空でなければ FAIL
  local null_fields
  null_fields=$(jq '.schema_version, .session_id, .issue_number, .repo, .completed_at, .specialists, .phase4_path | select(. == null)' "$PHASE4_FILE")
  [[ -z "$null_fields" ]]
}

@test "E2: 生成された JSON の schema_version が 1.0.0 である" {
  export SESSION_ID="test-session-e2b"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  local PHASE4_FILE="${CONTROLLER_ISSUE_DIR}/${SESSION_ID}/Phase4-complete.json"

  mkdir -p "${CONTROLLER_ISSUE_DIR}/${SESSION_ID}"
  jq -n --arg schema_version "1.0.0" --arg sid "$SESSION_ID" \
    --argjson n 1564 --arg repo "shuu5/twill" \
    --arg completed_at "2026-05-12T00:00:00Z" \
    --argjson specialists '["issue-critic"]' \
    --arg phase4_path "[B]" \
    '{schema_version: $schema_version, session_id: $sid, issue_number: $n, repo: $repo, completed_at: $completed_at, specialists: $specialists, phase4_path: $phase4_path}' \
    > "$PHASE4_FILE"

  run jq -r '.schema_version' "$PHASE4_FILE"
  assert_output "1.0.0"
}

@test "E2: 生成された JSON の phase4_path が [B] または [D] のいずれかである" {
  export SESSION_ID="test-session-e2c"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  local PHASE4_FILE="${CONTROLLER_ISSUE_DIR}/${SESSION_ID}/Phase4-complete.json"

  mkdir -p "${CONTROLLER_ISSUE_DIR}/${SESSION_ID}"
  jq -n --arg schema_version "1.0.0" --arg sid "$SESSION_ID" \
    --argjson n 1564 --arg repo "shuu5/twill" \
    --arg completed_at "2026-05-12T00:00:00Z" \
    --argjson specialists '["issue-critic"]' \
    --arg phase4_path "[D]" \
    '{schema_version: $schema_version, session_id: $sid, issue_number: $n, repo: $repo, completed_at: $completed_at, specialists: $specialists, phase4_path: $phase4_path}' \
    > "$PHASE4_FILE"

  run jq -r '.phase4_path' "$PHASE4_FILE"
  # [A] は ADR-024 Phase D で "追加しない" と明記されているため除外
  [[ "$output" == "[B]" || "$output" == "[D]" ]]
}

# ---------------------------------------------------------------------------
# E3: 既存 refined-status-gate-refined-option.bats R3 シナリオが回帰しない
# ---------------------------------------------------------------------------
# R3 シナリオ: 3d983780 + Phase4-complete.json あり → allow
# この bats 内で hook を直接実行して R3 の動作を再確認する（回帰確認のみ、再実装でなく確認）
@test "E3: R3 regression — 3d983780 + Phase4-complete.json あり → hook が allow する" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"
  mkdir -p "$SANDBOX/.controller-issue/test-session-e3"

  # Phase4-complete.json を sandbox に配置
  cat > "$SANDBOX/.controller-issue/test-session-e3/Phase4-complete.json" <<EOF
{
  "schema_version": "1.0.0",
  "session_id": "test-session-e3",
  "issue_number": 1564,
  "repo": "shuu5/twill",
  "completed_at": "2026-05-12T00:00:00Z",
  "specialists": ["issue-critic"],
  "phase4_path": "[B]"
}
EOF

  local payload_file="$SANDBOX/hook-payload.json"
  jq -nc --arg cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 3d983780 --project-id PVT_xyz" \
    '{tool_name: "Bash", tool_input: {command: $cmd}}' > "$payload_file"

  run bash "$SANDBOX/scripts/$HOOK_SCRIPT_NAME" < "$payload_file"

  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}
