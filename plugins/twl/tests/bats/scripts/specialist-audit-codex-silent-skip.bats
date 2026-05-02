#!/usr/bin/env bats
# specialist-audit-codex-silent-skip.bats
#
# Issue #1289: specialist-audit.sh — codex silent_skip 率 > 50% で FAIL 昇格
#
# AC-4: specialist-audit.sh が対象セッションの findings.yaml を走査して
#       codex silent_skip 率を計算し、> 50%(exclusive) の場合に
#       JSON 出力で "status":"FAIL" に昇格すること
#       (既存 specialist_missing チェックと OR 結合)
#
# RED フェーズ:
#   specialist-audit.sh に codex silent_skip チェック未実装 → 全テスト FAIL

load '../helpers/common'

AUDIT_SCRIPT=""

# create_findings_yaml <dir> <has_reason: true|false>
# findings.yaml を作成。has_reason=false の場合は silent skip (reason なし findings: [])
create_findings_yaml() {
  local dir="$1"
  local has_reason="$2"
  mkdir -p "$dir"
  if [[ "$has_reason" == "true" ]]; then
    cat > "$dir/findings.yaml" <<EOF
worker-codex-reviewer:
  status: PASS
  reason: "401 Unauthorized"
  findings:
    - severity: info
      message: "codex skipped due to auth error"
EOF
  else
    cat > "$dir/findings.yaml" <<EOF
worker-codex-reviewer:
  status: PASS
  findings: []
EOF
  fi
}

setup() {
  common_setup
  AUDIT_SCRIPT="$SANDBOX/scripts/specialist-audit.sh"
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  stub_command "pr-review-manifest.sh" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-4: silent_skip > 50% (exclusive) → status:FAIL
# ---------------------------------------------------------------------------

@test "ac4-silent-skip-over-50pct-is-fail: silent_skip 51% (51/100) で status:FAIL になる" {
  # RED: codex silent_skip チェック未実装 → status:PASS のまま → FAIL
  local session_dir="$SANDBOX/.controller-issue/test-session/per-issue/999/rounds"
  mkdir -p "$session_dir"

  # 51 件の silent skip (reason なし)
  for i in $(seq 1 51); do
    create_findings_yaml "$session_dir/round${i}" "false"
  done
  # 49 件は reason あり
  for i in $(seq 52 100); do
    create_findings_yaml "$session_dir/round${i}" "true"
  done

  run bash "$AUDIT_SCRIPT" \
    --jsonl /dev/null \
    --manifest-file /dev/null \
    --codex-session-dir "$session_dir" \
    --json

  [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
  echo "$output" | grep -q '"status":"FAIL"'
}

# ---------------------------------------------------------------------------
# AC-4: silent_skip 50% (exactly) → status:PASS (exclusive = 50% は PASS)
# ---------------------------------------------------------------------------

@test "ac4-silent-skip-exactly-50pct-is-pass: silent_skip 50% (5/10) で status:PASS になる" {
  # 50% ちょうどは PASS (exclusive: > 50% のみ FAIL)
  local session_dir="$SANDBOX/.controller-issue/test-session2/per-issue/999/rounds"
  mkdir -p "$session_dir"

  for i in $(seq 1 5); do
    create_findings_yaml "$session_dir/round${i}" "false"
  done
  for i in $(seq 6 10); do
    create_findings_yaml "$session_dir/round${i}" "true"
  done

  run bash "$AUDIT_SCRIPT" \
    --jsonl /dev/null \
    --manifest-file /dev/null \
    --codex-session-dir "$session_dir" \
    --json

  echo "$output" | grep -q '"status":"PASS"'
}

# ---------------------------------------------------------------------------
# AC-4: codex entries なし → status:PASS (silent_skip チェック対象外)
# ---------------------------------------------------------------------------

@test "ac4-no-codex-entries-is-pass: worker-codex-reviewer エントリなし → status:PASS" {
  local session_dir="$SANDBOX/.controller-issue/test-session3/per-issue/999/rounds"
  mkdir -p "$session_dir"
  # worker-codex-reviewer エントリを含まない findings.yaml
  mkdir -p "$session_dir/round1"
  cat > "$session_dir/round1/findings.yaml" <<EOF
worker-code-reviewer:
  status: PASS
  findings: []
EOF

  run bash "$AUDIT_SCRIPT" \
    --jsonl /dev/null \
    --manifest-file /dev/null \
    --codex-session-dir "$session_dir" \
    --json

  echo "$output" | grep -q '"status":"PASS"'
}

# ---------------------------------------------------------------------------
# AC-4: specialist_missing FAIL + silent_skip PASS → OR 結合で status:FAIL
# ---------------------------------------------------------------------------

@test "ac4-or-combine: specialist_missing FAIL のみでも status:FAIL になる (OR 結合維持)" {
  # 既存の specialist_missing FAIL ロジックが OR 結合で機能すること (regression テスト)
  local session_dir="$SANDBOX/.controller-issue/test-session4/per-issue/999/rounds"
  mkdir -p "$session_dir"
  # silent_skip 0% (全て reason あり) でも specialist_missing があれば FAIL
  create_findings_yaml "$session_dir/round1" "true"

  # manifest に worker-security-reviewer を要求するが JSONL に含まれない
  local manifest_file="$SANDBOX/test-manifest.txt"
  echo "worker-security-reviewer" > "$manifest_file"

  local jsonl_file="$SANDBOX/test.jsonl"
  echo '{"type":"tool_use","subagent_type":"twl:twl:worker-code-reviewer"}' > "$jsonl_file"

  run bash "$AUDIT_SCRIPT" \
    --jsonl "$jsonl_file" \
    --manifest-file "$manifest_file" \
    --codex-session-dir "$session_dir" \
    --json

  echo "$output" | grep -q '"status":"FAIL"'
}

# ---------------------------------------------------------------------------
# AC-4: su-observer grep 契約 "status":"FAIL" 互換確認
# ---------------------------------------------------------------------------

@test "ac4-grep-contract: JSON 出力の status フィールドが grep 契約 '\"status\":\"FAIL\"' にマッチする" {
  local session_dir="$SANDBOX/.controller-issue/test-session5/per-issue/999/rounds"
  mkdir -p "$session_dir"

  # 51件 silent skip
  for i in $(seq 1 6); do
    create_findings_yaml "$session_dir/round${i}" "false"
  done
  for i in $(seq 7 10); do
    create_findings_yaml "$session_dir/round${i}" "true"
  done

  run bash "$AUDIT_SCRIPT" \
    --jsonl /dev/null \
    --manifest-file /dev/null \
    --codex-session-dir "$session_dir" \
    --json

  # su-observer は 'grep "status":"FAIL"' で検知する
  echo "$output" | grep -q '"status":"FAIL"'
}
