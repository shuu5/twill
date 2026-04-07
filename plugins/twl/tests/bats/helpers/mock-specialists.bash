#!/usr/bin/env bash
# mock-specialists.bash - Issue #144 / Phase 4-A Layer 2
#
# bats workflow-scenarios で specialist 出力を mock するヘルパー。
# 実 specialist (LLM) を呼ばずに checkpoint ファイルを書き出す。
# 現状の workflow-scenarios の trace 順序検証では LLM 出力の中身は使わないが、
# 将来 fix-phase エスカレーションや merge-gate REJECT の分岐 verify を追加する際
# に備え、共通生成関数を集約しておく。

# mock_specialist_pass <step> [path]
# 指定 step の checkpoint を PASS で書き出す。
mock_specialist_pass() {
  local step="$1"
  local path="${2:-${WORKFLOW_SANDBOX:-$BATS_TEST_TMPDIR}/.autopilot/checkpoints/${step}.json}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{"step":"${step}","status":"PASS","findings":[],"confidence":100}
EOF
}

# mock_specialist_critical <step> [path]
# CRITICAL findings 付き checkpoint を書き出す（fix ループ分岐検証用）。
mock_specialist_critical() {
  local step="$1"
  local path="${2:-${WORKFLOW_SANDBOX:-$BATS_TEST_TMPDIR}/.autopilot/checkpoints/${step}.json}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{"step":"${step}","status":"FAIL","findings":[{"severity":"CRITICAL","confidence":90,"message":"mock critical finding"}],"confidence":90}
EOF
}

# mock_specialist_warning <step> [path]
mock_specialist_warning() {
  local step="$1"
  local path="${2:-${WORKFLOW_SANDBOX:-$BATS_TEST_TMPDIR}/.autopilot/checkpoints/${step}.json}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{"step":"${step}","status":"WARN","findings":[{"severity":"WARNING","confidence":50,"message":"mock warning"}],"confidence":50}
EOF
}
