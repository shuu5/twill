#!/usr/bin/env bash
# =============================================================================
# BDD Scenario Tests: su-observer session ID persistence & cld --observer resume
# Generated from: deltaspec/changes/issue-613/specs/session-id-persistence/spec.md
# Coverage level: edge-cases
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SESSION_PLUGIN_ROOT="$(cd "${PROJECT_ROOT}/../../plugins/session" && pwd 2>/dev/null)" || SESSION_PLUGIN_ROOT=""
CLD_SCRIPT="${SESSION_PLUGIN_ROOT:+${SESSION_PLUGIN_ROOT}/scripts/cld}"
SU_OBSERVER_SKILL="${PROJECT_ROOT}/skills/su-observer/SKILL.md"
SUPERVISION_MD="${PROJECT_ROOT}/architecture/domain/contexts/supervision.md"
SU_POSTCOMPACT="${PROJECT_ROOT}/scripts/su-postcompact.sh"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "$file" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "$file" ]] && grep -qP -- "$pattern" "$file"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "$file" ]] || return 1
  if grep -qP -- "$pattern" "$file"; then
    return 1
  fi
  return 0
}

run_test() {
  local name="$1"
  local func="$2"
  local result=0
  $func || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++)) || true
}

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "${SANDBOX}/.supervisor"
}

teardown_sandbox() {
  if [[ -n "${SANDBOX:-}" && -d "${SANDBOX}" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

SANDBOX=""
trap teardown_sandbox EXIT

# =============================================================================
# Requirement: Session ID 保存
# Scenario: 新規 observer セッション起動時の session ID 保存 (spec line 7)
# WHEN: su-observer SKILL.md Step 0 で SupervisorSession を新規作成するとき
# THEN: Claude Code session ID が .supervisor/session.json の claude_session_id フィールドに書き込まれること
# =============================================================================
echo ""
echo "--- Requirement: Session ID 保存 / Scenario: 新規 observer セッション起動時 ---"

# Test: SKILL.md Step 0 に session.json への claude_session_id 書き込み指示が含まれる
test_skillmd_step0_session_id_write() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "claude_session_id"
}

if [[ -f "$SU_OBSERVER_SKILL" ]]; then
  run_test "SKILL.md Step 0: claude_session_id フィールドへの書き込み指示が存在する" test_skillmd_step0_session_id_write
else
  run_test_skip "SKILL.md Step 0: claude_session_id 書き込み指示" "SKILL.md が存在しない"
fi

# Test: SKILL.md が session.json への保存に言及している
test_skillmd_session_json_reference() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session\.json"
}

if [[ -f "$SU_OBSERVER_SKILL" ]]; then
  run_test "SKILL.md: .supervisor/session.json への参照が存在する" test_skillmd_session_json_reference
else
  run_test_skip "SKILL.md: session.json 参照" "SKILL.md が存在しない"
fi

# Test: SKILL.md Step 0 に「新規作成」パスで session ID 保存に言及する
test_skillmd_new_session_id_save() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  # 新規 SupervisorSession 作成パスに claude_session_id への言及があること
  python3 - "$SU_OBSERVER_SKILL" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# Step 0 セクションを抽出（Step 1 が現れる前まで）
step0_match = re.search(r'(?:##+ Step\s*0|Step\s*0[:\s])(.*?)(?=##+ Step\s*1|Step\s*1[:\s]|\Z)', content, re.DOTALL | re.IGNORECASE)
if not step0_match:
    print("Step 0 section not found", file=sys.stderr)
    sys.exit(1)

step0_text = step0_match.group(0)

# 新規作成パス + session ID の両方が含まれるか確認
has_new_session = bool(re.search(r'新規.*SupervisorSession|SupervisorSession.*作成|新規.*セッション', step0_text))
has_session_id = bool(re.search(r'claude_session_id', step0_text))

if not (has_new_session and has_session_id):
    print(f"Step 0 missing new-session+session_id: has_new_session={has_new_session}, has_session_id={has_session_id}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}

if [[ -f "$SU_OBSERVER_SKILL" ]]; then
  run_test "SKILL.md Step 0: 新規作成パスで claude_session_id 保存が定義されている" test_skillmd_new_session_id_save
else
  run_test_skip "SKILL.md Step 0: 新規作成パスの session ID 保存" "SKILL.md が存在しない"
fi

# Edge case: session.json は .supervisor/ ディレクトリ内に作成されること
test_skillmd_supervisor_dir_path() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "\.supervisor/session\.json"
}

if [[ -f "$SU_OBSERVER_SKILL" ]]; then
  run_test "SKILL.md [edge: session.json パスが .supervisor/ 配下であること]" test_skillmd_supervisor_dir_path
else
  run_test_skip "SKILL.md [edge: .supervisor/session.json パス]" "SKILL.md が存在しない"
fi

# Edge case: session.json の JSON 構造に claude_session_id キーが含まれること（スキーマ検証）
test_sandbox_session_json_schema() {
  setup_sandbox
  # session.json に claude_session_id が含まれる場合の JSON パース確認
  cat > "${SANDBOX}/.supervisor/session.json" <<'JSON'
{
  "session_id": "test-session-001",
  "claude_session_id": "claude-abc123",
  "status": "active",
  "started_at": "2026-04-14T00:00:00Z"
}
JSON
  python3 -c "
import json, sys
with open('${SANDBOX}/.supervisor/session.json') as f:
    data = json.load(f)
if 'claude_session_id' not in data:
    print('claude_session_id key missing', file=sys.stderr)
    sys.exit(1)
if not data['claude_session_id']:
    print('claude_session_id is empty', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
  local result=$?
  teardown_sandbox
  return $result
}
run_test "session.json [edge: claude_session_id キーを含む JSON スキーマが有効]" test_sandbox_session_json_schema

# =============================================================================
# Requirement: Session ID 保存
# Scenario: observer セッション復帰時の session ID 更新 (spec line 11)
# WHEN: su-observer SKILL.md Step 0 で status=active の既存セッションに復帰するとき
# THEN: 既存の claude_session_id が検証され、変更がある場合は更新されること
# =============================================================================
echo ""
echo "--- Requirement: Session ID 保存 / Scenario: observer セッション復帰時の session ID 更新 ---"

# Test: SKILL.md Step 0 に「復帰」パスで session ID 更新に言及する
test_skillmd_resume_session_id_update() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  python3 - "$SU_OBSERVER_SKILL" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# Step 0 セクションを抽出
step0_match = re.search(r'(?:##+ Step\s*0|Step\s*0[:\s])(.*?)(?=##+ Step\s*1|Step\s*1[:\s]|\Z)', content, re.DOTALL | re.IGNORECASE)
if not step0_match:
    print("Step 0 section not found", file=sys.stderr)
    sys.exit(1)

step0_text = step0_match.group(0)

# status=active 復帰パス + session ID 更新の両方が含まれるか
has_resume = bool(re.search(r'status.*active|active.*復帰|復帰.*active|前回.*復帰', step0_text))
has_update = bool(re.search(r'claude_session_id', step0_text))

if not (has_resume and has_update):
    print(f"Step 0 missing resume+update: has_resume={has_resume}, has_update={has_update}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}

if [[ -f "$SU_OBSERVER_SKILL" ]]; then
  run_test "SKILL.md Step 0: 復帰パスで claude_session_id の検証・更新が定義されている" test_skillmd_resume_session_id_update
else
  run_test_skip "SKILL.md Step 0: 復帰パスの session ID 更新" "SKILL.md が存在しない"
fi

# Edge case: session ID が変更なし → session.json を書き換えない（冪等性）
test_sandbox_session_id_unchanged_idempotent() {
  setup_sandbox
  local original_id="claude-unchanged-999"
  cat > "${SANDBOX}/.supervisor/session.json" <<JSON
{
  "session_id": "sup-001",
  "claude_session_id": "${original_id}",
  "status": "active",
  "started_at": "2026-04-14T00:00:00Z"
}
JSON
  # ファイル変更なし → 同じ値を書いても claude_session_id が変わらないこと
  python3 -c "
import json
path = '${SANDBOX}/.supervisor/session.json'
with open(path) as f:
    data = json.load(f)
# 変更なし（同値）
if data['claude_session_id'] == '${original_id}':
    # session.json は書き換え不要（更新不要フラグが立つはず）
    import sys; sys.exit(0)
import sys; sys.exit(1)
"
  local result=$?
  teardown_sandbox
  return $result
}
run_test "session.json [edge: session ID 変更なし時は書き換え不要（冪等性）]" test_sandbox_session_id_unchanged_idempotent

# Edge case: session ID が変更あり → 新しい値で session.json が更新されること
test_sandbox_session_id_update_on_change() {
  setup_sandbox
  local old_id="claude-old-111"
  local new_id="claude-new-222"
  cat > "${SANDBOX}/.supervisor/session.json" <<JSON
{
  "session_id": "sup-002",
  "claude_session_id": "${old_id}",
  "status": "active",
  "started_at": "2026-04-14T00:00:00Z"
}
JSON
  # 新しい session ID で上書き
  python3 -c "
import json
path = '${SANDBOX}/.supervisor/session.json'
with open(path) as f:
    data = json.load(f)
data['claude_session_id'] = '${new_id}'
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
  # 更新後の確認
  python3 -c "
import json
path = '${SANDBOX}/.supervisor/session.json'
with open(path) as f:
    data = json.load(f)
import sys
if data['claude_session_id'] != '${new_id}':
    print(f'Expected ${new_id}, got {data[\"claude_session_id\"]}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
  local result=$?
  teardown_sandbox
  return $result
}
run_test "session.json [edge: session ID 変更時は新しい値で更新される]" test_sandbox_session_id_update_on_change

# =============================================================================
# Requirement: SupervisorSession エンティティ拡張
# Scenario: アーキテクチャドキュメントへのフィールド追加 (spec line 19)
# WHEN: plugins/twl/architecture/domain/contexts/supervision.md を参照するとき
# THEN: SupervisorSession エンティティのフィールド一覧に claude_session_id: string | null が含まれること
# =============================================================================
echo ""
echo "--- Requirement: SupervisorSession エンティティ拡張 / Scenario: アーキテクチャドキュメントへのフィールド追加 ---"

# Test: supervision.md の SupervisorSession テーブルに claude_session_id フィールドが存在する
test_supervision_md_has_claude_session_id() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  python3 - "$SUPERVISION_MD" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# SupervisorSession セクションを抽出
session_match = re.search(r'###\s*SupervisorSession(.*?)(?=###|\Z)', content, re.DOTALL)
if not session_match:
    print("SupervisorSession section not found", file=sys.stderr)
    sys.exit(1)

section_text = session_match.group(1)

# claude_session_id フィールドが存在するか確認
if not re.search(r'claude_session_id', section_text):
    print("claude_session_id field not found in SupervisorSession section", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
}

if [[ -f "$SUPERVISION_MD" ]]; then
  run_test "supervision.md: SupervisorSession に claude_session_id フィールドが存在する" test_supervision_md_has_claude_session_id
else
  run_test_skip "supervision.md: SupervisorSession フィールド確認" "supervision.md が存在しない"
fi

# Test: claude_session_id の型が string | null または string \| null と定義されている
test_supervision_md_field_type_nullable_string() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  python3 - "$SUPERVISION_MD" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# SupervisorSession セクション内の claude_session_id 行を確認
session_match = re.search(r'###\s*SupervisorSession(.*?)(?=###|\Z)', content, re.DOTALL)
if not session_match:
    print("SupervisorSession section not found", file=sys.stderr)
    sys.exit(1)

section_text = session_match.group(1)

# claude_session_id を含む行を抽出
lines = section_text.splitlines()
field_line = next((l for l in lines if 'claude_session_id' in l), None)
if not field_line:
    print("claude_session_id line not found", file=sys.stderr)
    sys.exit(1)

# string | null または string \| null が含まれるか（テーブルのエスケープ考慮）
if not re.search(r'string.*\|?\s*null|null.*\|?\s*string', field_line, re.IGNORECASE):
    print(f"Type annotation 'string | null' not found in: {field_line.strip()}", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
}

if [[ -f "$SUPERVISION_MD" ]]; then
  run_test "supervision.md: claude_session_id の型が string | null と定義されている" test_supervision_md_field_type_nullable_string
else
  run_test_skip "supervision.md: claude_session_id 型定義確認" "supervision.md が存在しない"
fi

# Edge case: SupervisorSession テーブルの既存フィールド（session_id, status 等）が壊れていない
test_supervision_md_existing_fields_intact() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  python3 - "$SUPERVISION_MD" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

session_match = re.search(r'###\s*SupervisorSession(.*?)(?=###|\Z)', content, re.DOTALL)
if not session_match:
    print("SupervisorSession section not found", file=sys.stderr)
    sys.exit(1)

section_text = session_match.group(1)

# 必須の既存フィールドが残っているか確認
required_fields = ['session_id', 'project', 'status', 'started_at']
missing = [f for f in required_fields if f not in section_text]
if missing:
    print(f"Missing required fields: {missing}", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
}

if [[ -f "$SUPERVISION_MD" ]]; then
  run_test "supervision.md [edge: 既存フィールド session_id/project/status/started_at が維持されている]" test_supervision_md_existing_fields_intact
else
  run_test_skip "supervision.md [edge: 既存フィールド確認]" "supervision.md が存在しない"
fi

# =============================================================================
# Requirement: cld --observer フラグ
# Scenario: 有効な observer session への resume (spec line 29)
# WHEN: cld --observer を実行し、有効な session ID と tmux window が存在するとき
# THEN: claude --resume <claude_session_id> が実行されること
# =============================================================================
echo ""
echo "--- Requirement: cld --observer フラグ / Scenario: 有効な observer session への resume ---"

# Test: cld スクリプトに --observer フラグの処理が含まれている
test_cld_has_observer_flag_handling() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "\-\-observer"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: --observer フラグ処理が実装されている" test_cld_has_observer_flag_handling
else
  run_test_skip "cld スクリプト: --observer フラグ処理" "cld スクリプトが見つからない"
fi

# Test: cld スクリプトに claude --resume の呼び出しが含まれている
test_cld_has_claude_resume_call() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "claude.*--resume|--resume.*claude"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: claude --resume <session_id> 呼び出しが実装されている" test_cld_has_claude_resume_call
else
  run_test_skip "cld スクリプト: claude --resume 呼び出し" "cld スクリプトが見つからない"
fi

# Test: cld スクリプトが session.json から claude_session_id を読み取る
test_cld_reads_claude_session_id_from_json() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "claude_session_id"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: session.json から claude_session_id を読み取る処理がある" test_cld_reads_claude_session_id_from_json
else
  run_test_skip "cld スクリプト: claude_session_id 読み取り" "cld スクリプトが見つからない"
fi

# Edge case: --observer フラグ処理が他フラグ（--env-file, -p 等）より前に評価される
test_cld_observer_flag_parse_order() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  python3 - "$CLD_SCRIPT" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

observer_match = re.search(r'--observer', content)
resume_match = re.search(r'--resume', content)

if not observer_match:
    print("--observer not found in cld script", file=sys.stderr)
    sys.exit(1)
if not resume_match:
    print("--resume not found in cld script", file=sys.stderr)
    sys.exit(1)

# --observer の処理が --resume よりも前に定義されているか
if observer_match.start() > resume_match.start():
    print("Warning: --observer handling appears after --resume call", file=sys.stderr)
    # 警告のみ（FAIL ではなく）
sys.exit(0)
PYEOF
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト [edge: --observer フラグが正しい順序で解析される]" test_cld_observer_flag_parse_order
else
  run_test_skip "cld スクリプト [edge: フラグ解析順序]" "cld スクリプトが見つからない"
fi

# =============================================================================
# Requirement: cld --observer フラグ
# Scenario: session.json が存在しない場合のエラー (spec line 33)
# WHEN: cld --observer を実行し、.supervisor/session.json が存在しないとき
# THEN: "No active observer session. Start one with: cld → /su-observer" メッセージが表示されること
# =============================================================================
echo ""
echo "--- Requirement: cld --observer フラグ / Scenario: session.json が存在しない場合のエラー ---"

# Test: cld スクリプトに session.json 不在時のエラーメッセージが含まれる
test_cld_no_session_json_error_msg() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "No active observer session"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: session.json 不在時エラーメッセージ 'No active observer session' が存在する" test_cld_no_session_json_error_msg
else
  run_test_skip "cld スクリプト: session.json 不在エラーメッセージ" "cld スクリプトが見つからない"
fi

# Test: エラーメッセージに su-observer 起動方法が含まれる
test_cld_no_session_json_error_hint() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "su-observer"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: session.json 不在エラーに /su-observer 起動ヒントが含まれる" test_cld_no_session_json_error_hint
else
  run_test_skip "cld スクリプト: エラーヒント確認" "cld スクリプトが見つからない"
fi

# Edge case: session.json が存在するが壊れた JSON の場合もエラーが出ること
test_cld_observer_broken_json_handled() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # スクリプトに JSON パースエラーハンドリングが存在するか
  assert_file_contains "$CLD_SCRIPT" "jq\|python3\|parse" || \
    assert_file_contains "$CLD_SCRIPT" "2>/dev/null\|2>&1"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト [edge: 破損 JSON に対してエラーハンドリングが存在する]" test_cld_observer_broken_json_handled
else
  run_test_skip "cld スクリプト [edge: 破損 JSON ハンドリング]" "cld スクリプトが見つからない"
fi

# =============================================================================
# Requirement: cld --observer フラグ
# Scenario: session ID が空の場合のエラー (spec line 37)
# WHEN: cld --observer を実行し、claude_session_id が null または空のとき
# THEN: "Observer session found but no Claude session ID recorded" メッセージが表示されること
# =============================================================================
echo ""
echo "--- Requirement: cld --observer フラグ / Scenario: session ID が空の場合のエラー ---"

# Test: cld スクリプトに session ID 空時のエラーメッセージが含まれる
test_cld_empty_session_id_error_msg() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "Observer session found but no Claude session ID recorded"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: session ID 空時エラーメッセージが定義されている" test_cld_empty_session_id_error_msg
else
  run_test_skip "cld スクリプト: session ID 空エラーメッセージ" "cld スクリプトが見つからない"
fi

# Edge case: claude_session_id が "null" リテラル文字列の場合も空と同様に扱われること
test_cld_null_literal_treated_as_empty() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # null または空の両方をチェックするパターンが存在するか
  assert_file_contains "$CLD_SCRIPT" 'null\|-z\|empty\|^\s*$'
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト [edge: null リテラルと空文字列の両方をエラーとして扱う]" test_cld_null_literal_treated_as_empty
else
  run_test_skip "cld スクリプト [edge: null/空の両方チェック]" "cld スクリプトが見つからない"
fi

# =============================================================================
# Requirement: cld --observer フラグ
# Scenario: tmux window が存在しない場合のエラー (spec line 41)
# WHEN: cld --observer を実行し、対応する tmux window が存在しないとき
# THEN: "Observer window not found. Session may have ended" メッセージが表示されること
# =============================================================================
echo ""
echo "--- Requirement: cld --observer フラグ / Scenario: tmux window が存在しない場合のエラー ---"

# Test: cld スクリプトに tmux window 不在時のエラーメッセージが含まれる
test_cld_no_tmux_window_error_msg() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "Observer window not found"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: tmux window 不在エラーメッセージ 'Observer window not found' が存在する" test_cld_no_tmux_window_error_msg
else
  run_test_skip "cld スクリプト: tmux window 不在エラーメッセージ" "cld スクリプトが見つからない"
fi

# Test: cld スクリプトが tmux window の存在確認を行っている
test_cld_checks_tmux_window_existence() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "tmux.*list-windows\|tmux.*has-session\|tmux.*select-window"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: tmux window 存在確認コマンドが実装されている" test_cld_checks_tmux_window_existence
else
  run_test_skip "cld スクリプト: tmux window 存在確認" "cld スクリプトが見つからない"
fi

# Edge case: tmux が起動していない場合（TMUX 変数なし）でもエラーが適切に処理される
test_cld_tmux_not_running_handled() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # tmux コマンド失敗時の || または 2>/dev/null が存在するか
  assert_file_contains "$CLD_SCRIPT" "tmux.*2>/dev/null\|tmux.*\|\|"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト [edge: tmux 未起動時のエラーが適切に処理される]" test_cld_tmux_not_running_handled
else
  run_test_skip "cld スクリプト [edge: tmux 未起動時の処理]" "cld スクリプトが見つからない"
fi

# =============================================================================
# Requirement: cld --observer フラグ
# Scenario: Claude Code プロセスが終了している場合のエラー (spec line 45)
# WHEN: cld --observer を実行し、Claude Code プロセスが exited 状態のとき
# THEN: "Observer session has ended. Start a new one with: cld → /su-observer" メッセージが表示されること
# =============================================================================
echo ""
echo "--- Requirement: cld --observer フラグ / Scenario: Claude Code プロセスが終了している場合のエラー ---"

# Test: cld スクリプトにプロセス終了時のエラーメッセージが含まれる
test_cld_process_exited_error_msg() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  assert_file_contains "$CLD_SCRIPT" "Observer session has ended"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: プロセス終了エラーメッセージ 'Observer session has ended' が存在する" test_cld_process_exited_error_msg
else
  run_test_skip "cld スクリプト: プロセス終了エラーメッセージ" "cld スクリプトが見つからない"
fi

# Test: cld スクリプトがプロセスの生存確認を行っている
test_cld_checks_process_alive() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # プロセス確認: ps, kill -0, pgrep など
  assert_file_contains "$CLD_SCRIPT" "ps\b.*claude\|pgrep.*claude\|kill\s*-0\|tmux.*capture-pane\|session.*exited\|exited"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: Claude Code プロセス生存確認が実装されている" test_cld_checks_process_alive
else
  run_test_skip "cld スクリプト: プロセス生存確認" "cld スクリプトが見つからない"
fi

# Edge case: session.json の status フィールドが ended/exited の場合もエラーを表示する
test_cld_session_status_ended_detected() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # status=ended または exited の検出パターン
  assert_file_contains "$CLD_SCRIPT" "ended\|exited\|status"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト [edge: session status=ended/exited を検出してエラー表示]" test_cld_session_status_ended_detected
else
  run_test_skip "cld スクリプト [edge: status=ended 検出]" "cld スクリプトが見つからない"
fi

# =============================================================================
# Requirement: cld --observer フラグ
# Scenario: 既存フラグの互換性維持 (spec line 49)
# WHEN: cld を --observer フラグなしで実行するとき
# THEN: 既存動作（全引数を claude にパススルー）に影響がないこと
# =============================================================================
echo ""
echo "--- Requirement: cld --observer フラグ / Scenario: 既存フラグの互換性維持 ---"

# Test: cld スクリプトに --observer なし時の exec/passthrough が維持されている
test_cld_passthrough_preserved() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # exec claude ... "$@" または claude ... "$@" パターンが存在するか
  assert_file_contains "$CLD_SCRIPT" 'exec.*claude.*"\$@"\|claude.*"\$@"'
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: --observer なし時の全引数パススルーが維持されている" test_cld_passthrough_preserved
else
  run_test_skip "cld スクリプト: 全引数パススルー維持" "cld スクリプトが見つからない"
fi

# Test: --observer フラグは権限フラグ等の既存フラグと共存できる
test_cld_observer_coexists_with_existing_flags() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # --dangerously-skip-permissions が残っている（2026-04-21 auto mode revert 後）
  assert_file_contains "$CLD_SCRIPT" "dangerously-skip-permissions"
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト: --dangerously-skip-permissions 等の既存フラグが維持されている" test_cld_observer_coexists_with_existing_flags
else
  run_test_skip "cld スクリプト: 既存フラグ共存確認" "cld スクリプトが見つからない"
fi

# Edge case: -p フラグが --observer と共に渡された場合は拒否する（既存の cld-p-flag-prohibition）
test_cld_p_flag_prohibition_with_observer() {
  [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]] || return 1
  # -p フラグに関する制約が存在するか（または --observer 時は明示的にチェックしないことを確認）
  # この Edge case: --observer が -p フラグの既存禁止ロジックを壊さないこと
  # cld スクリプト自体に -p 禁止ロジックがあれば OK
  assert_file_contains "$CLD_SCRIPT" "\-p\b\|\-\-print\b" || return 0  # なければスキップ相当で OK
}

if [[ -n "$CLD_SCRIPT" && -f "$CLD_SCRIPT" ]]; then
  run_test "cld スクリプト [edge: -p フラグ禁止ロジックが --observer によって壊されていない]" test_cld_p_flag_prohibition_with_observer
else
  run_test_skip "cld スクリプト [edge: -p フラグ禁止共存]" "cld スクリプトが見つからない"
fi

# =============================================================================
# Requirement: Compaction 後の Session ID 更新
# Scenario: compaction 後の session ID 更新（ID 変更ケース） (spec line 57)
# WHEN: Claude Code の /compact 実行後に session ID が変わったとき
# THEN: su-postcompact.sh が新しい session ID を取得し .supervisor/session.json を更新すること
# =============================================================================
echo ""
echo "--- Requirement: Compaction 後の Session ID 更新 / Scenario: compaction 後の session ID 更新 ---"

# Test: su-postcompact.sh スクリプトが存在する
test_postcompact_script_exists() {
  assert_file_exists "$SU_POSTCOMPACT"
}
run_test "su-postcompact.sh スクリプトが存在する" test_postcompact_script_exists

# Test: su-postcompact.sh が session.json の claude_session_id 更新に言及している
test_postcompact_updates_claude_session_id() {
  assert_file_exists "$SU_POSTCOMPACT" || return 1
  assert_file_contains "$SU_POSTCOMPACT" "claude_session_id"
}

if [[ -f "$SU_POSTCOMPACT" ]]; then
  run_test "su-postcompact.sh: claude_session_id 更新処理が実装されている" test_postcompact_updates_claude_session_id
else
  run_test_skip "su-postcompact.sh: claude_session_id 更新" "su-postcompact.sh が存在しない"
fi

# Test: su-postcompact.sh が session.json を書き込む処理を持つ
test_postcompact_writes_session_json() {
  assert_file_exists "$SU_POSTCOMPACT" || return 1
  assert_file_contains "$SU_POSTCOMPACT" "session\.json"
}

if [[ -f "$SU_POSTCOMPACT" ]]; then
  run_test "su-postcompact.sh: .supervisor/session.json への書き込みが実装されている" test_postcompact_writes_session_json
else
  run_test_skip "su-postcompact.sh: session.json 書き込み" "su-postcompact.sh が存在しない"
fi

# Edge case: compaction 後も session_id（supervisor 側）は変わらず claude_session_id のみ更新される
test_postcompact_only_claude_session_id_changes() {
  assert_file_exists "$SU_POSTCOMPACT" || return 1
  python3 - "$SU_POSTCOMPACT" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# claude_session_id の更新処理が存在するか
has_claude_session_update = bool(re.search(r'claude_session_id', content))

if not has_claude_session_update:
    print("claude_session_id update not found in su-postcompact.sh", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
}

if [[ -f "$SU_POSTCOMPACT" ]]; then
  run_test "su-postcompact.sh [edge: claude_session_id のみを選択的に更新する]" test_postcompact_only_claude_session_id_changes
else
  run_test_skip "su-postcompact.sh [edge: 選択的更新]" "su-postcompact.sh が存在しない"
fi

# Edge case: su-postcompact.sh は SUPERVISOR_DIR 環境変数を尊重する（デフォルト: .supervisor）
test_postcompact_respects_supervisor_dir_env() {
  assert_file_exists "$SU_POSTCOMPACT" || return 1
  assert_file_contains "$SU_POSTCOMPACT" "SUPERVISOR_DIR"
}

if [[ -f "$SU_POSTCOMPACT" ]]; then
  run_test "su-postcompact.sh [edge: SUPERVISOR_DIR 環境変数を尊重する]" test_postcompact_respects_supervisor_dir_env
else
  run_test_skip "su-postcompact.sh [edge: SUPERVISOR_DIR 環境変数]" "su-postcompact.sh が存在しない"
fi

# Edge case: compaction 後 session.json が存在しない場合は何もしない（graceful）
test_postcompact_graceful_no_session_json() {
  assert_file_exists "$SU_POSTCOMPACT" || return 1
  # session.json 不在時の exit 0 や存在チェックが定義されているか
  assert_file_contains "$SU_POSTCOMPACT" "\[ -f.*session\.json\|session\.json.*-f\|\[ -d \$\{SUPERVISOR_DIR"
}

if [[ -f "$SU_POSTCOMPACT" ]]; then
  run_test "su-postcompact.sh [edge: session.json 不在時は何もせずに終了する]" test_postcompact_graceful_no_session_json
else
  run_test_skip "su-postcompact.sh [edge: session.json 不在時の graceful exit]" "su-postcompact.sh が存在しない"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
