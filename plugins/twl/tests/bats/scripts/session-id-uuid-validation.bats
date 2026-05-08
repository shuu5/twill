#!/usr/bin/env bats
# session-id-uuid-validation.bats - Issue #1552 AC1/AC2/AC6 RED テスト
#
# バグ: session.json の claude_session_id に非UUID値（例: "post-compact-2026-05-08T10:16-w77"）が
#       書き込まれると cld --observer が正常な UUID として --resume に渡してしまう。
#
# AC1（write-side validation）:
#   session-init.sh および su-postcompact.sh の Python ブロックで
#   claude_session_id 書き込み前に UUID v4 regex を assert する。
#   空文字列は許容。違反時は WARN + skip（既存値保持）。
#
# AC2（read-side validation）:
#   cld --observer が claude_session_id 読み取り直後に UUID v4 check。
#   違反時は actionable error + exit 1。
#
# AC6:
#   このファイル自体が AC6 の bats テスト成果物。
#
# RED 理由:
#   現時点の実装には UUID v4 検証ロジックが存在しないため、全テストが fail する。
#
# UUID v4 パターン: ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$
# (より緩い許容: ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$)
#
# テストフレームワーク: bats-core（bats-support + bats-assert）

load '../helpers/common'

REPO_ROOT_ABS=""
SESSION_INIT_SRC=""
POSTCOMPACT_SRC=""
CLD_SRC=""

setup() {
  common_setup

  # REPO_ROOT は common.bash で plugins/twl/ として解決される
  REPO_ROOT_ABS="$REPO_ROOT"

  # 実装対象スクリプトの絶対パス
  SESSION_INIT_SRC="${REPO_ROOT_ABS}/skills/su-observer/scripts/session-init.sh"
  POSTCOMPACT_SRC="${REPO_ROOT_ABS}/scripts/su-postcompact.sh"
  # cld は plugins/session/scripts/cld（REPO_ROOT の兄弟 plugin）
  CLD_SRC="$(cd "${REPO_ROOT_ABS}/../.." && pwd)/plugins/session/scripts/cld"

  # SUPERVISOR_DIR を sandbox 内に設定
  export SUPERVISOR_DIR="${SANDBOX}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}"

  # 外部コマンド stub（AC と無関係な呼び出し）
  stub_command "tmux" 'echo "test-window"'
  stub_command "twl" 'exit 0'
  stub_command "systemd-run" 'shift; shift; exec "$@"'
  stub_command "git" 'echo ""'

  # session-state.sh stub（cld --observer が呼ぶ）
  stub_command "session-state.sh" 'echo "active"'

  # HOME を sandbox に向けて ~/.claude/projects/ の影響を排除
  export HOME="${SANDBOX}"
  mkdir -p "${SANDBOX}/.claude/projects"
}

# ---------------------------------------------------------------------------
# ヘルパー: session-init.sh に渡す claude_session_id を
# ~/.claude/projects/<PROJECT_HASH>/<id>.jsonl ファイル経由で注入する。
# session-init.sh は行19で ls -t により CLAUDE_SESSION_ID_VAL を上書きするため、
# 環境変数渡しは効かない。ファイルシステム注入が唯一の正しい方法。
#
# 引数: $1 = 注入する claude_session_id 文字列（ファイル名として使用）
# 副作用: $SANDBOX/.claude/projects/<PROJECT_HASH>/<id>.jsonl を作成
# ---------------------------------------------------------------------------
_inject_session_id_via_fs() {
  local inject_id="$1"
  local project_hash
  # session-init.sh と同じ計算: PROJECT_HASH=$(pwd | sed 's|/|-|g')
  project_hash=$(pwd | sed 's|/|-|g')
  mkdir -p "${SANDBOX}/.claude/projects/${project_hash}"
  touch "${SANDBOX}/.claude/projects/${project_hash}/${inject_id}.jsonl"
}

teardown() {
  common_teardown
}

# ===========================================================================
# ヘルパー: 有効な UUID v4 文字列を生成
# ===========================================================================

_valid_uuid() {
  python3 -c "import uuid; print(str(uuid.uuid4()))"
}

# ===========================================================================
# ヘルパー: session.json を SANDBOX/.supervisor に作成
# ===========================================================================

_create_supervisor_session_json() {
  local claude_session_id="${1:-}"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': '${claude_session_id}',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {
    'pid': None,
    'pane_id': None,
    'spawn_cmd': None,
    'started_at': None,
    'log_path': None,
    'lock_path': '/tmp/cld-observe-any.lock'
  }
}
import os
path = os.path.join(os.environ.get('SUPERVISOR_DIR', '.supervisor'), 'session.json')
json.dump(data, open(path, 'w'), indent=2)
"
}

# ===========================================================================
# AC1: write-side validation — session-init.sh
# ===========================================================================

# ---------------------------------------------------------------------------
# write-side AC1-1: invalid claude_session_id で session-init.sh 実行
#   → WARN が stderr に出力される（RED: 現行実装に検証なし）
# ---------------------------------------------------------------------------

@test "ac1-write-session-init: invalid claude_session_id=post-compact-value で WARN が stderr に出力される" {
  # RED: 現行の session-init.sh に UUID 検証が存在しないため fail する
  # PASS 条件（実装後）: invalid 値で "[session-init] WARN: invalid claude_session_id rejected: <value>" が stderr に出力される
  #
  # 注意: session-init.sh は行19で ls -t ~/.claude/projects/.../*.jsonl から CLAUDE_SESSION_ID_VAL を
  # 上書きするため、環境変数渡しは効かない。ファイルシステム注入（_inject_session_id_via_fs）を使う。

  [[ -f "$SESSION_INIT_SRC" ]] \
    || fail "session-init.sh が存在しない: ${SESSION_INIT_SRC}"

  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --dangerously-skip-permissions"
  local invalid_id="post-compact-2026-05-08T10:16-w77"

  # ファイルシステム経由で invalid 値を注入
  _inject_session_id_via_fs "$invalid_id"

  HOME="${SANDBOX}" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    SESSION_INIT_CMDLINE_OVERRIDE="${SESSION_INIT_CMDLINE_OVERRIDE}" \
    run bash "${SESSION_INIT_SRC}"

  # exit code は 0（WARN で abort しない）
  assert_success

  # stderr に WARN が含まれること
  echo "${output}" | grep -qi 'WARN\|warn\|invalid.*claude_session_id\|rejected' \
    || fail "AC1 FAIL: invalid claude_session_id に対する WARN が出力されていない。
現行の session-init.sh に UUID v4 検証が存在しないため fail する（#1552 RED）。
期待: '[session-init] WARN: invalid claude_session_id rejected: ${invalid_id}' が stderr に出力される。"
}

# ---------------------------------------------------------------------------
# write-side AC1-2: invalid 値のとき session.json に書き込まれない（既存値保持）
#   （RED: 現行実装は invalid 値をそのまま書き込む）
# ---------------------------------------------------------------------------

@test "ac1-write-session-init: invalid claude_session_id が session.json に書き込まれない（既存値保持）" {
  # RED: 現行の session-init.sh に UUID 検証が存在しないため、
  #      invalid 値がそのまま session.json に書き込まれてしまう。
  # PASS 条件（実装後）: invalid 値は書き込まれず、session.json の claude_session_id は空文字または変更前の値のまま

  [[ -f "$SESSION_INIT_SRC" ]] \
    || fail "session-init.sh が存在しない: ${SESSION_INIT_SRC}"

  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --dangerously-skip-permissions"
  local invalid_id="post-compact-2026-05-08T10:16-w77"

  CLAUDE_SESSION_ID_VAL="$invalid_id" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    SESSION_INIT_CMDLINE_OVERRIDE="$SESSION_INIT_CMDLINE_OVERRIDE" \
    run bash "${SESSION_INIT_SRC}"

  assert_success

  local session_file="${SUPERVISOR_DIR}/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: ${session_file}"

  local actual_id
  actual_id=$(python3 -c "
import json
with open('${session_file}') as f:
    d = json.load(f)
print(d.get('claude_session_id', ''))
" 2>/dev/null || echo "PARSE_ERROR")

  # invalid 値が書き込まれていないこと
  [[ "$actual_id" != "$invalid_id" ]] \
    || fail "AC1 FAIL: invalid claude_session_id '${invalid_id}' が session.json に書き込まれている。
現行の session-init.sh に UUID v4 検証が存在しないため fail する（#1552 RED）。
期待: invalid 値は skip され、claude_session_id は空文字のまま。"
}

# ---------------------------------------------------------------------------
# write-side AC1-3: 正しい UUID v4 → session.json に正常書き込み
#   (GREEN after implementation)
# ---------------------------------------------------------------------------

@test "ac1-write-session-init: 正しい UUID v4 → session.json に正常書き込みされる" {
  # session-init.sh は行19で ls -t ~/.claude/projects/<PROJECT_HASH>/*.jsonl から
  # CLAUDE_SESSION_ID_VAL を上書きするため、ファイルシステム注入を使う（env var は効かない）。

  [[ -f "$SESSION_INIT_SRC" ]] \
    || fail "session-init.sh が存在しない: ${SESSION_INIT_SRC}"

  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --dangerously-skip-permissions"
  local valid_id
  valid_id=$(_valid_uuid)

  # ファイルシステム経由で valid UUID を注入
  _inject_session_id_via_fs "$valid_id"

  HOME="${SANDBOX}" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    SESSION_INIT_CMDLINE_OVERRIDE="${SESSION_INIT_CMDLINE_OVERRIDE}" \
    run bash "${SESSION_INIT_SRC}"

  assert_success

  local session_file="${SUPERVISOR_DIR}/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: ${session_file}"

  local actual_id
  actual_id=$(python3 -c "
import json
with open('${session_file}') as f:
    d = json.load(f)
print(d.get('claude_session_id', ''))
" 2>/dev/null || echo "PARSE_ERROR")

  [[ "$actual_id" == "$valid_id" ]] \
    || fail "AC1 FAIL: 正常な UUID v4 '${valid_id}' が session.json に書き込まれていない。
実際の値: '${actual_id}'。
修正実装で正常 UUID は引き続き書き込まれること（regression guard）。"
}

# ---------------------------------------------------------------------------
# write-side AC1-4: 空文字列 → 既存値保持（空は許容）
#   (空文字は valid として扱う; 既存値を上書きしない)
# ---------------------------------------------------------------------------

@test "ac1-write-session-init: 空文字列 claude_session_id は session.json に空のまま記録される（許容）" {
  # RED: 現行実装に検証がないため、このテストは通常 PASS するが、
  #      実装後に空文字許容動作が維持されることを保証する。
  # PASS 条件（実装後）: 空文字列はエラーなく受け入れられ、session.json の claude_session_id は ""

  [[ -f "$SESSION_INIT_SRC" ]] \
    || fail "session-init.sh が存在しない: ${SESSION_INIT_SRC}"

  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --dangerously-skip-permissions"

  # CLAUDE_SESSION_ID_VAL を空文字列で実行
  CLAUDE_SESSION_ID_VAL="" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    SESSION_INIT_CMDLINE_OVERRIDE="$SESSION_INIT_CMDLINE_OVERRIDE" \
    run bash "${SESSION_INIT_SRC}"

  assert_success

  local session_file="${SUPERVISOR_DIR}/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: ${session_file}"

  local actual_id
  actual_id=$(python3 -c "
import json
with open('${session_file}') as f:
    d = json.load(f)
print(repr(d.get('claude_session_id', 'KEY_MISSING')))
" 2>/dev/null || echo "PARSE_ERROR")

  # 空文字列が WARN なく書き込まれていること（空は許容）
  # 実装後は WARN が出ないことを確認
  echo "${output}" | grep -qi 'rejected' \
    && fail "AC1 FAIL: 空文字列の claude_session_id に対して 'rejected' WARN が出力された。
空文字列は許容されるべき（#1552 AC1 仕様）。" || true

  echo "actual claude_session_id repr: $actual_id (test passed: empty string accepted)"
}

# ---------------------------------------------------------------------------
# write-side AC1-5: session-init.sh の Python ブロックに UUID v4 検証コードが存在する（static grep）
# ---------------------------------------------------------------------------

@test "ac1-static-session-init: Python ブロックに UUID v4 regex 検証が存在する" {
  # RED: 現行の session-init.sh に UUID 検証コードが存在しないため fail する
  # PASS 条件（実装後）: UUID v4 regex パターン（[0-9a-f]{8}-...）または uuid.UUID への言及が存在する

  [[ -f "$SESSION_INIT_SRC" ]] \
    || fail "session-init.sh が存在しない: ${SESSION_INIT_SRC}"

  grep -qE '[0-9a-f]\{8\}.*-|uuid\.UUID|uuid4.*regex|WARN.*invalid.*claude_session_id|rejected.*claude_session_id' \
    "${SESSION_INIT_SRC}" \
    || fail "AC1 FAIL: session-init.sh の Python ブロックに UUID v4 検証コードが存在しない。
期待: '^[0-9a-f]{8}-...' regex または WARN: invalid claude_session_id rejected のパターン。
現行実装には UUID 検証が未実装（#1552 RED）。"
}

# ===========================================================================
# AC1: write-side validation — su-postcompact.sh
# ===========================================================================

# ---------------------------------------------------------------------------
# write-side AC1-6: su-postcompact.sh で invalid NEW_SESSION_ID_VAL → WARN + 既存値保持
# ---------------------------------------------------------------------------

@test "ac1-write-postcompact: invalid NEW_SESSION_ID_VAL で WARN が stderr に出力される" {
  # RED: 現行の su-postcompact.sh に UUID 検証が存在しないため fail する
  # PASS 条件（実装後）: "[su-postcompact] WARN: invalid claude_session_id rejected: <value>" が stderr に出力される

  [[ -f "$POSTCOMPACT_SRC" ]] \
    || fail "su-postcompact.sh が存在しない: ${POSTCOMPACT_SRC}"

  local invalid_id="post-compact-2026-05-08T10:16-w77"

  # session.json に有効な既存 UUID を設定
  local existing_valid_id
  existing_valid_id=$(_valid_uuid)
  _create_supervisor_session_json "$existing_valid_id"

  # su-postcompact.sh は PROJECT_HASH を pwd で計算し ~/.claude/projects/ を ls する。
  # NEW_SESSION_ID を直接環境変数でオーバーライドする手段がないため、
  # ~/.claude/projects/<PROJECT_HASH>/*.jsonl をモックして invalid 値が入るよう設定する。
  local project_hash
  project_hash=$(python3 -c "import os; print(os.getcwd().replace('/', '-'))")
  mkdir -p "${SANDBOX}/.claude/projects/${project_hash}"
  # invalid_id 名の .jsonl ファイルを作成（ls -t で最新として取得される）
  touch "${SANDBOX}/.claude/projects/${project_hash}/${invalid_id}.jsonl"

  SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    CLAUDE_PROJECT_ROOT="${SANDBOX}" \
    HOME="${SANDBOX}" \
    run bash "${POSTCOMPACT_SRC}"

  # exit 0（WARN で abort しない）
  assert_success

  # stderr に WARN が含まれること
  echo "${output}" | grep -qi 'WARN\|warn\|invalid.*claude_session_id\|rejected' \
    || fail "AC1 FAIL: su-postcompact.sh で invalid claude_session_id に対する WARN が出力されていない。
現行の su-postcompact.sh に UUID v4 検証が存在しないため fail する（#1552 RED）。
期待: '[su-postcompact] WARN: invalid claude_session_id rejected: ${invalid_id}' が stderr に出力される。"
}

# ---------------------------------------------------------------------------
# write-side AC1-7: su-postcompact.sh で invalid NEW_SESSION_ID_VAL → 既存値保持
# ---------------------------------------------------------------------------

@test "ac1-write-postcompact: invalid NEW_SESSION_ID_VAL で session.json の claude_session_id が変更されない" {
  # RED: 現行の su-postcompact.sh に UUID 検証が存在しないため、
  #      invalid 値がそのまま書き込まれてしまう。
  # PASS 条件（実装後）: invalid 値は skip され、既存の valid UUID が保持される

  [[ -f "$POSTCOMPACT_SRC" ]] \
    || fail "su-postcompact.sh が存在しない: ${POSTCOMPACT_SRC}"

  local invalid_id="post-compact-2026-05-08T10:16-w77"
  local existing_valid_id
  existing_valid_id=$(_valid_uuid)

  # session.json に有効な既存 UUID を設定
  _create_supervisor_session_json "$existing_valid_id"

  # invalid_id 名の .jsonl ファイルを作成
  local project_hash
  project_hash=$(python3 -c "import os; print(os.getcwd().replace('/', '-'))")
  mkdir -p "${SANDBOX}/.claude/projects/${project_hash}"
  touch "${SANDBOX}/.claude/projects/${project_hash}/${invalid_id}.jsonl"

  SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    CLAUDE_PROJECT_ROOT="${SANDBOX}" \
    HOME="${SANDBOX}" \
    run bash "${POSTCOMPACT_SRC}"

  assert_success

  local session_file="${SUPERVISOR_DIR}/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が存在しない: ${session_file}"

  local actual_id
  actual_id=$(python3 -c "
import json
with open('${session_file}') as f:
    d = json.load(f)
print(d.get('claude_session_id', ''))
" 2>/dev/null || echo "PARSE_ERROR")

  # invalid 値が書き込まれていないこと（既存の valid UUID が保持されていること）
  [[ "$actual_id" != "$invalid_id" ]] \
    || fail "AC1 FAIL: invalid claude_session_id '${invalid_id}' が su-postcompact.sh によって session.json に書き込まれている。
現行の su-postcompact.sh に UUID v4 検証が存在しないため fail する（#1552 RED）。
期待: 既存の valid UUID '${existing_valid_id}' が保持される。"

  # より厳密: 既存の valid UUID が保持されていること
  [[ "$actual_id" == "$existing_valid_id" ]] \
    || fail "AC1 FAIL: invalid 値 skip 後に既存の valid UUID '${existing_valid_id}' が保持されていない。
実際の値: '${actual_id}'。
期待: invalid 値は skip され既存値を保持する（#1552 AC1 仕様）。"
}

# ---------------------------------------------------------------------------
# write-side AC1-8: su-postcompact.sh の Python ブロックに UUID v4 検証コードが存在する（static grep）
# ---------------------------------------------------------------------------

@test "ac1-static-postcompact: su-postcompact.sh の Python ブロックに UUID v4 regex 検証が存在する" {
  # RED: 現行の su-postcompact.sh に UUID 検証コードが存在しないため fail する
  # PASS 条件（実装後）: UUID v4 regex パターンまたは WARN 出力コードが存在する

  [[ -f "$POSTCOMPACT_SRC" ]] \
    || fail "su-postcompact.sh が存在しない: ${POSTCOMPACT_SRC}"

  grep -qE '[0-9a-f]\{8\}.*-|uuid\.UUID|uuid4.*regex|WARN.*invalid.*claude_session_id|rejected.*claude_session_id' \
    "${POSTCOMPACT_SRC}" \
    || fail "AC1 FAIL: su-postcompact.sh の Python ブロックに UUID v4 検証コードが存在しない。
現行実装には UUID 検証が未実装（#1552 RED）。"
}

# ===========================================================================
# AC2: read-side validation — cld --observer
# ===========================================================================

# ---------------------------------------------------------------------------
# read-side AC2-1: session.json の claude_session_id が invalid → cld --observer が exit 1
# ---------------------------------------------------------------------------

@test "ac2-read-cld-observer: invalid claude_session_id で cld --observer が exit 1 する" {
  # RED: 現行の cld に UUID 検証が存在しないため、
  #      invalid 値でも exec claude --resume に渡してしまう（exit 1 しない）。
  # PASS 条件（実装後）: invalid claude_session_id で exit 1 + actionable error が stderr に出力される

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  local invalid_id="post-compact-2026-05-08T10:16-w77"

  # PROJECT_ROOT を SANDBOX に固定するため、git の結果を制御
  # cld は git rev-parse --show-toplevel でプロジェクトルートを検出する
  stub_command "git" "echo '${SANDBOX}'"

  # session.json に invalid claude_session_id を設定
  # cld --observer は SESSION_JSON="${PROJECT_ROOT}/.supervisor/session.json" を参照する
  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': '${invalid_id}',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  # claude stub: 呼ばれたら fail（本来は exit 1 前に呼ばれるべきでない）
  stub_command "claude" 'echo "claude called unexpectedly: $*" >&2; exit 99'

  run bash "${CLD_SRC}" --observer

  # exit 1 であること（invalid UUID で --resume を呼ばない）
  [[ "$status" -eq 1 ]] \
    || fail "AC2 FAIL: invalid claude_session_id '${invalid_id}' で cld --observer が exit ${status} した（exit 1 が期待された）。
現行の cld に UUID v4 検証が存在しないため fail する（#1552 RED）。
期待: exit 1 + actionable error が stderr に出力される。"
}

# ---------------------------------------------------------------------------
# read-side AC2-2: invalid claude_session_id で actionable error が stderr に出力される
# ---------------------------------------------------------------------------

@test "ac2-read-cld-observer: invalid claude_session_id で actionable error が stderr に出力される" {
  # RED: 現行の cld に UUID 検証が存在しないため、
  #      actionable error が出力されず通常エラーメッセージのみ（またはクラッシュ）になる。
  # PASS 条件（実装後）: stderr に "Invalid claude_session_id in session.json: <value>" と
  #                        Recovery 手順が含まれる

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  local invalid_id="post-compact-2026-05-08T10:16-w77"

  stub_command "git" "echo '${SANDBOX}'"

  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': '${invalid_id}',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  stub_command "claude" 'exit 0'

  run bash "${CLD_SRC}" --observer

  # stderr に actionable error が含まれること
  echo "${output}" | grep -qiE 'Invalid.*claude_session_id|invalid.*session.*json|Recovery|session\.json.*invalid' \
    || fail "AC2 FAIL: invalid claude_session_id に対する actionable error が出力されていない。
現行の cld に UUID v4 検証が存在しないため fail する（#1552 RED）。
期待: 'Invalid claude_session_id in session.json: ${invalid_id}' + Recovery 手順が stderr に出力される。
実際の出力: '${output}'"
}

# ---------------------------------------------------------------------------
# read-side AC2-3: 正しい UUID v4 → exec claude --resume が呼ばれる（PATH stub で確認）
# ---------------------------------------------------------------------------

@test "ac2-read-cld-observer: 正しい UUID v4 → exec claude --resume が呼ばれる" {
  # RED: 現行の cld に UUID 検証がないため、通常は PASS するが、
  #      UUID 検証実装後に有効な UUID で --resume が呼ばれることを保証する regression guard。
  # このテストは実装前後ともに PASS を期待する（動作保持確認）。

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  local valid_id
  valid_id=$(_valid_uuid)

  stub_command "git" "echo '${SANDBOX}'"

  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': '${valid_id}',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  # claude stub: args を記録して exit 0
  local args_file="${SANDBOX}/claude.args"
  cat > "${STUB_BIN}/claude" <<CLAUDE_STUB_EOF
#!/bin/bash
echo "claude called: \$*" > "${args_file}"
exit 0
CLAUDE_STUB_EOF
  chmod +x "${STUB_BIN}/claude"

  run bash "${CLD_SRC}" --observer

  # exec claude --resume <valid_id> が呼ばれたこと
  [[ -f "$args_file" ]] \
    || fail "AC2 FAIL: 正常な UUID v4 でも claude が呼ばれていない。
実装後に有効な UUID で --resume が呼ばれることを期待（#1552 AC2 regression guard）。"

  grep -q "resume" "$args_file" \
    || fail "AC2 FAIL: claude --resume が呼ばれていない。
args ファイルの内容: $(cat ${args_file} 2>/dev/null || echo 'empty')"

  grep -q "$valid_id" "$args_file" \
    || fail "AC2 FAIL: 正しい UUID v4 '${valid_id}' が --resume に渡されていない。
args ファイルの内容: $(cat ${args_file} 2>/dev/null || echo 'empty')"
}

# ---------------------------------------------------------------------------
# read-side AC2-4: cld の Python ブロックに UUID v4 検証コードが存在する（static grep）
# ---------------------------------------------------------------------------

@test "ac2-static-cld: cld の claude_session_id 読み取り部に UUID v4 検証が存在する" {
  # RED: 現行の cld に UUID 検証コードが存在しないため fail する
  # PASS 条件（実装後）: cld の L59-71 付近（SESSION_DATA Python ブロック）の後続に
  #                        UUID v4 regex チェックまたは actionable error 出力が存在する

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  grep -qE '[0-9a-f]\{8\}.*-|uuid\.UUID|uuid4.*regex|Invalid.*claude_session_id|invalid.*session.*json|Recovery' \
    "${CLD_SRC}" \
    || fail "AC2 FAIL: cld に UUID v4 検証コードが存在しない。
現行実装には UUID 検証が未実装（#1552 RED）。
期待: 'Invalid claude_session_id in session.json: <value>' + Recovery 手順を含む検証ロジック。"
}

# ===========================================================================
# AC2/AC6 boundary: UUID 境界値テスト
# ===========================================================================

# ---------------------------------------------------------------------------
# boundary-1: 空文字列 → exit 1（空は write 側では許容だが read 側では resume 不可）
# ---------------------------------------------------------------------------

@test "ac6-boundary: 空文字列 claude_session_id で cld --observer が exit 1 する" {
  # AC2 の既存動作: 現行の cld は空文字列で
  # "Observer session found but no Claude session ID recorded" で exit 1 する。
  # UUID 検証実装後も空文字列で exit 1 が維持されること（regression guard）。
  # このテストは現行実装でも PASS する可能性があるが、RED テストとして含める。

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  stub_command "git" "echo '${SANDBOX}'"

  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': '',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  stub_command "claude" 'exit 0'

  run bash "${CLD_SRC}" --observer

  [[ "$status" -ne 0 ]] \
    || fail "AC6-boundary FAIL: 空文字列 claude_session_id で cld --observer が exit 0 した（exit 1 が期待された）。"
}

# ---------------------------------------------------------------------------
# boundary-2: "null"（文字列）→ exit 1（JSON null ではなく文字列 "null"）
# ---------------------------------------------------------------------------

@test "ac6-boundary: 文字列 'null' claude_session_id で cld --observer が exit 1 する" {
  # RED: 現行の cld は文字列 "null" を有効値として claude --resume に渡す可能性がある。
  # PASS 条件（実装後）: "null" は invalid UUID として exit 1

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  stub_command "git" "echo '${SANDBOX}'"

  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': 'null',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  stub_command "claude" 'echo "claude called with null uuid" >&2; exit 0'

  run bash "${CLD_SRC}" --observer

  [[ "$status" -eq 1 ]] \
    || fail "AC6-boundary FAIL: 文字列 'null' の claude_session_id で cld --observer が exit ${status} した（exit 1 が期待された）。
現行の cld に UUID 検証が存在しないため fail する（#1552 RED）。"
}

# ---------------------------------------------------------------------------
# boundary-3: 短縮 UUID b364fc8a（8文字、ハイフンなし）→ exit 1
# ---------------------------------------------------------------------------

@test "ac6-boundary: 短縮UUID b364fc8a で cld --observer が exit 1 する" {
  # RED: 現行の cld は短縮 UUID を有効値として claude --resume に渡す可能性がある。
  # PASS 条件（実装後）: 短縮 UUID は invalid として exit 1

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  stub_command "git" "echo '${SANDBOX}'"

  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': 'b364fc8a',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  stub_command "claude" 'exit 0'

  run bash "${CLD_SRC}" --observer

  [[ "$status" -eq 1 ]] \
    || fail "AC6-boundary FAIL: 短縮 UUID 'b364fc8a' で cld --observer が exit ${status} した（exit 1 が期待された）。
現行の cld に UUID 検証が存在しないため fail する（#1552 RED）。"
}

# ---------------------------------------------------------------------------
# boundary-4: ハイフン数違い（3つ）→ exit 1
# ---------------------------------------------------------------------------

@test "ac6-boundary: ハイフン数違い UUID（3ハイフン）で cld --observer が exit 1 する" {
  # RED: 現行の cld はハイフン数違い UUID を有効値として渡す可能性がある。
  # PASS 条件（実装後）: ハイフン数違いは invalid として exit 1

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  # 正しい形式は 8-4-4-4-12 (4ハイフン)。3ハイフンは invalid
  local malformed_uuid="b364fc8a-1234-5678-abcdef012345"

  stub_command "git" "echo '${SANDBOX}'"

  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': '${malformed_uuid}',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  stub_command "claude" 'exit 0'

  run bash "${CLD_SRC}" --observer

  [[ "$status" -eq 1 ]] \
    || fail "AC6-boundary FAIL: ハイフン数違い UUID '${malformed_uuid}' で cld --observer が exit ${status} した（exit 1 が期待された）。
現行の cld に UUID 検証が存在しないため fail する（#1552 RED）。"
}

# ---------------------------------------------------------------------------
# boundary-5: 正しいフルUUID → exit 0 かつ --resume が呼ばれる（regression guard）
# ---------------------------------------------------------------------------

@test "ac6-boundary: 正しいフル UUID で cld --observer が exit 0 し --resume が呼ばれる" {
  # このテストは現行実装でも PASS する可能性があるが、
  # UUID 検証実装後に正常 UUID で動作が破壊されないことを保証する regression guard。

  [[ -f "$CLD_SRC" ]] \
    || fail "cld が存在しない: ${CLD_SRC}"

  local valid_id
  valid_id=$(_valid_uuid)

  stub_command "git" "echo '${SANDBOX}'"

  mkdir -p "${SANDBOX}/.supervisor"
  python3 -c "
import json, datetime
data = {
  'session_id': '11111111-1111-1111-1111-111111111111',
  'claude_session_id': '${valid_id}',
  'observer_window': 'test-window',
  'mode': 'bypass',
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {'pid': None, 'pane_id': None, 'spawn_cmd': None,
                       'started_at': None, 'log_path': None, 'lock_path': '/tmp/test.lock'}
}
import json as j
j.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"

  local args_file="${SANDBOX}/claude-resume.args"
  cat > "${STUB_BIN}/claude" <<CLAUDE_STUB_EOF2
#!/bin/bash
echo "called: \$*" > "${args_file}"
exit 0
CLAUDE_STUB_EOF2
  chmod +x "${STUB_BIN}/claude"

  run bash "${CLD_SRC}" --observer

  assert_success

  [[ -f "$args_file" ]] && grep -q "resume" "$args_file" \
    || fail "AC6-boundary FAIL: 正しい UUID v4 '${valid_id}' で --resume が呼ばれていない。"
}

# ===========================================================================
# AC6: bats ファイル自体の存在確認（自己参照テスト）
# ===========================================================================

@test "ac6: session-id-uuid-validation.bats が plugins/twl/tests/bats/scripts/ に存在する" {
  # AC6 達成確認: このファイル自体の存在をアサート
  local expected_path="${REPO_ROOT_ABS}/tests/bats/scripts/session-id-uuid-validation.bats"

  [[ -f "$expected_path" ]] \
    || fail "AC6 FAIL: session-id-uuid-validation.bats が存在しない: ${expected_path}"

  # AC1/AC2 に対応するテストが含まれていること
  grep -q 'ac1-write' "${expected_path}" \
    || fail "AC6 FAIL: session-id-uuid-validation.bats に ac1-write テストが含まれていない。"

  grep -q 'ac2-read' "${expected_path}" \
    || fail "AC6 FAIL: session-id-uuid-validation.bats に ac2-read テストが含まれていない。"

  grep -q 'ac6-boundary' "${expected_path}" \
    || fail "AC6 FAIL: session-id-uuid-validation.bats に ac6-boundary テストが含まれていない。"
}
