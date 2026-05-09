#!/usr/bin/env bats
# issue-1612-mcp-mid-session-disconnect.bats
#
# RED-phase tests for Issue #1612:
#   bug(twl-mcp): 長時間セッションでの MCP server mid-session disconnect —
#                 Wave 88 fix の不完全 (#1568 regression)
#
# 問題の本質:
#   - wait_for_mcp_ready.sh は SessionStart 時のみ実行される（起動時 race のみ対処）
#   - mid-session で MCP server process が死んだ場合、Claude Code の内部接続が切れる
#   - `twl mcp restart` で server process は再起動できるが、
#     Claude Code session の再起動が必要（または自動 reconnect の仕組みが必要）
#
# AC coverage:
#   AC1: mid-session disconnect 検出の仕組みが存在すること
#        - wait_for_mcp_ready.sh が SessionStart 以外でも呼び出し可能な設計になっていること
#          (standalone mode / --mode=mid-session 引数等)
#        - または: twl mcp doctor --probe 失敗時に自動再起動を試みる
#          --auto-restart オプションが doctor.py に存在すること
#   AC2: `twl mcp restart` の実行後、回復のための明確なガイダンスが提供されること
#        - restart 後に「Restart your Claude Code session to reconnect」メッセージが出力されること（既存）
#        - または: session 再起動不要な recovery mechanism が実装されること
#   AC3: MCP server プロセスの permanence 保証（ウォッチドッグまたは supervisord 相当）
#        - MCP server が死んだ場合に自動再起動する仕組みが存在すること
#          (mcp-watchdog.sh, twl mcp watchdog, supervisord conf 等のいずれか)
#        - または: cld-spawn が起動する MCP server の process group 管理が改善されること
#   AC4: bats テスト追加（本 Issue の mid-session シナリオをカバー）
#        - plugins/twl/tests/bats/issue-1612-mcp-mid-session-disconnect.bats が存在すること
#        - mid-session disconnect のシナリオをカバーするテストが含まれること
#
# RED となるテスト（現状では fail する):
#   AC1: wait_for_mcp_ready.sh に SessionStart 以外の呼び出しを想定した設計がない → fail
#        doctor.py に --auto-restart がない → fail
#   AC2: 既存の restart 後メッセージは PASS 相当。recovery mechanism は未実装 → fail (新規)
#   AC3: watchdog / supervisor 相当ファイルが存在しない → fail
#   AC4: 本ファイル自体の静的確認（実行時は PASS / 記録テスト）
#
# テストスタイル: issue-1568-cld-spawn-mcp-warm.bats と同じ構造
#   - 静的ファイル存在確認・grep ベースが中心
#   - 動的プロセス起動は skip-by-default

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

  WAIT_FOR_MCP_SCRIPT="${REPO_ROOT}/scripts/wait_for_mcp_ready.sh"
  DOCTOR_PY="${MONO_ROOT}/cli/twl/src/twl/mcp_server/doctor.py"
  LIFECYCLE_PY="${MONO_ROOT}/cli/twl/src/twl/mcp_server/lifecycle.py"
  MCP_SMOKE_YML="${MONO_ROOT}/.github/workflows/mcp-restart-smoke.yml"
  CLD_SPAWN="${MONO_ROOT}/plugins/session/scripts/cld-spawn"
  BATS_TARGET_FILE="${this_dir}/issue-1612-mcp-mid-session-disconnect.bats"
  export WAIT_FOR_MCP_SCRIPT DOCTOR_PY LIFECYCLE_PY MCP_SMOKE_YML CLD_SPAWN BATS_TARGET_FILE
}

# ===========================================================================
# AC1: mid-session disconnect 検出の仕組みが存在すること
# wait_for_mcp_ready.sh が SessionStart 以外でも呼び出し可能な設計になっていること
# または: twl mcp doctor --probe 失敗時に --auto-restart オプションが存在すること
# ===========================================================================

@test "ac1: wait_for_mcp_ready.sh exists (prerequisite)" {
  # AC: wait_for_mcp_ready.sh がモノリポに存在すること（前提確認）
  [ -f "${WAIT_FOR_MCP_SCRIPT}" ]
}

@test "ac1: wait_for_mcp_ready.sh supports mid-session mode or standalone invocation" {
  # AC: wait_for_mcp_ready.sh が SessionStart 以外でも呼び出し可能な設計になっていること
  #     - コメントに「SessionStart hook から呼び出される」のみの記述である場合は fail
  #     - standalone / --mode / 引数 / mid-session 対応コメントがある場合は pass
  # RED: 現状は SessionStart 専用設計のため fail する
  run grep -qiE 'standalone|mid.session|on.demand|--mode|mode=|reconnect|MODE|STANDALONE' "${WAIT_FOR_MCP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac1: wait_for_mcp_ready.sh is not restricted to SessionStart-only by its shebang comment" {
  # AC: スクリプト先頭コメントが SessionStart 限定を前提としない設計になっていること
  #     既存: "# SessionStart hook から呼び出される MCP 接続確認スクリプト"
  #     期待: mid-session や standalone 呼び出しを許容する設計記述に更新されていること
  # RED: コメントが SessionStart のみを前提としていたら fail
  local first_comment
  first_comment="$(grep '^#' "${WAIT_FOR_MCP_SCRIPT}" | head -3)"
  # 「SessionStart」のみ言及し「standalone」「mid-session」「on-demand」等の記述がない場合 fail
  run bash -c "
    echo '${first_comment}' | grep -qiE 'standalone|mid.session|on.demand|reconnect'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: doctor.py has --auto-restart option for mid-session recovery" {
  # AC: twl mcp doctor --probe 失敗時に自動再起動を試みる --auto-restart オプションが
  #     doctor.py の argparse に定義されていること
  # RED: --auto-restart が存在しない場合 fail（現状は未実装）
  [ -f "${DOCTOR_PY}" ]
  run grep -qE '"--auto-restart"|"auto_restart"|auto.restart' "${DOCTOR_PY}"
  [ "${status}" -eq 0 ]
}

@test "ac1: doctor.py --auto-restart triggers lifecycle restart on probe failure" {
  # AC: --auto-restart 実装が probe 失敗時に lifecycle.restart_mcp_server() を呼ぶこと
  # RED: 実装がない場合 fail
  [ -f "${DOCTOR_PY}" ]
  run grep -qiE 'auto.restart.*restart_mcp|restart_mcp.*auto.restart|probe.*fail.*restart|restart.*probe.*fail' "${DOCTOR_PY}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: `twl mcp restart` の実行後、回復のための明確なガイダンスが提供されること
# 既存: "NOTE: Restart your Claude Code session to reconnect." は実装済み
# 追加: session 再起動不要な recovery mechanism が存在すること、または
#       restart 後のガイダンスが 1612 の教訓を反映したメッセージに更新されること
# ===========================================================================

@test "ac2: lifecycle.py emits restart guidance after mcp restart (existing, should pass)" {
  # AC: lifecycle.py の restart_mcp_server() が restart 後に
  #     「Restart your Claude Code session to reconnect」を出力すること
  # NOTE: これは #1605 で実装済みのため PASS する想定（regression check）
  [ -f "${LIFECYCLE_PY}" ]
  run grep -qF 'Restart your Claude Code session to reconnect' "${LIFECYCLE_PY}"
  [ "${status}" -eq 0 ]
}

@test "ac2: lifecycle.py restart guidance references mid-session disconnect scenario" {
  # AC: restart 後の guidance が mid-session disconnect のシナリオを言及するか、
  #     または issue 番号 (#1612) を参照するメッセージに更新されていること
  # RED: 現状の generic な "NOTE: Restart your Claude Code session..." のみの場合 fail
  [ -f "${LIFECYCLE_PY}" ]
  run grep -qiE '1612|mid.session|disconnect|long.session|session.drop' "${LIFECYCLE_PY}"
  [ "${status}" -eq 0 ]
}

@test "ac2: mcp-restart-smoke.yml includes mid-session disconnect scenario test" {
  # AC: mcp-restart-smoke.yml が mid-session disconnect シナリオをカバーする step を持つこと
  # RED: mid-session シナリオの step が存在しない場合 fail
  [ -f "${MCP_SMOKE_YML}" ]
  run grep -qiE 'mid.session|disconnect|long.session|session.drop|1612' "${MCP_SMOKE_YML}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: MCP server プロセスの permanence 保証（ウォッチドッグまたは supervisord 相当）
# MCP server が死んだ場合に自動再起動する仕組みが存在すること
# ===========================================================================

@test "ac3: mcp watchdog script or equivalent exists" {
  # AC: MCP server の自動再起動を担う watchdog スクリプトが存在すること
  #     候補: plugins/twl/scripts/mcp-watchdog.sh
  #           plugins/session/scripts/mcp-watchdog.sh
  #           plugins/twl/scripts/wait_for_mcp_ready.sh に watchdog mode
  # RED: いずれも存在しない場合 fail
  local found=0
  # watchdog 専用スクリプトの存在確認
  if find "${MONO_ROOT}" -name "*mcp*watchdog*" -o -name "*watchdog*mcp*" 2>/dev/null | grep -q '.'; then
    found=1
  fi
  # または wait_for_mcp_ready.sh が watchdog mode を持つ場合
  if [ -f "${WAIT_FOR_MCP_SCRIPT}" ] && grep -qiE 'watchdog|--watch|WATCH|daemon|DAEMON' "${WAIT_FOR_MCP_SCRIPT}"; then
    found=1
  fi
  # または twl mcp watchdog コマンドが cli.py に存在する場合
  local cli_py="${MONO_ROOT}/cli/twl/src/twl/cli.py"
  if [ -f "${cli_py}" ] && grep -qiE 'watchdog|mcp.*watch|watch.*mcp' "${cli_py}"; then
    found=1
  fi
  [ "${found}" -eq 1 ]
}

@test "ac3: cld-spawn MCP server process group is managed for mid-session stability" {
  # AC: cld-spawn が起動する MCP server の process group 管理が
  #     mid-session disconnect 耐性のために改善されていること
  #     - setsid / start-new-session / process group 管理の明示的なコードがあること
  #     - または: mid-session 対策コメント + 1612 参照があること
  # RED: 現状は eager-warm のみで process group 管理改善がない場合 fail
  [ -f "${CLD_SPAWN}" ]
  run grep -qiE 'setsid|process.group|proc.group|nohup|daemon|DAEMON|1612|mid.session' "${CLD_SPAWN}"
  [ "${status}" -eq 0 ]
}

@test "ac3: lifecycle.py restart uses process group isolation to prevent mid-session death" {
  # AC: lifecycle.py の restart_mcp_server() が start_new_session=True かつ
  #     mid-session disconnect 耐性のための追加の process group 管理を実装していること
  # 既存: start_new_session=True は実装済み → 追加の改善を確認する
  # RED: 1612 の教訓を反映した process group 管理の改善がない場合 fail
  [ -f "${LIFECYCLE_PY}" ]
  # start_new_session=True は存在するが、追加の keepalive / watchdog / health-check が必要
  run grep -qiE 'keepalive|keep.alive|health.check|healthcheck|watchdog|1612|mid.session|permanent|respawn' "${LIFECYCLE_PY}"
  [ "${status}" -eq 0 ]
}

@test "ac3: scenario-A: mcp watchdog daemonizes and auto-restarts on process death (skip-by-default)" {
  # AC: watchdog が MCP server プロセス死を検知して自動再起動すること（動的テスト）
  # Scenario A: 動的実行テスト（skip-by-default）
  # RED: 実装前は watchdog が存在しないため fail する想定だが、
  #      このテストはプロセス操作を伴うため skip する
  skip "Scenario A (skip-by-default): requires live MCP server process management"
}

# ===========================================================================
# AC4: bats テスト追加（本 Issue の mid-session シナリオをカバー）
# plugins/twl/tests/bats/issue-1612-mcp-mid-session-disconnect.bats が存在すること
# mid-session disconnect のシナリオをカバーするテストが含まれること
# ===========================================================================

@test "ac4: issue-1612-mcp-mid-session-disconnect.bats exists in plugins/twl/tests/bats/" {
  # AC: plugins/twl/tests/bats/issue-1612-mcp-mid-session-disconnect.bats が存在すること
  # NOTE: 本テスト自体が当該ファイルであるため、実行時は常に PASS する（記録テスト）
  [ -f "${BATS_TARGET_FILE}" ]
}

@test "ac4: bats file contains AC1 mid-session detection tests" {
  # AC: 本 bats ファイルに AC1 の mid-session 検出テストが含まれること
  # RED: AC1 テストが bats ファイルに実装されていない場合 fail
  run grep -qF '"ac1:' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

@test "ac4: bats file contains AC2 restart guidance tests" {
  # AC: 本 bats ファイルに AC2 の restart guidance テストが含まれること
  # RED: AC2 テストが bats ファイルに実装されていない場合 fail
  run grep -qF '"ac2:' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

@test "ac4: bats file contains AC3 watchdog / permanence tests" {
  # AC: 本 bats ファイルに AC3 の watchdog / permanence テストが含まれること
  # RED: AC3 テストが bats ファイルに実装されていない場合 fail
  run grep -qF '"ac3:' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

@test "ac4: bats file includes skip-by-default dynamic scenario" {
  # AC: 動的テストシナリオが skip-by-default としてマークされていること
  # RED: skip-by-default マーカーが存在しない場合 fail
  run grep -qE 'skip.*Scenario A|skip-by-default' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}
