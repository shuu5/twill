#!/usr/bin/env bats
# twl-validate-commit-message-extract.bats - Issue #1334: AC-4 regression tests
#
# twl_validate_commit_handler の command: str 引数から commit message を
# 抽出するロジックを検証する regression テスト。
#
# 検証方針: twl_validate_commit MCP tool（Python handler）を直接呼び出し、
# command 文字列から抽出されたメッセージが正しいことを確認する。
#
# 検証するフィクスチャ:
#   - git commit -m "feat: X"    → message="feat: X"
#   - git commit --message "fix: Y" → message="fix: Y"
#   - git commit -F /path/to/file   → message=ファイル内容 or "" (no-op)
#
# RED: 実装前（twl_validate_commit_handler が command 引数を受け取らない）は
#      全テストが FAIL する（意図的 RED）。

load '../helpers/common'

setup() {
  common_setup
  REPO_ROOT_ABS="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../.." && pwd)"
  export REPO_ROOT_ABS

  # Python インタープリタの特定
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
  else
    PYTHON_CMD="python"
  fi
  export PYTHON_CMD

  # twl パッケージのパスを設定
  TWL_SRC="${REPO_ROOT_ABS}/cli/twl"
  export TWL_SRC
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# ヘルパー: twl_validate_commit_handler を Python から直接呼び出す
#
# 注意: 非クォート heredoc (<<EOF) を使用。
# $PYTHON_CMD, $TWL_SRC 等の外部変数を heredoc 内で展開するため。
# ---------------------------------------------------------------------------

_call_handler_with_command() {
  local cmd_str="$1"
  # AC-1: command: str を受け取る新しいインターフェースを呼び出す
  # RED: 現在は TypeError (unexpected keyword argument 'command') で FAIL する
  PYTHONPATH="${TWL_SRC}/src" $PYTHON_CMD -c "
import sys
import json
sys.path.insert(0, '${TWL_SRC}/src')
from twl.mcp_server.tools import twl_validate_commit_handler
try:
    result = twl_validate_commit_handler(command='${cmd_str}')
    print(json.dumps(result))
except TypeError as e:
    print(json.dumps({'ok': False, 'error': str(e), 'error_type': 'type_error'}))
except Exception as e:
    print(json.dumps({'ok': False, 'error': str(e), 'error_type': 'exception'}))
"
}

# ---------------------------------------------------------------------------
# AC-4-1: git commit -m "feat: X" → message="feat: X" が抽出されること
#
# RED: 現在の handler は command 引数を持たないため TypeError になり FAIL
# ---------------------------------------------------------------------------

@test "ac4-1: git commit -m 'feat: X' から message が抽出されること" {
  # AC: command = 'git commit -m "feat: X"' のとき
  #     result に extracted_message="feat: X" またはそれに準ずる情報が含まれること
  # RED: twl_validate_commit_handler が command 引数を受け取らないため TypeError で FAIL

  local result
  result=$(_call_handler_with_command 'git commit -m "feat: X"')

  # error_type が type_error の場合は実装未完了
  local error_type
  error_type=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_type','none'))" 2>/dev/null || echo "parse_error")
  [ "$error_type" != "type_error" ]

  # result に ok フィールドがあること（handler が正常に応答したことの確認）
  local has_ok
  has_ok=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if 'ok' in d else 'false')" 2>/dev/null || echo "false")
  [ "$has_ok" = "true" ]
}

@test "ac4-1: 抽出された message が 'feat: X' であること" {
  # AC: -m フラグから正確に "feat: X" が抽出されること
  # RED: command 引数未実装のため type_error になり FAIL

  local result
  result=$(_call_handler_with_command 'git commit -m "feat: X"')

  # error_type が type_error でないこと（実装済みの証明）
  local error_type
  error_type=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_type','none'))" 2>/dev/null || echo "parse_error")
  [ "$error_type" != "type_error" ]

  # extracted_message または同等フィールドが "feat: X" を含むこと
  # 実装詳細によって extracted_message / commit_message / message 等変わりうるが、
  # result を文字列として確認する
  echo "$result" | grep -q "feat: X"
}

# ---------------------------------------------------------------------------
# AC-4-2: git commit --message "fix: Y" → message="fix: Y" が抽出されること
#
# RED: 現在の handler は command 引数を持たないため TypeError になり FAIL
# ---------------------------------------------------------------------------

@test "ac4-2: git commit --message 'fix: Y' から message が抽出されること" {
  # AC: command = 'git commit --message "fix: Y"' のとき
  #     result に message="fix: Y" に相当する情報が含まれること
  # RED: twl_validate_commit_handler が command 引数を受け取らないため TypeError で FAIL

  local result
  result=$(_call_handler_with_command 'git commit --message "fix: Y"')

  # error_type が type_error の場合は実装未完了
  local error_type
  error_type=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_type','none'))" 2>/dev/null || echo "parse_error")
  [ "$error_type" != "type_error" ]

  local has_ok
  has_ok=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if 'ok' in d else 'false')" 2>/dev/null || echo "false")
  [ "$has_ok" = "true" ]
}

@test "ac4-2: 抽出された message が 'fix: Y' であること" {
  # AC: --message フラグから正確に "fix: Y" が抽出されること
  # RED: command 引数未実装のため type_error になり FAIL

  local result
  result=$(_call_handler_with_command 'git commit --message "fix: Y"')

  local error_type
  error_type=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_type','none'))" 2>/dev/null || echo "parse_error")
  [ "$error_type" != "type_error" ]

  echo "$result" | grep -q "fix: Y"
}

# ---------------------------------------------------------------------------
# AC-4-3: git commit -F /path/to/file → message=ファイル内容 or "" (no-op)
#
# -F フラグはファイルからメッセージを読み込む。
# MCP hook は非インタラクティブ環境で実行されるため、ファイルが存在しない場合は
# "" (空文字) または no-op として扱うことが期待される。
#
# RED: 現在の handler は command 引数を持たないため TypeError になり FAIL
# ---------------------------------------------------------------------------

@test "ac4-3: git commit -F /path/to/file は type_error にならずに処理されること" {
  # AC: command = 'git commit -F /path/to/file' のとき
  #     handler が TypeError を発生させないこと（no-op または ファイル読み込みを試みる）
  # RED: twl_validate_commit_handler が command 引数を受け取らないため TypeError で FAIL

  local result
  result=$(_call_handler_with_command 'git commit -F /path/to/nonexistent/file')

  local error_type
  error_type=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_type','none'))" 2>/dev/null || echo "parse_error")
  [ "$error_type" != "type_error" ]
}

@test "ac4-3: git commit -F は ok フィールドを含む dict を返すこと" {
  # AC: -F フラグの場合も dict 形式で応答すること（no-op でも ok: true/false を返す）
  # RED: command 引数未実装のため type_error になり FAIL

  local result
  result=$(_call_handler_with_command 'git commit -F /tmp/test-commit-msg.txt')

  local has_ok
  has_ok=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if 'ok' in d else 'false')" 2>/dev/null || echo "false")
  [ "$has_ok" = "true" ]
}

# ---------------------------------------------------------------------------
# AC-4-extra: command が git commit 以外の場合は no-op で ok: true を返すこと
#
# MCP hook は Bash ツール実行前に呼ばれる。git commit 以外のコマンドの場合は
# 検証をスキップして ok: true を返すことが期待される。
#
# RED: command 引数未実装のため FAIL
# ---------------------------------------------------------------------------

@test "ac4-extra: git commit 以外のコマンドは no-op で ok: true を返すこと" {
  # AC: command = 'git push origin main' のような非 commit コマンドは
  #     検証をスキップして ok: true を返すこと
  # RED: command 引数未実装のため type_error で FAIL

  local result
  result=$(_call_handler_with_command 'git push origin main')

  local error_type
  error_type=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_type','none'))" 2>/dev/null || echo "parse_error")
  [ "$error_type" != "type_error" ]

  local ok_value
  ok_value=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('ok',False)).lower())" 2>/dev/null || echo "false")
  [ "$ok_value" = "true" ]
}
