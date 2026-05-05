#!/usr/bin/env bats
# issue-1388-mcp-restart.bats
#
# RED-phase tests for Issue #1388:
#   tech-debt(hooks): MCP observer が mcp-serve で unknown tool エラー → 再起動フロー整備
#
# AC coverage:
#   AC1: cli.py に `mcp restart` の if-chain が存在する（静的確認）
#   AC2: `twl mcp restart` が exit 0 で完了すること（機能テスト）
#   AC3: cli/twl/src/twl/mcp_server/README.md に再起動手順の記述が存在する（静的確認）
#
# スキップ対象:
#   AC4: 新規 Claude Code セッションで Unknown tool が出ないことを手動確認（自動テスト不可）
#   AC5: #1037 epic の Sub-Issue 追加 + checklist 更新（プロジェクト管理、自動テスト不可）
#
# RED となるテスト: AC1 (mcp サブコマンド if-chain 不在), AC2 (コマンド未実装),
#                   AC3 (再起動手順記述不在)

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

  CLI_PY="${MONO_ROOT}/cli/twl/src/twl/cli.py"
  MCP_README="${MONO_ROOT}/cli/twl/src/twl/mcp_server/README.md"
  export CLI_PY MCP_README
}

# ===========================================================================
# AC1: cli.py に `mcp` サブコマンドが argparse subparser として登録されている（静的確認）
# (Issue #1397 で if-chain から argparse subparser へ移行済み)
# ===========================================================================

@test "ac1: cli.py contains 'mcp' subcommand argparse registration" {
  # AC: cli.py に mcp サブコマンドが argparse subparser として登録されていること
  # (Issue #1397: if-chain から argparse 移行後の確認)
  run grep -qF "add_parser('mcp'" "${CLI_PY}"
  [ "${status}" -eq 0 ]
}

@test "ac1: cli.py contains 'restart' subcommand dispatch for mcp" {
  # AC: cli.py の mcp ブロック内に 'restart' サブコマンドの dispatch が存在する
  # RED: mcp サブコマンド自体が未実装のため fail
  run grep -qE "restart" "${CLI_PY}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: `twl mcp restart` が exit 0 で完了すること（機能テスト）
# ===========================================================================

@test "ac2: 'twl mcp restart' exits with code 0" {
  # AC: twl mcp restart コマンドが exit 0 で完了する
  # RED: twl mcp restart サブコマンドが存在しないため exit 1 以上で fail
  local twl_bin
  twl_bin="${MONO_ROOT}/cli/twl/twl"
  if [ ! -f "${twl_bin}" ]; then
    skip "twl binary not found at ${twl_bin}"
  fi
  run "${twl_bin}" mcp restart
  [ "${status}" -eq 0 ]
}

@test "ac2: 'twl mcp restart' does not emit 'error:' to stderr" {
  # AC: twl mcp restart 実行時に stderr にエラーメッセージが出ない
  # RED: 未実装のため argparse が "error: unrecognized arguments" を stderr に出力する
  local twl_bin
  twl_bin="${MONO_ROOT}/cli/twl/twl"
  if [ ! -f "${twl_bin}" ]; then
    skip "twl binary not found at ${twl_bin}"
  fi
  run bash -c "'${twl_bin}' mcp restart 2>&1 1>/dev/null"
  # stderr が空であることを確認（実装済みなら何も出ない）
  [ -z "${output}" ]
}

# ===========================================================================
# AC3: cli/twl/src/twl/mcp_server/README.md に再起動手順の記述が存在する
# ===========================================================================

@test "ac3: mcp_server/README.md mentions tools.py edit requires server restart" {
  # AC: README に「tools.py を編集したら server を再起動する」旨の記述が存在する
  # RED: 現在 README に再起動契機の記述が存在しないため fail
  run grep -qiE "tools\.py.*restart|restart.*tools\.py|再起動" "${MCP_README}"
  [ "${status}" -eq 0 ]
}

@test "ac3: mcp_server/README.md contains a restart section or procedure" {
  # AC: README に再起動手順を示すセクション（## Restart, ## 再起動 等）が存在する
  # RED: 現在そのようなセクションが存在しないため fail
  run grep -qiE "^## .*[Rr]estart|^## .*再起動" "${MCP_README}"
  [ "${status}" -eq 0 ]
}

@test "ac3: mcp_server/README.md contains 'twl mcp restart' command example" {
  # AC: README に 'twl mcp restart' コマンド例が記載されている
  # RED: 現在 README に該当コマンド例が存在しないため fail
  run grep -qF "twl mcp restart" "${MCP_README}"
  [ "${status}" -eq 0 ]
}
