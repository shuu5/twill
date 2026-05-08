#!/usr/bin/env bats
# issue-1568-cld-spawn-mcp-warm.bats
#
# RED-phase tests for Issue #1568:
#   bug(twl-mcp): Pilot/Worker セッション起動直後に MCP server が未起動で
#                 SessionStart hook error が発生する問題
#
# AC coverage:
#   AC1: cld-spawn に MCP server eager-warm step を追加
#        - TWL_SKIP_MCP_WARM=1 env で bypass 可能
#        - inject-file --wait 行の直前に `twl mcp doctor --probe 2>/dev/null || true` を呼び出す
#   AC2: SessionStart hook で MCP server 接続待ちを実装
#        - plugins/twl/scripts/wait_for_mcp_ready.sh (新規) が存在すること
#        - .claude/settings.json の SessionStart 配列に wait_for_mcp_ready.sh の command hook が追加されること
#   AC3: bats テスト追加（本ファイル自体の存在確認）
#        - Issue #1568 本件の Scenario B (CI必須) + Scenario A (skip-by-default)
#   AC4: CI smoke 拡張 — .github/workflows/mcp-restart-smoke.yml に「new session warmup」step 追加
#        - 既存 Doctor validation step (if: false) とは独立して有効化
#   AC5 (任意 / skip-by-default): twl mcp doctor --wait-ready フラグ追加
#        - cli/twl/src/twl/mcp_server/doctor.py に --wait-ready オプションが存在すること
#
# RED となるテスト:
#   AC1: cld-spawn に TWL_SKIP_MCP_WARM / mcp doctor --probe が存在しない → fail
#   AC2: wait_for_mcp_ready.sh が存在しない → fail
#        settings.json の SessionStart に wait_for_mcp_ready.sh hook がない → fail
#   AC3: 本ファイル自体の静的確認（実行時は PASS するが RED フェーズの記録）
#   AC4: mcp-restart-smoke.yml に warmup step がない → fail
#   AC5: doctor.py に --wait-ready がない → fail (skip-by-default)

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  # tests/bats/ -> tests/ -> plugins/twl/ (REPO_ROOT = plugins/twl/)
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  # リポジトリルート (twill モノリポルート) = plugins/twl/ の 2 つ上
  MONO_ROOT="$(cd "${REPO_ROOT}/../.." && pwd)"
  export MONO_ROOT

  CLD_SPAWN="${MONO_ROOT}/plugins/session/scripts/cld-spawn"
  WAIT_FOR_MCP_SCRIPT="${REPO_ROOT}/scripts/wait_for_mcp_ready.sh"
  SETTINGS_JSON="${MONO_ROOT}/.claude/settings.json"
  MCP_SMOKE_YML="${MONO_ROOT}/.github/workflows/mcp-restart-smoke.yml"
  DOCTOR_PY="${MONO_ROOT}/cli/twl/src/twl/mcp_server/doctor.py"
  BATS_TARGET_FILE="${this_dir}/issue-1568-cld-spawn-mcp-warm.bats"
  export CLD_SPAWN WAIT_FOR_MCP_SCRIPT SETTINGS_JSON MCP_SMOKE_YML DOCTOR_PY BATS_TARGET_FILE
}

# ===========================================================================
# AC1: cld-spawn に MCP server eager-warm step が存在すること
# inject-file --wait 行の直前に twl mcp doctor --probe 呼び出しが追加されること
# TWL_SKIP_MCP_WARM=1 で bypass できること
# ===========================================================================

@test "ac1: cld-spawn exists at plugins/session/scripts/cld-spawn" {
  # AC: cld-spawn スクリプトがモノリポに存在すること（前提確認）
  [ -f "${CLD_SPAWN}" ]
}

@test "ac1: cld-spawn contains TWL_SKIP_MCP_WARM bypass guard" {
  # AC: cld-spawn に TWL_SKIP_MCP_WARM=1 による bypass ガードが存在すること
  # RED: TWL_SKIP_MCP_WARM 環境変数の参照が存在しない場合 fail
  run grep -qF 'TWL_SKIP_MCP_WARM' "${CLD_SPAWN}"
  [ "${status}" -eq 0 ]
}

@test "ac1: cld-spawn calls 'twl mcp doctor --probe' for eager warm" {
  # AC: cld-spawn が MCP eager-warm のために 'twl mcp doctor --probe' を呼び出すこと
  # RED: mcp doctor --probe 呼び出しが存在しない場合 fail
  run grep -qF 'mcp doctor --probe' "${CLD_SPAWN}"
  [ "${status}" -eq 0 ]
}

@test "ac1: cld-spawn mcp warm step is placed before inject-file --wait line" {
  # AC: MCP warm step が inject-file --wait 行の直前（より前の行番号）に位置すること
  # RED: warm step が存在しないか inject-file --wait より後に配置されている場合 fail
  local warm_line inject_line

  warm_line="$(grep -n 'mcp doctor --probe' "${CLD_SPAWN}" | head -1 | cut -d: -f1)"
  inject_line="$(grep -n 'inject-file.*--wait' "${CLD_SPAWN}" | head -1 | cut -d: -f1)"

  # どちらも存在しなければ fail
  [ -n "${warm_line}" ]
  [ -n "${inject_line}" ]

  # warm step の行番号が inject-file --wait より小さいこと
  [ "${warm_line}" -lt "${inject_line}" ]
}

@test "ac1: cld-spawn mcp doctor --probe is called with '|| true' to suppress errors" {
  # AC: mcp doctor --probe が 2>/dev/null || true パターンで呼び出されること
  #     (MCP warm 失敗時でもセッション起動を継続するため)
  # RED: 該当パターンが存在しない場合 fail
  run grep -qE 'mcp doctor --probe.*\|\|.*true' "${CLD_SPAWN}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: wait_for_mcp_ready.sh の新規作成と settings.json への SessionStart hook 追加
# ===========================================================================

@test "ac2: wait_for_mcp_ready.sh exists at plugins/twl/scripts/" {
  # AC: plugins/twl/scripts/wait_for_mcp_ready.sh が存在すること
  # RED: ファイルが存在しない場合 fail（新規作成前は常に fail）
  local wait_script="${REPO_ROOT}/scripts/wait_for_mcp_ready.sh"
  [ -f "${wait_script}" ]
}

@test "ac2: wait_for_mcp_ready.sh is executable" {
  # AC: wait_for_mcp_ready.sh に実行権限が付与されていること
  # RED: ファイルが存在しないか実行権限がない場合 fail
  local wait_script="${REPO_ROOT}/scripts/wait_for_mcp_ready.sh"
  [ -f "${wait_script}" ]
  [ -x "${wait_script}" ]
}

@test "ac2: settings.json SessionStart array contains wait_for_mcp_ready.sh hook" {
  # AC: .claude/settings.json の SessionStart 配列に wait_for_mcp_ready.sh の
  #     command hook が存在すること
  # RED: wait_for_mcp_ready.sh への参照が SessionStart hook に存在しない場合 fail
  [ -f "${SETTINGS_JSON}" ]
  run grep -qF 'wait_for_mcp_ready.sh' "${SETTINGS_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac2: settings.json SessionStart wait_for_mcp_ready hook has type command" {
  # AC: settings.json の SessionStart に wait_for_mcp_ready.sh を呼ぶ
  #     type: command の hook エントリが存在すること
  # RED: type が command 以外、または hook エントリが存在しない場合 fail
  [ -f "${SETTINGS_JSON}" ]

  # jq で SessionStart 配列内に wait_for_mcp_ready.sh を含む command hook が存在するか確認
  run bash -c "
    jq -e '
      .hooks.SessionStart[]?
      | .hooks[]?
      | select(.type == \"command\" and (.command | test(\"wait_for_mcp_ready\")))
    ' '${SETTINGS_JSON}' > /dev/null 2>&1
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: bats テスト追加（本ファイル自体の存在確認）
# Scenario B (CI 必須): cld-spawn の eager-warm 静的検証
# Scenario A (skip-by-default): TWL_SKIP_MCP_WARM bypass 動的テスト
# ===========================================================================

@test "ac3: issue-1568-cld-spawn-mcp-warm.bats exists in plugins/twl/tests/bats/" {
  # AC: plugins/twl/tests/bats/issue-1568-cld-spawn-mcp-warm.bats が存在すること
  # NOTE: 本テスト自体が当該ファイルであるため、実行時は常に PASS する
  #       CI での静的存在確認の確実性を担保するための記録テスト
  [ -f "${BATS_TARGET_FILE}" ]
}

@test "ac3: scenario-B: bats file contains AC1 static checks (CI required)" {
  # AC: 本 bats ファイルに AC1 の静的テスト（Scenario B / CI 必須）が含まれること
  # RED: AC1 テストが bats ファイルに実装されていない場合 fail
  run grep -qF '"ac1:' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

@test "ac3: scenario-B: bats file contains AC2 static checks (CI required)" {
  # AC: 本 bats ファイルに AC2 の静的テスト（Scenario B / CI 必須）が含まれること
  # RED: AC2 テストが bats ファイルに実装されていない場合 fail
  run grep -qF '"ac2:' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

@test "ac3: scenario-A: TWL_SKIP_MCP_WARM bypass test is marked skip-by-default" {
  # AC: TWL_SKIP_MCP_WARM の動的テスト（Scenario A）が skip-by-default として
  #     マークされていること
  # RED: skip-by-default マーカーが存在しない場合 fail
  run grep -qE 'skip.*TWL_SKIP_MCP_WARM|TWL_SKIP_MCP_WARM.*skip' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

@test "ac3: scenario-A: TWL_SKIP_MCP_WARM=1 causes cld-spawn to skip mcp doctor probe (skip-by-default)" {
  # AC: TWL_SKIP_MCP_WARM=1 設定時に cld-spawn が mcp doctor --probe を呼ばないこと
  # Scenario A: 動的実行テスト（skip-by-default）
  # RED: 実装前は TWL_SKIP_MCP_WARM を cld-spawn が参照しないため fail する想定だが、
  #      このテストは統合実行が困難なため skip する
  skip "Scenario A (skip-by-default): requires live cld-spawn execution environment"
}

# ===========================================================================
# AC4: .github/workflows/mcp-restart-smoke.yml に「new session warmup」step 追加
# 既存 Doctor validation step (if: false) とは独立して有効化されること
# ===========================================================================

@test "ac4: mcp-restart-smoke.yml exists" {
  # AC: .github/workflows/mcp-restart-smoke.yml が存在すること（前提確認）
  [ -f "${MCP_SMOKE_YML}" ]
}

@test "ac4: mcp-restart-smoke.yml contains 'new session warmup' step" {
  # AC: mcp-restart-smoke.yml に「new session warmup」step が存在すること
  # RED: warmup step が存在しない場合 fail
  run grep -qiE 'new.session.warmup|session.warmup|warmup.*step' "${MCP_SMOKE_YML}"
  [ "${status}" -eq 0 ]
}

@test "ac4: mcp-restart-smoke.yml warmup step does not have 'if: false' guard" {
  # AC: 追加された warmup step が 'if: false' によって無効化されていないこと
  #     (既存 Doctor validation step とは独立して有効化されること)
  # RED: warmup step が 'if: false' で無効化されている場合、または step が存在しない場合 fail
  #
  # 実装方針: warmup step の name 行の前後数行に "if: false" がないことを確認する
  # warmup ステップ名の行番号を取得し、その前後10行に "if: false" がなければ PASS
  local warmup_line
  warmup_line="$(grep -niE 'new.session.warmup|session.warmup' "${MCP_SMOKE_YML}" | head -1 | cut -d: -f1)"

  # warmup step 自体が存在しなければ fail
  [ -n "${warmup_line}" ]

  # warmup step 周辺 (前後 5 行) に "if: false" がないことを確認
  local start_line end_line total_lines
  total_lines="$(wc -l < "${MCP_SMOKE_YML}")"
  start_line=$(( warmup_line > 5 ? warmup_line - 5 : 1 ))
  end_line=$(( warmup_line + 15 < total_lines ? warmup_line + 15 : total_lines ))

  run bash -c "sed -n '${start_line},${end_line}p' '${MCP_SMOKE_YML}' | grep -qF 'if: \"\${{ false }}\"'"
  [ "${status}" -ne 0 ]
}

@test "ac4: mcp-restart-smoke.yml warmup step calls twl mcp or cld-spawn warm logic" {
  # AC: warmup step が MCP warm 処理（twl mcp doctor --probe、wait_for_mcp_ready.sh 等）を実行すること
  # RED: warmup step 名の直後のブロック内に warm 関連コマンドが存在しない場合 fail
  #
  # 実装方針: warmup step 名の行番号を取得し、その後続 20 行内に warm 関連コマンドがあるか確認
  # warmup step 自体が存在しなければ fail する
  local warmup_line total_lines end_line
  warmup_line="$(grep -niE 'new.session.warmup|session.warmup' "${MCP_SMOKE_YML}" | head -1 | cut -d: -f1)"

  # warmup step 自体が存在しなければ fail
  [ -n "${warmup_line}" ]

  total_lines="$(wc -l < "${MCP_SMOKE_YML}")"
  end_line=$(( warmup_line + 20 < total_lines ? warmup_line + 20 : total_lines ))

  run bash -c "sed -n '${warmup_line},${end_line}p' '${MCP_SMOKE_YML}' | grep -qiE 'mcp doctor.*probe|wait_for_mcp|TWL_SKIP_MCP_WARM|mcp.*warm'"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5 (任意 / skip-by-default): twl mcp doctor --wait-ready フラグ追加
# cli/twl/src/twl/mcp_server/doctor.py に --wait-ready オプションが存在すること
# ===========================================================================

@test "ac5: doctor.py exists at cli/twl/src/twl/mcp_server/doctor.py (skip-by-default)" {
  # AC: doctor.py がモノリポに存在すること（前提確認）
  # 任意 AC のため skip-by-default
  skip "AC5 is optional (skip-by-default)"
  [ -f "${DOCTOR_PY}" ]
}

@test "ac5: doctor.py contains --wait-ready flag definition (skip-by-default)" {
  # AC: doctor.py に --wait-ready オプションが argparse に追加されていること
  # RED: --wait-ready フラグが存在しない場合 fail
  # 任意 AC のため skip-by-default
  skip "AC5 is optional (skip-by-default)"
  [ -f "${DOCTOR_PY}" ]
  run grep -qE '"--wait-ready"|"wait_ready"' "${DOCTOR_PY}"
  [ "${status}" -eq 0 ]
}

@test "ac5: doctor.py --wait-ready implements polling loop (skip-by-default)" {
  # AC: --wait-ready 実装がポーリングループを含むこと
  # RED: polling / retry ロジックが doctor.py に存在しない場合 fail
  # 任意 AC のため skip-by-default
  skip "AC5 is optional (skip-by-default)"
  [ -f "${DOCTOR_PY}" ]
  run grep -qiE 'wait.ready|wait_ready|poll.*ready|retry.*ready' "${DOCTOR_PY}"
  [ "${status}" -eq 0 ]
}
