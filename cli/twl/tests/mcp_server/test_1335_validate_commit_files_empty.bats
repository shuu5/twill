#!/usr/bin/env bats
# test_1335_validate_commit_files_empty.bats
#
# RED テストスタブ (Issue #1335)
#
# AC-5: regression bats で「files=[] 入力で常に ok=true」を契約として固定（spec lock）
#
# このテストは spec lock として機能する:
# - files=[] のとき twl_validate_commit_handler は常に ok=true を返さなければならない
# - この挙動は Claude Code hook 仕様制約（staged files が取得不可）による意図的な設計
# - 将来 hook 仕様が拡張された場合にこのテストを更新すること
#

GIT_ROOT=""
TOOLS_PY=""

setup() {
  GIT_ROOT="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel 2>/dev/null)"
  TOOLS_PY="${GIT_ROOT}/cli/twl/src/twl/mcp_server/tools.py"
}

# ---------------------------------------------------------------------------
# AC-5: files=[] 入力で常に ok=true (spec lock)
# ---------------------------------------------------------------------------

@test "ac5: files=[] で twl_validate_commit_handler は ok=true を返す (spec lock)" {
  # AC: regression bats で「files=[] 入力で常に ok=true」を契約として固定
  # この挙動は意図的設計: Claude Code hook 仕様制約で staged files が取得不可
  # RED: handler 未実装または挙動変更時に fail する

  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_validate_commit_handler
result = twl_validate_commit_handler(message='test: commit message', files=[])
assert result.get('ok') == True, f'expected ok=True, got {result}'
print('ok=True confirmed for files=[]')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok=True confirmed"* ]]
}

@test "ac5: files=[] で items リストは空 (no violations)" {
  # AC: files=[] のとき violations リストが空であること
  # RED: handler が files=[] 時に unexpected violation を返す場合 fail

  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_validate_commit_handler
result = twl_validate_commit_handler(message='feat: empty files list', files=[])
items = result.get('items', [])
assert items == [], f'expected items=[], got {items}'
print('items=[] confirmed')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"items=[] confirmed"* ]]
}

@test "ac5: files=[] で exit_code=0 (spec lock)" {
  # AC: files=[] のとき exit_code=0 であること
  # RED: exit_code が 0 以外の場合 fail

  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_validate_commit_handler
result = twl_validate_commit_handler(message='chore: no staged files', files=[])
assert result.get('exit_code') == 0, f'expected exit_code=0, got {result}'
print('exit_code=0 confirmed')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exit_code=0 confirmed"* ]]
}
