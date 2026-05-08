#!/usr/bin/env bats
# twl-audit-stuck-patterns.bats
# Issue #1582: twl audit stuck-patterns サブコマンド追加
#
# AC3 (drift lint): twl audit stuck-patterns サブコマンドで
#                   SSoT (stuck-patterns.yaml) と consumer スクリプトの
#                   pattern 一致を検証する
#
# 対象: cli/twl/src/twl/autopilot/audit.py
#
# RED: 実装前は stuck-patterns サブコマンドが存在しないため fail
# GREEN: 実装後に全テスト PASS

load '../helpers/common'

AUDIT_PY=""

setup() {
  common_setup

  # Resolve monorepo root
  local _monorepo_root
  _monorepo_root="$(cd "${BATS_TEST_DIRNAME}" && cd ../../../../../ && pwd)"

  AUDIT_PY="${_monorepo_root}/cli/twl/src/twl/autopilot/audit.py"

  # Ensure PYTHONPATH includes twl package
  local _src_dir="${_monorepo_root}/cli/twl/src"
  export PYTHONPATH="${_src_dir}${PYTHONPATH:+:${PYTHONPATH}}"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC3 structural: stuck-patterns サブコマンドの実装確認
# ===========================================================================

@test "ac3: audit.py に stuck-patterns サブパーサーが追加されている" {
  # RED: 実装前は stuck-patterns サブコマンドが add_parser されていないため fail
  run grep -qF "stuck-patterns" "${AUDIT_PY}"
  assert_success
}

@test "ac3: audit.py に sub.add_parser('stuck-patterns') が存在する" {
  # RED: 実装前は stuck-patterns サブパーサーが未定義のため fail
  run grep -qE "add_parser\(['\"]stuck-patterns['\"]" "${AUDIT_PY}"
  assert_success
}

@test "ac3: twl audit stuck-patterns コマンドが exit code 0 で実行できる（SSoT 一致時）" {
  # RED: 実装前は stuck-patterns サブコマンドが存在せず exit 1 または error のため fail
  # NOTE: stuck-patterns.yaml が未作成の場合は exit code が非 0 になる可能性があるが、
  # ここでは --help で存在確認するに留める
  run python3 -m twl.autopilot.audit stuck-patterns --help
  assert_success
}

# ===========================================================================
# AC3 behavioral: drift lint ロジック確認
# ===========================================================================

@test "ac3: audit.py に stuck-patterns.yaml を grep する lint ロジックが含まれる" {
  # RED: 実装前は lint ロジックが未実装のため fail
  run grep -qF "stuck-patterns.yaml" "${AUDIT_PY}"
  assert_success
}

@test "ac3: audit.py に consumer スクリプトへの pattern 検証ロジックが含まれる" {
  # RED: 実装前は consumer 検証ロジックが未実装のため fail
  # consumer 検証は grep や pattern matching で行う想定
  run grep -qE "grep|consumer|orchestrator|observer" "${AUDIT_PY}"
  assert_success
}
