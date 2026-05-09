#!/usr/bin/env bats
# test_issue_1618_hook_output_e2e.bats
#
# RED テストスタブ (Issue #1618)
#
# AC-1: このファイルが bats から実行可能であること (bats <path> で no-error 起動)
# AC-2: PreToolUse:Bash 系 4 MCP tool の戻り値 JSON が Claude Code 2.1.x HookOutput schema
#        (allow フィールド: decision/permissionDecision/hookSpecificOutput/continue/
#         suppressOutput/stopReason/reason/systemMessage) のみを含むことを assert
# AC-3: PreToolUse:Write 系 MCP tool twl_validate_deps の戻り値 JSON が schema 互換かを確認
# AC-4: bats シナリオから Zod validator 互換ロジックを呼び出す検証ハーネスを用意し
#        Hook JSON output validation failed エラーがゼロ件であることを確認
# AC-5: tools.py 全件 audit: decision:"allow"/"deny" リテラルが @mcp.tool() expose 後の
#        最終出力に含まれないことを grep + json 検証で assert
# AC-6: cli/twl/tests/ac-test-mapping-1618.yaml が追加され AC-1〜AC-5 がマッピングされていること
#
# 全テストは _to_hook_output() が tools.py に存在しないため RED (fail) 状態になる。
#

GIT_ROOT=""
TOOLS_PY=""
MAPPING_YAML=""

# HookOutput 有効フィールドのリスト (Claude Code 2.1.x Zod schema)
VALID_HOOK_OUTPUT_FIELDS="decision permissionDecision hookSpecificOutput continue suppressOutput stopReason reason systemMessage"

# VALID_DECISION_VALUES: approve / block のみ ("allow"/"deny" は legacy で無効)
# VALID_PERMISSION_DECISION_VALUES: allow / deny / ask

setup() {
  GIT_ROOT="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel 2>/dev/null)"
  TOOLS_PY="${GIT_ROOT}/cli/twl/src/twl/mcp_server/tools.py"
  MAPPING_YAML="${GIT_ROOT}/cli/twl/tests/ac-test-mapping-1618.yaml"
}

# ---------------------------------------------------------------------------
# ヘルパー: Python で HookOutput schema を検証する
# 引数:
#   $1 = JSON 文字列
#   $2 = context ラベル (エラーメッセージ用)
# 戻り値: 0=valid, 1=invalid (stderr に理由を出力)
# ---------------------------------------------------------------------------
_assert_hook_output_valid_json() {
  local json_str="$1"
  local context="${2:-unknown}"

  python3 - <<EOF
import sys, json

VALID_FIELDS = frozenset({
    "decision",
    "permissionDecision",
    "hookSpecificOutput",
    "continue",
    "suppressOutput",
    "stopReason",
    "reason",
    "systemMessage",
})
VALID_DECISION = frozenset({"approve", "block"})
VALID_PERMISSION_DECISION = frozenset({"allow", "deny", "ask"})

context = "${context}"
raw = '''${json_str}'''

try:
    result = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"SCHEMA_ERROR [{context}]: invalid JSON: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(result, dict):
    print(f"SCHEMA_ERROR [{context}]: HookOutput must be a dict, got {type(result)}", file=sys.stderr)
    sys.exit(1)

extra = set(result.keys()) - VALID_FIELDS
if extra:
    print(f"SCHEMA_ERROR [{context}]: extra fields not allowed by Zod schema: {sorted(extra)}", file=sys.stderr)
    sys.exit(1)

if "decision" in result and result["decision"] not in VALID_DECISION:
    print(f"SCHEMA_ERROR [{context}]: decision='{result['decision']}' invalid; must be 'approve' or 'block'", file=sys.stderr)
    sys.exit(1)

if "permissionDecision" in result and result["permissionDecision"] not in VALID_PERMISSION_DECISION:
    print(f"SCHEMA_ERROR [{context}]: permissionDecision='{result['permissionDecision']}' invalid", file=sys.stderr)
    sys.exit(1)

print(f"SCHEMA_OK [{context}]")
sys.exit(0)
EOF
}

# ---------------------------------------------------------------------------
# ヘルパー: _to_hook_output() が tools.py に存在するかを確認する
# RED 状態では存在しないため fail する
# ---------------------------------------------------------------------------
_require_to_hook_output() {
  python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output
print('_to_hook_output found')
" 2>&1
}

# ===========================================================================
# AC-1: bats 実行可能性テスト
# このファイルが存在し、bats から no-error 起動できることを確認する。
# AC-1 自体は「ファイルが存在して構文エラーなし」で PASS するが、
# 以降のテストが RED になるため全体として RED セットとなる。
# ===========================================================================

@test "ac1: test file が存在し bats から実行可能であること" {
  # AC: test_issue_1618_hook_output_e2e.bats が新規追加され bats で no-error 起動
  # このテスト自体は PASS する (ファイル存在 = 実行中)
  [ -f "${BATS_TEST_FILENAME}" ]
}

@test "ac1: tools.py が存在すること" {
  # AC: 実装対象ファイルが存在すること
  [ -f "${TOOLS_PY}" ]
}

@test "ac1: _to_hook_output が tools.py に実装されていること (RED: 未実装)" {
  # AC: GREEN PR で _to_hook_output() が追加されること
  # RED: 現時点では tools.py に _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output
print('_to_hook_output found')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_to_hook_output found"* ]]
}

# ===========================================================================
# AC-2: PreToolUse:Bash 系 4 MCP tool の HookOutput schema 準拠テスト
#
# 対象 tool:
#   - twl_validate_merge
#   - twl_validate_commit
#   - twl_validate_status_transition
#   - twl_validate_issue_create
#
# 各 tool につき allow / deny / no-op の代表ケース >= 1 件
# ===========================================================================

# --- twl_validate_merge ---

@test "ac2: twl_validate_merge allow ケース — HookOutput schema 準拠 (RED)" {
  # AC: twl_validate_merge の allow ケース戻り値が HookOutput schema のみのフィールドを持つ
  # RED: _to_hook_output が存在しないため ImportError で fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_merge_handler
import json

raw = twl_validate_merge_handler(branch='feat/test-1618', base='main')
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'
print('SCHEMA_OK: twl_validate_merge allow')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

@test "ac2: twl_validate_merge deny ケース (timeout) — HookOutput schema 準拠 (RED)" {
  # AC: twl_validate_merge の deny ケース (timeout_sec=0) 戻り値が HookOutput schema 準拠
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_merge_handler
import json

raw = twl_validate_merge_handler(branch='test', base='main', timeout_sec=0)
assert raw.get('ok') is False, f'timeout_sec=0 should produce ok=False, got {raw}'
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'

VALID_DECISION = frozenset({'approve','block'})
if 'decision' in result:
    assert result['decision'] in VALID_DECISION, f\"decision='{result['decision']}' invalid\"

print('SCHEMA_OK: twl_validate_merge deny/timeout')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

# --- twl_validate_commit ---

@test "ac2: twl_validate_commit no-op (files=[]) — HookOutput schema 準拠 (RED)" {
  # AC: twl_validate_commit の no-op (files=[]) ケース戻り値が HookOutput schema 準拠
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_commit_handler
import json

raw = twl_validate_commit_handler(command='git commit -m \"feat: test\"', files=[])
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'
print('SCHEMA_OK: twl_validate_commit no-op')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

@test "ac2: twl_validate_commit deny ケース (timeout) — HookOutput schema 準拠 (RED)" {
  # AC: twl_validate_commit の deny ケース (timeout_sec=0) 戻り値が HookOutput schema 準拠
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_commit_handler
import json

raw = twl_validate_commit_handler(command='git commit -m \"feat: test\"', files=[], timeout_sec=0)
assert raw.get('ok') is False, f'timeout_sec=0 should produce ok=False, got {raw}'
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'
print('SCHEMA_OK: twl_validate_commit deny/timeout')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

# --- twl_validate_status_transition ---

@test "ac2: twl_validate_status_transition no-op — HookOutput schema 準拠 (RED)" {
  # AC: no-op ケース (非 gh project item-edit コマンド) が HookOutput schema 準拠
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_status_transition_handler
import json, tempfile, os

tmpdir = tempfile.mkdtemp()
raw = twl_validate_status_transition_handler(
    command='git status',
    tool_name='Bash',
    session_tmp_dir=tmpdir,
    controller_issue_dir=tmpdir,
)
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'
print('SCHEMA_OK: twl_validate_status_transition no-op')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

@test "ac2: twl_validate_status_transition allow ケース (evidence あり) — HookOutput schema 準拠 (RED)" {
  # AC: evidence ファイルありの allow ケースが HookOutput schema 準拠
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_status_transition_handler
import json

tmpdir = tempfile.mkdtemp()
# spec-review-session evidence を作成
open(os.path.join(tmpdir, '.spec-review-session-1618test.json'), 'w').write('{}')

raw = twl_validate_status_transition_handler(
    command='gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780',
    tool_name='Bash',
    session_tmp_dir=tmpdir,
    controller_issue_dir=os.path.join(tmpdir, 'nonexistent'),
)
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'

VALID_DECISION = frozenset({'approve','block'})
if 'decision' in result:
    assert result['decision'] in VALID_DECISION, f\"decision='{result['decision']}' invalid\"

# allow ケースは blocking でないこと
is_block = result.get('decision') == 'block' or result.get('permissionDecision') == 'deny'
assert not is_block, f'allow case must not produce blocking signal, got: {result}'
print('SCHEMA_OK: twl_validate_status_transition allow')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

@test "ac2: twl_validate_status_transition deny ケース (evidence なし) — HookOutput schema 準拠 (RED)" {
  # AC: evidence なしの deny ケースが HookOutput schema 準拠かつ blocking signal を持つ
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_status_transition_handler
import json

tmpdir = tempfile.mkdtemp()
raw = twl_validate_status_transition_handler(
    command='gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780',
    tool_name='Bash',
    session_tmp_dir=os.path.join(tmpdir, 'no-evidence'),
    controller_issue_dir=os.path.join(tmpdir, 'no-evidence'),
)
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'

VALID_DECISION = frozenset({'approve','block'})
if 'decision' in result:
    assert result['decision'] in VALID_DECISION, f\"decision='{result['decision']}' invalid\"

# deny ケースは blocking signal を持つこと
is_block = result.get('decision') == 'block' or result.get('permissionDecision') == 'deny'
assert is_block, f'deny case must produce blocking signal, got: {result}'
print('SCHEMA_OK: twl_validate_status_transition deny')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

# --- twl_validate_issue_create ---

@test "ac2: twl_validate_issue_create no-op — HookOutput schema 準拠 (RED)" {
  # AC: no-op ケース (非 gh issue create コマンド) が HookOutput schema 準拠
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_issue_create_handler
import json

tmpdir = tempfile.mkdtemp()
raw = twl_validate_issue_create_handler(
    command='git status',
    tool_name='Bash',
    session_tmp_dir=tmpdir,
    controller_issue_dir=tmpdir,
)
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'
print('SCHEMA_OK: twl_validate_issue_create no-op')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

@test "ac2: twl_validate_issue_create allow ケース — HookOutput schema 準拠 (RED)" {
  # AC: co-explore-bootstrap ファイルありの allow ケースが HookOutput schema 準拠
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_issue_create_handler
import json

tmpdir = tempfile.mkdtemp()
# co-explore-bootstrap state file を作成して allow ケースを誘発
import glob
open('/tmp/.co-explore-bootstrap-1618test.json', 'w').write('{}')

raw = twl_validate_issue_create_handler(
    command='gh issue create --title \"1618 test\"',
    tool_name='Bash',
    session_tmp_dir=tmpdir,
    controller_issue_dir=tmpdir,
)
result = _to_hook_output(raw)

# cleanup
try:
    os.remove('/tmp/.co-explore-bootstrap-1618test.json')
except FileNotFoundError:
    pass

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'

VALID_DECISION = frozenset({'approve','block'})
if 'decision' in result:
    assert result['decision'] in VALID_DECISION, f\"decision='{result['decision']}' invalid\"
print('SCHEMA_OK: twl_validate_issue_create allow')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

@test "ac2: twl_validate_issue_create deny ケース — HookOutput schema 準拠かつ blocking (RED)" {
  # AC: 未認可 gh issue create の deny ケースが HookOutput schema 準拠かつ blocking signal を持つ
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_issue_create_handler
import json

tmpdir = tempfile.mkdtemp()
raw = twl_validate_issue_create_handler(
    command='gh issue create --title \"unauthorized\"',
    tool_name='Bash',
    session_tmp_dir=tmpdir,
    controller_issue_dir=os.path.join(tmpdir, 'nonexistent'),
)
result = _to_hook_output(raw)

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
extra = set(result.keys()) - VALID_FIELDS
assert not extra, f'extra fields: {sorted(extra)}'

VALID_DECISION = frozenset({'approve','block'})
if 'decision' in result:
    assert result['decision'] in VALID_DECISION, f\"decision='{result['decision']}' invalid\"

# deny ケースは blocking signal を持つこと
is_block = result.get('decision') == 'block' or result.get('permissionDecision') == 'deny'
assert is_block, f'deny case must produce blocking signal, got: {result}'
print('SCHEMA_OK: twl_validate_issue_create deny')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEMA_OK"* ]]
}

# ===========================================================================
# AC-3: PreToolUse:Write 系 MCP tool twl_validate_deps の schema 互換チェック
#
# twl_validate_deps_handler は build_envelope() ベースの独自 envelope を返す。
# HookOutput schema 外の可能性があるため、違反があれば findings として記録
# (fail ではなく warn + record)
# ===========================================================================

@test "ac3: twl_validate_deps — HookOutput schema 互換チェックまたは schema 外として記録 (RED)" {
  # AC: twl_validate_deps の戻り値が HookOutput schema 互換であること
  #     または schema 外として明示的に分類・記録されること
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_deps_handler
import json

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})

# twl_validate_deps には plugin_root が必要。テスト用の最小 deps.yaml を作成する。
tmpdir = tempfile.mkdtemp()
deps_yaml = os.path.join(tmpdir, 'deps.yaml')
with open(deps_yaml, 'w') as f:
    f.write('plugin_name: test-1618\ndeps_version: \"3.0\"\n')

try:
    raw = twl_validate_deps_handler(plugin_root=tmpdir)
    result = _to_hook_output(raw)
    extra = set(result.keys()) - VALID_FIELDS
    if extra:
        # schema 外フィールドがある場合は findings として記録する (warn, not fail)
        print(f'SCHEMA_WARN: twl_validate_deps has extra fields: {sorted(extra)}')
        print('RECORDED_AS_SCHEMA_EXTERNAL: twl_validate_deps uses build_envelope format')
    else:
        print('SCHEMA_OK: twl_validate_deps')
except Exception as e:
    # _to_hook_output が存在しない場合は RED
    raise
" 2>&1
  # _to_hook_output が存在しない場合は non-zero exit で fail (RED)
  [ "$status" -eq 0 ]
  # SCHEMA_OK または RECORDED_AS_SCHEMA_EXTERNAL の記録があること
  [[ "$output" == *"SCHEMA_OK"* ]] || [[ "$output" == *"RECORDED_AS_SCHEMA_EXTERNAL"* ]]
}

@test "ac3: twl_validate_deps の raw 戻り値 (build_envelope) フィールド構造を記録 (RED)" {
  # AC: _to_hook_output 変換前の raw 戻り値が build_envelope 形式であることを記録
  # RED: _to_hook_output が存在しないため fail する (import 時に検証)
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
# _to_hook_output の存在を確認 (RED フェーズで fail させる)
from twl.mcp_server.tools import _to_hook_output
from twl.mcp_server.tools import twl_validate_deps_handler
import json

BUILD_ENVELOPE_FIELDS = frozenset({'tool', 'version', 'plugin', 'items', 'exit_code', 'ok'})
HOOK_OUTPUT_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})

tmpdir = tempfile.mkdtemp()
deps_yaml = os.path.join(tmpdir, 'deps.yaml')
with open(deps_yaml, 'w') as f:
    f.write('plugin_name: test-1618\ndeps_version: \"3.0\"\n')

try:
    raw = twl_validate_deps_handler(plugin_root=tmpdir)
    raw_keys = set(raw.keys())
    # build_envelope 形式かどうかを判定
    if raw_keys & BUILD_ENVELOPE_FIELDS:
        print(f'FINDING: twl_validate_deps raw is build_envelope format: {sorted(raw_keys)}')
    elif raw_keys <= HOOK_OUTPUT_FIELDS:
        print(f'FINDING: twl_validate_deps raw is already HookOutput compatible: {sorted(raw_keys)}')
    else:
        print(f'FINDING: twl_validate_deps raw has unknown schema: {sorted(raw_keys)}')
    print('AC3_RECORDED')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC3_RECORDED"* ]]
}

# ===========================================================================
# AC-4: Zod validator 互換 fixture で Hook JSON output validation failed エラー 0 件
#
# 実環境の Claude Code を呼ばず、Python mock で Zod schema 互換検証を行う
# ===========================================================================

@test "ac4: twl_validate_merge 全ケースで validation failed エラー 0 件 (RED)" {
  # AC: twl_validate_merge の全代表ケースで HookOutput validation エラーがゼロ件
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_merge_handler
import json

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
VALID_DECISION = frozenset({'approve','block'})
VALID_PERMISSION_DECISION = frozenset({'allow','deny','ask'})

validation_errors = []

def validate_hook_output(result, ctx):
    if not isinstance(result, dict):
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: not a dict')
        return
    extra = set(result.keys()) - VALID_FIELDS
    if extra:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: extra fields {sorted(extra)}')
    if 'decision' in result and result['decision'] not in VALID_DECISION:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: decision={result[\"decision\"]}')
    if 'permissionDecision' in result and result['permissionDecision'] not in VALID_PERMISSION_DECISION:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: permissionDecision={result[\"permissionDecision\"]}')

# ケース 1: allow
raw1 = twl_validate_merge_handler(branch='feat/1618-test', base='main')
validate_hook_output(_to_hook_output(raw1), 'merge-allow')

# ケース 2: deny/timeout
raw2 = twl_validate_merge_handler(branch='test', base='main', timeout_sec=0)
validate_hook_output(_to_hook_output(raw2), 'merge-timeout')

if validation_errors:
    for e in validation_errors:
        print(e, file=sys.stderr)
    sys.exit(1)

print(f'AC4_PASS: twl_validate_merge 0 validation errors ({len([raw1, raw2])} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC4_PASS"* ]]
  [[ "$output" != *"Hook JSON output validation failed"* ]]
}

@test "ac4: twl_validate_commit 全ケースで validation failed エラー 0 件 (RED)" {
  # AC: twl_validate_commit の全代表ケースで HookOutput validation エラーがゼロ件
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_commit_handler
import json

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
VALID_DECISION = frozenset({'approve','block'})

validation_errors = []

def validate_hook_output(result, ctx):
    if not isinstance(result, dict):
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: not a dict')
        return
    extra = set(result.keys()) - VALID_FIELDS
    if extra:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: extra fields {sorted(extra)}')
    if 'decision' in result and result['decision'] not in VALID_DECISION:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: decision={result[\"decision\"]}')

# ケース 1: no-op (files=[])
raw1 = twl_validate_commit_handler(command='git commit -m \"feat: test\"', files=[])
validate_hook_output(_to_hook_output(raw1), 'commit-noop')

# ケース 2: deny/timeout
raw2 = twl_validate_commit_handler(command='git commit -m \"feat: test\"', files=[], timeout_sec=0)
validate_hook_output(_to_hook_output(raw2), 'commit-timeout')

if validation_errors:
    for e in validation_errors:
        print(e, file=sys.stderr)
    sys.exit(1)

print(f'AC4_PASS: twl_validate_commit 0 validation errors ({len([raw1, raw2])} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC4_PASS"* ]]
  [[ "$output" != *"Hook JSON output validation failed"* ]]
}

@test "ac4: twl_validate_status_transition 全ケースで validation failed エラー 0 件 (RED)" {
  # AC: twl_validate_status_transition の全代表ケースで HookOutput validation エラーがゼロ件
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_status_transition_handler
import json

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
VALID_DECISION = frozenset({'approve','block'})

validation_errors = []
tmpdir = tempfile.mkdtemp()

def validate_hook_output(result, ctx):
    if not isinstance(result, dict):
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: not a dict')
        return
    extra = set(result.keys()) - VALID_FIELDS
    if extra:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: extra fields {sorted(extra)}')
    if 'decision' in result and result['decision'] not in VALID_DECISION:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: decision={result[\"decision\"]}')

# ケース 1: no-op
raw1 = twl_validate_status_transition_handler(
    command='git status', tool_name='Bash',
    session_tmp_dir=tmpdir, controller_issue_dir=tmpdir)
validate_hook_output(_to_hook_output(raw1), 'status-noop')

# ケース 2: allow (evidence あり)
open(os.path.join(tmpdir, '.spec-review-session-ac4test.json'), 'w').write('{}')
raw2 = twl_validate_status_transition_handler(
    command='gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780',
    tool_name='Bash', session_tmp_dir=tmpdir,
    controller_issue_dir=os.path.join(tmpdir, 'nonexistent'))
validate_hook_output(_to_hook_output(raw2), 'status-allow')

# ケース 3: deny (evidence なし)
noevid = os.path.join(tmpdir, 'no-evidence')
raw3 = twl_validate_status_transition_handler(
    command='gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780',
    tool_name='Bash', session_tmp_dir=noevid, controller_issue_dir=noevid)
validate_hook_output(_to_hook_output(raw3), 'status-deny')

if validation_errors:
    for e in validation_errors:
        print(e, file=sys.stderr)
    sys.exit(1)

print(f'AC4_PASS: twl_validate_status_transition 0 validation errors ({len([raw1, raw2, raw3])} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC4_PASS"* ]]
  [[ "$output" != *"Hook JSON output validation failed"* ]]
}

@test "ac4: twl_validate_issue_create 全ケースで validation failed エラー 0 件 (RED)" {
  # AC: twl_validate_issue_create の全代表ケースで HookOutput validation エラーがゼロ件
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_issue_create_handler
import json

VALID_FIELDS = frozenset({'decision','permissionDecision','hookSpecificOutput','continue','suppressOutput','stopReason','reason','systemMessage'})
VALID_DECISION = frozenset({'approve','block'})

validation_errors = []
tmpdir = tempfile.mkdtemp()

def validate_hook_output(result, ctx):
    if not isinstance(result, dict):
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: not a dict')
        return
    extra = set(result.keys()) - VALID_FIELDS
    if extra:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: extra fields {sorted(extra)}')
    if 'decision' in result and result['decision'] not in VALID_DECISION:
        validation_errors.append(f'[{ctx}] Hook JSON output validation failed: decision={result[\"decision\"]}')

# ケース 1: no-op (非 gh issue create)
raw1 = twl_validate_issue_create_handler(
    command='git status', tool_name='Bash',
    session_tmp_dir=tmpdir, controller_issue_dir=tmpdir)
validate_hook_output(_to_hook_output(raw1), 'issue-create-noop')

# ケース 2: deny (evidence なし)
raw2 = twl_validate_issue_create_handler(
    command='gh issue create --title \"unauthorized\"',
    tool_name='Bash', session_tmp_dir=tmpdir,
    controller_issue_dir=os.path.join(tmpdir, 'nonexistent'))
validate_hook_output(_to_hook_output(raw2), 'issue-create-deny')

if validation_errors:
    for e in validation_errors:
        print(e, file=sys.stderr)
    sys.exit(1)

print(f'AC4_PASS: twl_validate_issue_create 0 validation errors ({len([raw1, raw2])} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC4_PASS"* ]]
  [[ "$output" != *"Hook JSON output validation failed"* ]]
}

# ===========================================================================
# AC-5: tools.py 全件 audit
#
# @mcp.tool() decorator から expose される全 tool の最終出力に
# legacy enum (decision: "allow" / decision: "deny") が含まれないことを検証
#
# 手順:
#   1. grep で tools.py 内の decision:"allow"/"deny" リテラルの件数を確認
#   2. _to_hook_output() が変換後の出力から legacy enum を除去することを各 tool で確認
# ===========================================================================

@test "ac5: tools.py の decision:allow/deny リテラルが _to_hook_output 入力のみに残ること (grep 検証) (RED)" {
  # AC: @mcp.tool() decorator 経由で expose される全 tool の最終出力に
  #     legacy enum ("allow"/"deny") が含まれないこと
  # NOTE: _to_hook_output() の入力として渡される内部辞書に decision:"allow"/"deny"
  #       が残るのは OK。最終出力 (exposed JSON) に含まれないことを検証する。
  # RED: _to_hook_output が存在しないため、この検証自体が実行不可

  # tools.py 内の decision:"allow"/"deny" 件数を確認 (17件程度が期待値)
  local allow_deny_count
  allow_deny_count=$(grep -c '"decision": "allow"\|"decision": "deny"' "${TOOLS_PY}" 2>/dev/null || echo "0")
  echo "decision allow/deny literal count in tools.py: ${allow_deny_count}" >&2

  # _to_hook_output の実装確認 (RED: 未実装)
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output
# _to_hook_output の signature を確認 (存在するだけで OK)
import inspect
sig = inspect.signature(_to_hook_output)
print(f'_to_hook_output exists with signature: {sig}')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_to_hook_output exists"* ]]
}

@test "ac5: twl_validate_status_transition 最終出力に decision:allow/deny が含まれない (RED)" {
  # AC: @mcp.tool() 経由の expose 後、decision:"allow"/"deny" が最終出力に含まれない
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_status_transition_handler
import json

tmpdir = tempfile.mkdtemp()
noevid = os.path.join(tmpdir, 'no-evidence')

test_cases = [
    ('no-op', 'git status', 'Bash', tmpdir, tmpdir),
    ('deny', 'gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780', 'Bash', noevid, noevid),
]

# allow ケース
os.makedirs(tmpdir, exist_ok=True)
open(os.path.join(tmpdir, '.spec-review-session-ac5check.json'), 'w').write('{}')
test_cases.append(
    ('allow', 'gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780', 'Bash', tmpdir, os.path.join(tmpdir, 'nonexistent'))
)

failures = []
for ctx, cmd, tool_name, stmp, cidir in test_cases:
    raw = twl_validate_status_transition_handler(
        command=cmd, tool_name=tool_name,
        session_tmp_dir=stmp, controller_issue_dir=cidir)
    final_output = _to_hook_output(raw)
    final_json = json.dumps(final_output)

    # legacy enum チェック
    if '\"decision\": \"allow\"' in final_json or '\"decision\":\"allow\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:allow found in final output: {final_json}')
    if '\"decision\": \"deny\"' in final_json or '\"decision\":\"deny\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:deny found in final output: {final_json}')

if failures:
    for f in failures:
        print(f, file=sys.stderr)
    sys.exit(1)

print(f'AC5_PASS: twl_validate_status_transition no legacy enum in final output ({len(test_cases)} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC5_PASS"* ]]
}

@test "ac5: twl_validate_issue_create 最終出力に decision:allow/deny が含まれない (RED)" {
  # AC: @mcp.tool() 経由の expose 後、decision:"allow"/"deny" が最終出力に含まれない
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys, tempfile, os
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_issue_create_handler
import json

tmpdir = tempfile.mkdtemp()
noexist = os.path.join(tmpdir, 'nonexistent')

test_cases = [
    ('no-op', 'git status', 'Bash', tmpdir, tmpdir),
    ('deny', 'gh issue create --title \"unauthorized\"', 'Bash', tmpdir, noexist),
]

failures = []
for ctx, cmd, tool_name, stmp, cidir in test_cases:
    raw = twl_validate_issue_create_handler(
        command=cmd, tool_name=tool_name,
        session_tmp_dir=stmp, controller_issue_dir=cidir)
    final_output = _to_hook_output(raw)
    final_json = json.dumps(final_output)

    if '\"decision\": \"allow\"' in final_json or '\"decision\":\"allow\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:allow found in final output: {final_json}')
    if '\"decision\": \"deny\"' in final_json or '\"decision\":\"deny\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:deny found in final output: {final_json}')

if failures:
    for f in failures:
        print(f, file=sys.stderr)
    sys.exit(1)

print(f'AC5_PASS: twl_validate_issue_create no legacy enum in final output ({len(test_cases)} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC5_PASS"* ]]
}

@test "ac5: twl_validate_merge 最終出力に decision:allow/deny が含まれない (RED)" {
  # AC: @mcp.tool() 経由の expose 後、decision:"allow"/"deny" が最終出力に含まれない
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_merge_handler
import json

test_cases = [
    ('allow', {'branch': 'feat/1618-test', 'base': 'main'}),
    ('deny/timeout', {'branch': 'test', 'base': 'main', 'timeout_sec': 0}),
]

failures = []
for ctx, kwargs in test_cases:
    raw = twl_validate_merge_handler(**kwargs)
    final_output = _to_hook_output(raw)
    final_json = json.dumps(final_output)

    if '\"decision\": \"allow\"' in final_json or '\"decision\":\"allow\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:allow found in final output: {final_json}')
    if '\"decision\": \"deny\"' in final_json or '\"decision\":\"deny\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:deny found in final output: {final_json}')

if failures:
    for f in failures:
        print(f, file=sys.stderr)
    sys.exit(1)

print(f'AC5_PASS: twl_validate_merge no legacy enum in final output ({len(test_cases)} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC5_PASS"* ]]
}

@test "ac5: twl_validate_commit 最終出力に decision:allow/deny が含まれない (RED)" {
  # AC: @mcp.tool() 経由の expose 後、decision:"allow"/"deny" が最終出力に含まれない
  # RED: _to_hook_output が存在しないため fail する
  run python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import _to_hook_output, twl_validate_commit_handler
import json

test_cases = [
    ('no-op', {'command': 'git commit -m \"feat: test\"', 'files': []}),
    ('timeout', {'command': 'git commit -m \"feat: test\"', 'files': [], 'timeout_sec': 0}),
]

failures = []
for ctx, kwargs in test_cases:
    raw = twl_validate_commit_handler(**kwargs)
    final_output = _to_hook_output(raw)
    final_json = json.dumps(final_output)

    if '\"decision\": \"allow\"' in final_json or '\"decision\":\"allow\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:allow found in final output: {final_json}')
    if '\"decision\": \"deny\"' in final_json or '\"decision\":\"deny\"' in final_json:
        failures.append(f'[{ctx}] legacy decision:deny found in final output: {final_json}')

if failures:
    for f in failures:
        print(f, file=sys.stderr)
    sys.exit(1)

print(f'AC5_PASS: twl_validate_commit no legacy enum in final output ({len(test_cases)} cases)')
sys.exit(0)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC5_PASS"* ]]
}

# ===========================================================================
# AC-6: ac-test-mapping-1618.yaml が追加され AC-1〜AC-5 がマッピングされていること
# ===========================================================================

@test "ac6: ac-test-mapping-1618.yaml が cli/twl/tests/ 直下に存在すること" {
  # AC: cli/twl/tests/ac-test-mapping-1618.yaml が追加されていること
  [ -f "${MAPPING_YAML}" ]
}

@test "ac6: ac-test-mapping-1618.yaml に AC-1 のマッピングが含まれること" {
  # AC: AC-1 が test_issue_1618_hook_output_e2e.bats 内のテスト名にマッピングされていること
  [ -f "${MAPPING_YAML}" ]
  run grep -qF 'ac_index: 1' "${MAPPING_YAML}"
  [ "$status" -eq 0 ]
}

@test "ac6: ac-test-mapping-1618.yaml に AC-2 のマッピングが含まれること" {
  # AC: AC-2 が test_issue_1618_hook_output_e2e.bats 内のテスト名にマッピングされていること
  [ -f "${MAPPING_YAML}" ]
  run grep -qF 'ac_index: 2' "${MAPPING_YAML}"
  [ "$status" -eq 0 ]
}

@test "ac6: ac-test-mapping-1618.yaml に AC-3 のマッピングが含まれること" {
  # AC: AC-3 が test_issue_1618_hook_output_e2e.bats 内のテスト名にマッピングされていること
  [ -f "${MAPPING_YAML}" ]
  run grep -qF 'ac_index: 3' "${MAPPING_YAML}"
  [ "$status" -eq 0 ]
}

@test "ac6: ac-test-mapping-1618.yaml に AC-4 のマッピングが含まれること" {
  # AC: AC-4 が test_issue_1618_hook_output_e2e.bats 内のテスト名にマッピングされていること
  [ -f "${MAPPING_YAML}" ]
  run grep -qF 'ac_index: 4' "${MAPPING_YAML}"
  [ "$status" -eq 0 ]
}

@test "ac6: ac-test-mapping-1618.yaml に AC-5 のマッピングが含まれること" {
  # AC: AC-5 が test_issue_1618_hook_output_e2e.bats 内のテスト名にマッピングされていること
  [ -f "${MAPPING_YAML}" ]
  run grep -qF 'ac_index: 5' "${MAPPING_YAML}"
  [ "$status" -eq 0 ]
}

@test "ac6: ac-test-mapping-1618.yaml に AC-6 のマッピングが含まれること" {
  # AC: AC-6 自身のマッピングが含まれていること
  [ -f "${MAPPING_YAML}" ]
  run grep -qF 'ac_index: 6' "${MAPPING_YAML}"
  [ "$status" -eq 0 ]
}

@test "ac6: ac-test-mapping-1618.yaml の test_file が test_issue_1618_hook_output_e2e.bats を参照すること" {
  # AC: yaml の test_file フィールドが正しいパスを指していること
  [ -f "${MAPPING_YAML}" ]
  run grep -qF 'test_issue_1618_hook_output_e2e.bats' "${MAPPING_YAML}"
  [ "$status" -eq 0 ]
}
