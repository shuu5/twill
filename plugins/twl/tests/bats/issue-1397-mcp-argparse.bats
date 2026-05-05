#!/usr/bin/env bats
# issue-1397-mcp-argparse.bats
#
# RED-phase tests for Issue #1397:
#   tech-debt(cli): twl mcp restart を argparse subparser へ移行
#
# AC coverage:
#   AC1: twl --help に "mcp" サブコマンドが表示されること
#   AC2: twl mcp --help が exit 0 かつ "restart" を含むこと
#   AC3: twl mcp restart の既存挙動が argparse 移行後も破綻しないこと
#         (a) cli.py に sys.argv[1] == 'mcp' の if-chain が存在しないこと（移行後に消える）
#         (b) cli.py に add_parser('mcp') が存在すること
#         (c) twl mcp restart が exit 0 で完了すること
#   AC4: 既存 if-chain サブコマンドの回帰確認（twl hello が exit 0）
#   AC5: issue-1388-mcp-restart.bats に sys.argv[1] == 'mcp' の grep が存在しないこと
#   AC6: PR description にスコープ判断が明記されること（プロセス AC）
#
# RED となるテスト:
#   AC1: twl --help に "mcp" が含まれない（argparse subparser 未登録）→ FAIL
#   AC2: twl mcp --help が exit 1（if-chain が '--help' を unknown subcommand として扱う）→ FAIL
#   AC3(a): cli.py に sys.argv[1] == 'mcp' が存在する（移行前の if-chain が残存）→ FAIL
#   AC3(b): cli.py に add_parser('mcp') が存在しない→ FAIL
#   AC3(c): twl mcp restart が exit 0（回帰チェック、現在 PASS だが include）
#   AC4: twl hello が exit 0（回帰チェック、現在 PASS だが include）
#   AC5: issue-1388-mcp-restart.bats に sys.argv[1] == 'mcp' の grep が存在する→ FAIL
#   AC6: false（プロセス AC は手動確認が必要）

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT
  MONO_ROOT="$(cd "${REPO_ROOT}/../.." && pwd)"
  export MONO_ROOT
  CLI_PY="${MONO_ROOT}/cli/twl/src/twl/cli.py"
  TWL_BIN="${MONO_ROOT}/cli/twl/twl"
  export CLI_PY TWL_BIN
}

# ===========================================================================
# AC1: twl --help に "mcp" サブコマンドが表示されること
#
# RED: argparse subparser に mcp が登録されていないため --help 出力に含まれない
# GREEN: add_subparsers() + add_parser('mcp') 実装後に "mcp" が出力に現れる
# ===========================================================================

@test "ac1: 'twl --help' output contains 'mcp' subcommand" {
  # AC: twl --help 実行時に mcp サブコマンドが表示される（subparser メタデータ・ヘルプテキスト含む）
  # RED: 現在 argparse mainparser に add_subparsers() が未設定のため mcp が表示されない
  if [ ! -f "${TWL_BIN}" ]; then
    skip "twl binary not found at ${TWL_BIN}"
  fi
  run "${TWL_BIN}" --help
  echo "output: ${output}"
  [[ "${output}" == *"mcp"* ]]
}

# ===========================================================================
# AC2: twl mcp --help が exit 0 かつ "restart" を含むこと
#
# RED: if-chain が '--help' を unknown subcommand として扱い exit 1 で終了する
# GREEN: argparse subparser 実装後に exit 0 かつ "restart" が出力に含まれる
# ===========================================================================

@test "ac2: 'twl mcp --help' exits with code 0" {
  # AC: twl mcp --help が exit 0 で完了すること
  # RED: 現在 if-chain が '--help' を unknown subcommand として扱い exit 1
  if [ ! -f "${TWL_BIN}" ]; then
    skip "twl binary not found at ${TWL_BIN}"
  fi
  run "${TWL_BIN}" mcp --help
  echo "status: ${status}"
  echo "output: ${output}"
  [ "${status}" -eq 0 ]
}

@test "ac2: 'twl mcp --help' output contains 'restart'" {
  # AC: twl mcp --help の出力に restart サブサブコマンドが表示されること
  # RED: 現在 if-chain が '--help' を処理できないため restart が表示されない
  if [ ! -f "${TWL_BIN}" ]; then
    skip "twl binary not found at ${TWL_BIN}"
  fi
  run "${TWL_BIN}" mcp --help
  echo "output: ${output}"
  [[ "${output}" == *"restart"* ]]
}

# ===========================================================================
# AC3(a): cli.py に sys.argv[1] == 'mcp' の if-chain が存在しないこと
#
# RED: 現在 cli.py L82 付近に if-chain が存在するため grep が PASS し
#      このテストが FAIL する（not grep → FAIL）
# GREEN: argparse 移行後に if-chain が削除されると grep が FAIL し
#        このテストが PASS する（not grep → PASS）
# ===========================================================================

@test "ac3a: cli.py does NOT contain 'sys.argv[1] == .mcp.' if-chain (argparse migration)" {
  # AC: argparse 移行後 cli.py に sys.argv[1] == 'mcp' の if-chain が存在しないこと
  # RED: 現在 cli.py L82 に if-chain が残存しているため grep -q が exit 0 → [ not ] で FAIL
  run grep -qF "sys.argv[1] == 'mcp'" "${CLI_PY}"
  echo "grep exit status (expected 1 after migration): ${status}"
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC3(b): cli.py に add_parser('mcp') が存在すること
#
# RED: 現在 cli.py に add_subparsers() も add_parser('mcp') も存在しないため FAIL
# GREEN: argparse 移行後に add_parser('mcp') が追加されると PASS
# ===========================================================================

@test "ac3b: cli.py contains add_parser('mcp') for argparse subparser" {
  # AC: cli.py に argparse の add_parser('mcp') 呼び出しが存在すること
  # RED: 現在 cli.py に add_subparsers() が未設定のため add_parser('mcp') も存在しない
  run grep -qF "add_parser('mcp')" "${CLI_PY}"
  echo "grep exit status (expected 0 after migration): ${status}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3(c): twl mcp restart が exit 0 で完了すること（回帰チェック）
#
# 現在の if-chain 実装では PASS だが、argparse 移行後も PASS であることを保証する
# ===========================================================================

@test "ac3c: 'twl mcp restart' exits with code 0 (regression)" {
  # AC: twl mcp restart の既存挙動（restart_mcp_server() 呼び出し、exit 0 回帰）が破綻しないこと
  # RED(regression): argparse 移行後に exit 0 が維持されることを確認（現在は if-chain で PASS）
  if [ ! -f "${TWL_BIN}" ]; then
    skip "twl binary not found at ${TWL_BIN}"
  fi
  run "${TWL_BIN}" mcp restart
  echo "status: ${status}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: 既存 if-chain サブコマンドの回帰確認
#
# argparse subparser 導入後も既存サブコマンドが引き続き動作することを確認
# twl hello を引数なしで呼び出して exit code が変化しないこと
# ===========================================================================

@test "ac4: 'twl hello' exits with code 0 (regression)" {
  # AC: 既存の if-chain サブコマンド hello が argparse 移行後も引き続き動作すること
  # RED(regression): 現在 PASS だが、移行後の回帰確認として include
  if [ ! -f "${TWL_BIN}" ]; then
    skip "twl binary not found at ${TWL_BIN}"
  fi
  run "${TWL_BIN}" hello
  echo "status: ${status}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: issue-1388-mcp-restart.bats に sys.argv[1] == 'mcp' の grep が存在しないこと
#
# RED: 現在 issue-1388-mcp-restart.bats L44 に grep -qF "sys.argv[1] == 'mcp'" が存在するため
#      grep が PASS し、このテストが FAIL する（not grep → FAIL）
# GREEN: L44 の静的チェックが削除または書き換えられると grep が FAIL し
#        このテストが PASS する（not grep → PASS）
# ===========================================================================

@test "ac5: issue-1388-mcp-restart.bats does NOT contain 'sys.argv[1] == .mcp.' grep check" {
  # AC: issue-1388-mcp-restart.bats を argparse 構造に合わせて更新した上で、
  #     L44 の grep -qF "sys.argv[1] == 'mcp'" 静的チェックが削除または書き換えられていること
  # RED: 現在 issue-1388-mcp-restart.bats L44 に該当 grep が残存しているため FAIL
  local bats_1388="${REPO_ROOT}/tests/bats/issue-1388-mcp-restart.bats"
  run grep -qF "sys.argv[1] == 'mcp'" "${bats_1388}"
  echo "grep exit status (expected 1 after update): ${status}"
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC6: PR description にスコープ判断が明記されること（プロセス AC）
#
# プロセス AC のため自動テスト不可。常に fail するスタブとして実装。
# ===========================================================================

@test "ac6: PR description contains scope decision (process AC - manual verification required)" {
  # AC: スコープ判断（PR description にスコープが明記されること）
  # RED: プロセス AC は手動確認が必要のため常に FAIL
  false  # RED: PR description は手動確認が必要
}
