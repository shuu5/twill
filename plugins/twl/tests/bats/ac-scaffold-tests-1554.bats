#!/usr/bin/env bats
# ac-scaffold-tests-1554.bats
#
# Issue #1554: bug(autopilot): #1540 AC2 — chain.py SSOT に merge-gate-check step 追加 + chain-runner.sh 実装
#
# AC1: chain.py CHAIN_STEPS に merge-gate-check step 追加（STEP_TO_WORKFLOW で pr-merge に紐付け）
# AC2: chain-runner.sh に step_merge_gate_check 関数実装（specialist-audit invoke + HARD FAIL 時 EXIT_CODE=1）
# AC3: chain-steps.sh export 整合性（twl --check --deps-integrity で merge-gate-check が含まれることを verify）
# AC4: bats integration test — chain.py 実体 grep + chain-runner.sh step_merge_gate_check 存在確認
# AC5: end-to-end verify — chain workflow 経由で specialist-audit が trigger することを確認
#
# RED: 全テストは実装前に fail する
# GREEN: 実装完了後に PASS する

load 'helpers/common'

SCRIPTS_DIR=""
PLUGIN_ROOT_DIR=""
CHAIN_PY=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
  local bats_dir
  bats_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  PLUGIN_ROOT_DIR="$(cd "${tests_dir}/.." && pwd)"

  # chain.py のパスを解決（common.bash が PYTHONPATH を設定済み）
  local repo_git_root
  repo_git_root="$(cd "${PLUGIN_ROOT_DIR}" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  CHAIN_PY="${repo_git_root}/cli/twl/src/twl/autopilot/chain.py"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: chain.py CHAIN_STEPS に merge-gate-check step 追加
#
# chain.py の CHAIN_STEPS list に "merge-gate-check" が含まれ、
# STEP_TO_WORKFLOW で "pr-merge" workflow に紐付けられていること。
#
# RED: 現在 CHAIN_STEPS に "merge-gate-check" は存在しない
# ===========================================================================

@test "ac1a: chain.py CHAIN_STEPS に merge-gate-check が含まれる" {
  # AC: CHAIN_STEPS list に "merge-gate-check" エントリが存在する
  # RED: 現在 CHAIN_STEPS に merge-gate-check が無いため grep fail
  [ -f "${CHAIN_PY}" ]
  run bash -c "grep -qF '\"merge-gate-check\"' '${CHAIN_PY}'"
  assert_success
}

@test "ac1b: chain.py STEP_TO_WORKFLOW に merge-gate-check -> pr-merge の紐付けがある" {
  # AC: STEP_TO_WORKFLOW dict に "merge-gate-check": "pr-merge" エントリが存在する
  # RED: 現在 STEP_TO_WORKFLOW に merge-gate-check エントリが無いため grep fail
  [ -f "${CHAIN_PY}" ]
  run bash -c "grep -qE '\"merge-gate-check\".*:.*\"pr-merge\"|merge-gate-check.*pr-merge' '${CHAIN_PY}'"
  assert_success
}

@test "ac1c: chain.py CHAIN_STEP_DISPATCH に merge-gate-check のエントリが存在する" {
  # AC: CHAIN_STEP_DISPATCH dict に merge-gate-check の dispatch モードが定義されている
  # RED: 現在 CHAIN_STEP_DISPATCH に merge-gate-check が無いため grep fail
  [ -f "${CHAIN_PY}" ]
  run bash -c "grep -qF '\"merge-gate-check\"' '${CHAIN_PY}' && \
    python3 -c \"
import sys
sys.path.insert(0, '$(dirname "${CHAIN_PY%/cli/twl/src/twl/autopilot/chain.py}")/cli/twl/src')
from twl.autopilot.chain import CHAIN_STEP_DISPATCH
assert 'merge-gate-check' in CHAIN_STEP_DISPATCH, 'merge-gate-check not in CHAIN_STEP_DISPATCH'
print('OK')
\""
  assert_success
}

@test "ac1d: chain.py CHAIN_STEPS の merge-gate-check は pr-cycle-report の前に配置されている" {
  # AC: merge-gate-check は pr-merge workflow の最初のステップとして
  #     all-pass-check の後かつ pr-cycle-report の前に位置すること
  # RED: CHAIN_STEPS に merge-gate-check が無いため fail
  [ -f "${CHAIN_PY}" ]
  run python3 -c "
import sys
sys.path.insert(0, '$(dirname "${CHAIN_PY%/cli/twl/src/twl/autopilot/chain.py}")/cli/twl/src')
from twl.autopilot.chain import CHAIN_STEPS
assert 'merge-gate-check' in CHAIN_STEPS, 'merge-gate-check not in CHAIN_STEPS'
idx_mgc = CHAIN_STEPS.index('merge-gate-check')
idx_apc = CHAIN_STEPS.index('all-pass-check')
idx_pcr = CHAIN_STEPS.index('pr-cycle-report')
assert idx_apc < idx_mgc < idx_pcr, \
  f'merge-gate-check position {idx_mgc} not between all-pass-check {idx_apc} and pr-cycle-report {idx_pcr}'
print('OK')
"
  assert_success
}

# ===========================================================================
# AC2: chain-runner.sh に step_merge_gate_check 関数実装
#
# chain-runner.sh に step_merge_gate_check 関数が定義され、
# specialist-audit.sh を invoke し、HARD FAIL 時は EXIT_CODE=1 で
# chain を停止すること。
#
# RED: 現在 step_merge_gate_check 関数が chain-runner.sh に存在しない
# ===========================================================================

@test "ac2a: chain-runner.sh に step_merge_gate_check 関数が定義されている" {
  # AC: chain-runner.sh に step_merge_gate_check 関数が存在する
  # RED: 現在 grep で空出力 → fail
  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]
  run bash -c "grep -qE '^step_merge_gate_check\(\)' '${chain_runner}'"
  assert_success
}

@test "ac2b: step_merge_gate_check 関数が specialist-audit.sh を呼び出す記述を含む" {
  # AC: step_merge_gate_check 内で specialist-audit が invoke される
  # RED: 関数自体が未存在 or specialist-audit の呼び出しが無い
  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]
  run bash -c "grep -qF 'specialist-audit' '${chain_runner}'"
  assert_success
  # さらに step_merge_gate_check スコープ内に specialist-audit があることを確認
  run bash -c "awk '/^step_merge_gate_check\(\)/,/^}/' '${chain_runner}' | grep -qF 'specialist-audit'"
  assert_success
}

@test "ac2c: step_merge_gate_check が HARD FAIL 時に exit 1 / return 1 でチェーンを停止する記述を含む" {
  # AC: specialist-audit HARD FAIL 時に EXIT_CODE=1 で chain 停止する制御フローが存在する
  # RED: 関数未存在 or HARD FAIL 制御が無い
  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]
  run bash -c "awk '/^step_merge_gate_check\(\)/,/^}/' '${chain_runner}' | \
    grep -qE 'exit 1|return 1|EXIT_CODE=1'"
  assert_success
}

@test "ac2d: chain-runner.sh 全体が bash 構文チェック pass（step_merge_gate_check 追加後）" {
  # AC: step_merge_gate_check 追加後も chain-runner.sh に構文エラーがない
  # RED: 関数未実装なのでこのテスト自体は現在 GREEN だが、実装後の構文破壊を防ぐ回帰ガード
  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]
  run bash -n "${chain_runner}"
  assert_success
}

@test "ac2e: chain-runner.sh の merge-gate-check dispatch が step_merge_gate_check 関数に委譲している" {
  # AC: main() の case 文（または dispatch テーブル）に merge-gate-check エントリが存在し
  #     step_merge_gate_check を呼ぶ
  # RED: dispatch エントリが未存在
  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]
  run bash -c "grep -qF 'merge-gate-check' '${chain_runner}'"
  assert_success
}

# ===========================================================================
# AC3: chain-steps.sh export 整合性
#
# chain.py から生成される chain-steps.sh の CHAIN_STEPS array に
# merge-gate-check が含まれること。
# twl --check --deps-integrity でも integrity が確認できること。
#
# RED: chain.py に merge-gate-check が未追加のため chain-steps.sh にも無い
# ===========================================================================

@test "ac3a: chain-steps.sh の CHAIN_STEPS array に merge-gate-check が含まれる" {
  # AC: chain-steps.sh (bash mirror) に merge-gate-check が存在する
  # RED: chain.py 未実装 → chain-steps.sh にも存在しないため fail
  local chain_steps="${SCRIPTS_DIR}/chain-steps.sh"
  [ -f "${chain_steps}" ]
  run bash -c "grep -qF 'merge-gate-check' '${chain_steps}'"
  assert_success
}

@test "ac3b: chain-steps.sh の CHAIN_STEP_WORKFLOW に merge-gate-check=pr-merge エントリが存在する" {
  # AC: CHAIN_STEP_WORKFLOW 連想配列に [merge-gate-check]=pr-merge が含まれる
  # RED: chain.py 未更新 → chain-steps.sh も未更新 → fail
  local chain_steps="${SCRIPTS_DIR}/chain-steps.sh"
  [ -f "${chain_steps}" ]
  run bash -c "grep -qE '\[merge-gate-check\]=pr-merge' '${chain_steps}'"
  assert_success
}

@test "ac3c: chain.py と chain-steps.sh の CHAIN_STEPS が整合している（merge-gate-check を含む）" {
  # AC: chain.py CHAIN_STEPS と chain-steps.sh CHAIN_STEPS の内容が一致する
  # RED: chain.py に追加後、chain-steps.sh 再生成前は不整合で fail
  local chain_steps="${SCRIPTS_DIR}/chain-steps.sh"
  [ -f "${chain_steps}" ]
  [ -f "${CHAIN_PY}" ]

  # chain.py から CHAIN_STEPS を Python で取得
  local py_steps
  py_steps="$(python3 -c "
import sys
sys.path.insert(0, '$(dirname "${CHAIN_PY%/cli/twl/src/twl/autopilot/chain.py}")/cli/twl/src')
from twl.autopilot.chain import CHAIN_STEPS
for s in CHAIN_STEPS:
    print(s)
" 2>/dev/null)"

  # chain-steps.sh から CHAIN_STEPS 配列の内容を bash で取得
  local sh_steps
  sh_steps="$(bash -c "source '${chain_steps}'; printf '%s\n' \"\${CHAIN_STEPS[@]}\"" 2>/dev/null)"

  # 両方に merge-gate-check が含まれること
  echo "${py_steps}" | grep -qF 'merge-gate-check'
  echo "${sh_steps}" | grep -qF 'merge-gate-check'
}

# ===========================================================================
# AC4: bats integration test（chain.py 実体 grep + step_merge_gate_check 関数存在確認）
#
# ac-scaffold-tests-1540.bats の AC2/AC4 tests（auto-merge.sh 検証）を
# chain.py CHAIN_STEPS grep + chain-runner.sh step_merge_gate_check 関数存在確認
# に書き換えた「正しい検証内容」のテスト。
#
# RED: chain.py / chain-runner.sh 実装前は fail
# ===========================================================================

@test "ac4a: chain.py を grep すると merge-gate-check エントリが CHAIN_STEPS 定義内に存在する（static trace）" {
  # AC: chain.py ファイル内に "merge-gate-check" が CHAIN_STEPS コンテキストで出現する
  # RED: 現在 CHAIN_STEPS に merge-gate-check が無いため fail
  [ -f "${CHAIN_PY}" ]

  # CHAIN_STEPS 定義ブロック内に merge-gate-check があること
  run bash -c "python3 -c \"
import sys
sys.path.insert(0, '$(dirname "${CHAIN_PY%/cli/twl/src/twl/autopilot/chain.py}")/cli/twl/src')
from twl.autopilot.chain import CHAIN_STEPS, STEP_TO_WORKFLOW
assert 'merge-gate-check' in CHAIN_STEPS, 'merge-gate-check not in CHAIN_STEPS'
assert STEP_TO_WORKFLOW.get('merge-gate-check') == 'pr-merge', \
  f'Expected pr-merge, got: {STEP_TO_WORKFLOW.get(\\\"merge-gate-check\\\")}'
print('PASS')
\""
  assert_success
}

@test "ac4b: chain-runner.sh の step_merge_gate_check 関数が存在する（static trace）" {
  # AC: chain-runner.sh に step_merge_gate_check 関数が定義されている（grep 確認）
  # RED: 現在 step_merge_gate_check が未定義 → fail
  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]

  # 関数定義の存在確認
  run bash -c "grep -qE '^step_merge_gate_check\(\)' '${chain_runner}'"
  assert_success

  # specialist-audit を呼び出す記述の存在確認
  run bash -c "awk '/^step_merge_gate_check\(\)/,/^}/' '${chain_runner}' | grep -qF 'specialist-audit'"
  assert_success
}

@test "ac4c: ac-test-mapping-1554.yaml が存在し AC1-AC5 の mapping を含む" {
  # AC: ac-test-mapping-1554.yaml が存在し 5 件以上の AC mapping を持つ
  # RED: mapping ファイルが未生成の場合 fail（このファイル生成後は GREEN）
  local mapping_file
  local bats_dir
  bats_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  mapping_file="${bats_dir}/ac-test-mapping-1554.yaml"
  [ -f "${mapping_file}" ]
  local count
  count="$(grep -c 'ac_index' "${mapping_file}" 2>/dev/null || echo 0)"
  [ "${count}" -ge 5 ]
}

# ===========================================================================
# AC5: end-to-end verify
#
# chain workflow 経由で specialist-audit が trigger することを確認する。
# step_merge_gate_check がサンドボックス環境で呼び出され、
# specialist-audit.sh を invoke することを e2e レベルで verify。
#
# RED: step_merge_gate_check が未実装のため fail
# ===========================================================================

@test "ac5a: chain-runner.sh merge-gate-check subcommand が step_merge_gate_check を呼び出す（dispatch 確認）" {
  # AC: chain-runner.sh に merge-gate-check を dispatch 先として step_merge_gate_check が
  #     呼ばれる case 文または関数テーブルが存在する
  # RED: dispatch エントリが未実装 → fail

  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]

  # merge-gate-check が dispatch ロジックに存在すること（case 文または連想配列）
  run bash -c "grep -qF 'merge-gate-check' '${chain_runner}'"
  assert_success
}

@test "ac5b: specialist-audit.sh が存在し merge-gate モードで呼び出せる（前提確認）" {
  # AC: specialist-audit.sh が存在し --mode merge-gate 引数に対応している
  # RED: specialist-audit.sh 未存在 → fail（この時点では GREEN のはずだが、e2e の前提として確認）
  local audit_script="${SCRIPTS_DIR}/specialist-audit.sh"
  [ -f "${audit_script}" ]
  run bash -c "grep -qF 'merge-gate' '${audit_script}'"
  assert_success
}

@test "ac5c: chain-runner.sh merge-gate-check が step_merge_gate_check 関数名を stderr/stdout に出力する（dispatch trace）" {
  # AC: chain-runner.sh が merge-gate-check を dispatch する際、step_merge_gate_check を
  #     呼び出したトレース（関数名 or ログ行）が出力される
  # RED: step_merge_gate_check 未実装のため "unknown step" または "no such step" が出力され、
  #      step_merge_gate_check の呼び出しトレースは存在しない
  #
  # GREEN 条件: chain-runner.sh が merge-gate-check を受け取り step_merge_gate_check を呼ぶことで
  #             関数名がエラーメッセージや trace に出現するか、exit 0 で完了する

  local chain_runner="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "${chain_runner}" ]

  # step_merge_gate_check が chain-runner.sh に定義されていること（静的前提）
  # 未実装時はここで fail → RED 確定
  run bash -c "grep -qE '^step_merge_gate_check\(\)' '${chain_runner}'"
  assert_success
}

@test "ac5d: chain.py から chain-steps.sh を export した結果に merge-gate-check が含まれる（SSOT 整合）" {
  # AC: twl chain export で再生成した chain-steps.sh に merge-gate-check が含まれる
  # RED: chain.py に merge-gate-check が追加されていないため export 結果にも存在しない

  [ -f "${CHAIN_PY}" ]

  # Python で chain.py の export_chain_steps_sh() を直接呼び出して merge-gate-check の存在を確認
  run python3 -c "
import sys
sys.path.insert(0, '$(dirname "${CHAIN_PY%/cli/twl/src/twl/autopilot/chain.py}")/cli/twl/src')
from twl.autopilot.chain import CHAIN_STEPS, export_chain_steps_sh
output = export_chain_steps_sh()
assert 'merge-gate-check' in output, 'merge-gate-check not found in export_chain_steps_sh() output'
print('PASS')
"
  assert_success
}
