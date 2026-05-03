#!/usr/bin/env bats
# twl-validate-commit-message-extract.bats - Issue #1334: commit message extraction regression tests
#
# AC-4: extract_commit_message_from_command の抽出ロジック検証
#
# 検証 fixture:
#   - git commit -m "feat: X"        -> message="feat: X"
#   - git commit --message "fix: Y"  -> message="fix: Y"
#   - git commit -F /path/to/file    -> message="" (no-op / ファイルパスなので抽出対象外)
#
# RED: 実装前（extract_commit_message_from_command 未定義）は全テストが FAIL する。
#
# bats baseline §9 注意: このファイルはヒアドキュメントを使用しないため
# heredoc 変数展開の警告は適用しない。
#
# bats baseline §10 注意: python3 -c で直接インポートするため
# source guard パターンの適用は不要。

load '../helpers/common'

setup() {
  common_setup
  # REPO_ROOT は common_setup で REPO_ROOT 変数が設定される
  # helpers/common.bash より: REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
  REPO_GIT_ROOT="$(cd "${BATS_TEST_FILENAME%/*/*/*/*}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [[ -z "${REPO_GIT_ROOT}" ]]; then
    REPO_GIT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../../../.." && pwd)"
  fi
  TWILL_SRC="${REPO_GIT_ROOT}/cli/twl/src"
  export TWILL_SRC REPO_GIT_ROOT
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: extract_commit_message_from_command を python3 で呼び出す
# ---------------------------------------------------------------------------
_extract_msg() {
  local cmd="$1"
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${TWILL_SRC}')
try:
    from twl.mcp_server.tools import extract_commit_message_from_command
except (ImportError, AttributeError) as e:
    print(f"IMPORT_ERROR: {e}", file=sys.stderr)
    sys.exit(1)
result = extract_commit_message_from_command('${cmd}')
print(result)
PYEOF
}

# ===========================================================================
# AC-4: git commit -m "feat: X" -> message="feat: X"
# ===========================================================================

@test "ac4: extract_commit_message_from_command is importable from tools" {
  # AC: extract_commit_message_from_command が tools モジュールからインポートできること
  # RED: 実装前は ImportError または AttributeError で fail する
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${TWILL_SRC}')
try:
    from twl.mcp_server.tools import extract_commit_message_from_command
except ImportError as e:
    print(f"ImportError: {e}", file=sys.stderr)
    sys.exit(1)
except AttributeError as e:
    print(f"AttributeError (function not defined): {e}", file=sys.stderr)
    sys.exit(1)
print("OK")
PYEOF
}

@test "ac4: git commit -m extracts message (short flag)" {
  # AC: "git commit -m 'feat: X'" から message="feat: X" が抽出されること
  # RED: 関数未定義のため ImportError または AssertionError で fail する
  run python3 - <<PYEOF
import sys
sys.path.insert(0, '${TWILL_SRC}')
try:
    from twl.mcp_server.tools import extract_commit_message_from_command
except (ImportError, AttributeError) as e:
    print(f"EXTRACT_FUNC_MISSING: {e}", file=sys.stderr)
    sys.exit(1)
result = extract_commit_message_from_command('git commit -m "feat: X"')
expected = "feat: X"
if result != expected:
    print(f"FAIL: expected={expected!r}, got={result!r}", file=sys.stderr)
    sys.exit(1)
print("OK")
PYEOF
  [ "$status" -eq 0 ]
}

@test "ac4: git commit --message extracts message (long flag)" {
  # AC: "git commit --message 'fix: Y'" から message="fix: Y" が抽出されること
  # RED: 関数未定義のため ImportError または AssertionError で fail する
  run python3 - <<PYEOF
import sys
sys.path.insert(0, '${TWILL_SRC}')
try:
    from twl.mcp_server.tools import extract_commit_message_from_command
except (ImportError, AttributeError) as e:
    print(f"EXTRACT_FUNC_MISSING: {e}", file=sys.stderr)
    sys.exit(1)
result = extract_commit_message_from_command('git commit --message "fix: Y"')
expected = "fix: Y"
if result != expected:
    print(f"FAIL: expected={expected!r}, got={result!r}", file=sys.stderr)
    sys.exit(1)
print("OK")
PYEOF
  [ "$status" -eq 0 ]
}

@test "ac4: git commit -F returns empty string (no-op, file-based commit)" {
  # AC: "git commit -F /path/to/file" の場合 message="" が返ること
  #     (ファイルから読む形式は MCP shadow では抽出対象外として no-op 扱い)
  # RED: 関数未定義のため ImportError で fail する
  run python3 - <<PYEOF
import sys
sys.path.insert(0, '${TWILL_SRC}')
try:
    from twl.mcp_server.tools import extract_commit_message_from_command
except (ImportError, AttributeError) as e:
    print(f"EXTRACT_FUNC_MISSING: {e}", file=sys.stderr)
    sys.exit(1)
result = extract_commit_message_from_command('git commit -F /path/to/file')
# -F はファイル読み込みなので抽出不可 -> 空文字列を期待
if result != "":
    print(f"FAIL: expected empty string for -F form, got={result!r}", file=sys.stderr)
    sys.exit(1)
print("OK")
PYEOF
  [ "$status" -eq 0 ]
}

@test "ac4: twl_validate_commit_handler accepts command param (integration)" {
  # AC: twl_validate_commit_handler が command キーワード引数を受け付け、正常に動作すること
  # RED: 現在のシグネチャは message: str なので TypeError で fail する
  run python3 - <<PYEOF
import sys
sys.path.insert(0, '${TWILL_SRC}')
try:
    from twl.mcp_server.tools import twl_validate_commit_handler
except ImportError as e:
    print(f"ImportError: {e}", file=sys.stderr)
    sys.exit(1)
try:
    result = twl_validate_commit_handler(
        command='git commit -m "feat: test command param"',
        files=[],
    )
except TypeError as e:
    print(f"TypeError (signature not updated): {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(result, dict):
    print(f"FAIL: result is not dict, got={result!r}", file=sys.stderr)
    sys.exit(1)
if "ok" not in result:
    print(f"FAIL: 'ok' key missing from result, got={result}", file=sys.stderr)
    sys.exit(1)
print("OK")
PYEOF
  [ "$status" -eq 0 ]
}

@test "ac4: git commit -m with single quotes extracts message" {
  # AC: "git commit -m 'chore: update'" のシングルクォート形式も抽出できること
  # RED: 関数未定義のため fail する
  run python3 - <<PYEOF
import sys
sys.path.insert(0, '${TWILL_SRC}')
try:
    from twl.mcp_server.tools import extract_commit_message_from_command
except (ImportError, AttributeError) as e:
    print(f"EXTRACT_FUNC_MISSING: {e}", file=sys.stderr)
    sys.exit(1)
result = extract_commit_message_from_command("git commit -m 'chore: update'")
expected = "chore: update"
if result != expected:
    print(f"FAIL: expected={expected!r}, got={result!r}", file=sys.stderr)
    sys.exit(1)
print("OK")
PYEOF
  [ "$status" -eq 0 ]
}
