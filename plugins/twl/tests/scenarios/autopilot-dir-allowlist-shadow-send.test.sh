#!/usr/bin/env bash
# =============================================================================
# Tests: AUTOPILOT_DIR allowlist validation in _backend_shadow_send
# Issue: #1411 — tech-debt: AUTOPILOT_DIR allowlist for shadow log write
# Coverage:
#   AC1: _backend_shadow_send で AUTOPILOT_DIR resolved 値を allowlist 検証してから mkdir-p / >> を実行
#   AC2: 不正値の場合 shadow log 書き出しをスキップ、stderr に Warning を出力
#   AC3: allowlist は絶対パス + .. 非含有 + /tmp / /run/user/<uid> / project_root の 3 種
#   AC4: /run/user/$(id -u) を hardcode（XDG_RUNTIME_DIR を使用しない）
#   AC5: 既存の正常ケース（AUTOPILOT_DIR 未設定 → .autopilot）が引き続き動作
#   AC6: 機能テスト — (a) パストラバーサル拒否, (b) allowlist 外絶対パス拒否,
#                      (c) デフォルト動作（未設定）, (d) /tmp 配下許可
# =============================================================================
set -uo pipefail

# plugins/twl のルート（tests/scenarios/ から 2 階層上）
TWL_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# worktree ルート（plugins/twl/ の親 2 階層上 = worktree root）
PROJECT_ROOT="$(cd "${TWL_ROOT}/../.." && pwd)"

BACKEND_MCP_SH="${PROJECT_ROOT}/plugins/session/scripts/session-comm-backend-mcp.sh"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
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

# BACKEND_MCP_SH のリポジトリ相対パス（assert_file_contains 用）
IMPL_FILE="plugins/session/scripts/session-comm-backend-mcp.sh"

# =============================================================================
# Document Verification Tests: AC1-AC5
# =============================================================================
echo ""
echo "--- AC1: _backend_shadow_send が allowlist 検証後に mkdir-p / >> を実行する ---"

# RED: allowlist チェックが存在しないうちは fail
test_ac1_allowlist_check_before_mkdir() {
  # allowlist 検証コードの存在: is_allowed 変数または allowlist パターンの使用
  assert_file_contains "$IMPL_FILE" \
    'is_allowed|allowlist|_shadow_allowed'
}

run_test "ac1: _backend_shadow_send に allowlist 検証コードが存在する" \
  test_ac1_allowlist_check_before_mkdir

# RED: 現在 mkdir -p の前に allowlist チェックがない
test_ac1_allowlist_precedes_mkdir() {
  # allowlist 変数宣言行が mkdir -p より前にファイル内で出現する構造確認
  # allowlist に関連するコメント (#OWASP A01) またはコードが _backend_shadow_send 関数内にある
  assert_file_contains "$IMPL_FILE" \
    'OWASP.*A01|allowlist.*shadow|_shadow_send.*allowlist|_is_shadow_dir_allowed'
}

run_test "ac1: _backend_shadow_send 内に allowlist 検証の構造的記述（コメントまたは変数）が存在する" \
  test_ac1_allowlist_precedes_mkdir

# =============================================================================
echo ""
echo "--- AC2: 不正値の場合 skip + stderr Warning 出力 ---"

# RED: 現在 Warning メッセージが存在しない
test_ac2_warning_message_on_invalid() {
  # Warning: AUTOPILOT_DIR ... is not allowed ... shadow log skipped のパターン
  assert_file_contains "$IMPL_FILE" \
    "Warning.*AUTOPILOT_DIR.*is not allowed|shadow log skipped"
}

run_test "ac2: 不正 AUTOPILOT_DIR 時の Warning メッセージが実装されている" \
  test_ac2_warning_message_on_invalid

# RED: 現在 stderr 出力 (&>2) がこのパスに存在しない
test_ac2_warning_to_stderr() {
  # >&2 で Warning を出力するコードが _backend_shadow_send 付近にある
  assert_file_contains "$IMPL_FILE" \
    'Warning.*AUTOPILOT_DIR.*>&\s*2|>&\s*2.*Warning.*AUTOPILOT_DIR'
}

run_test "ac2: Warning が stderr (>&2) に出力される" \
  test_ac2_warning_to_stderr

# RED: 現在 shadow skip パスが存在しない
test_ac2_shadow_skip_on_invalid() {
  # 不正値でスキップするコード（return や continue, if...fi で shadow log ブロックを囲む）
  assert_file_contains "$IMPL_FILE" \
    'shadow log skipped|_shadow_skip\|skip.*shadow'
}

run_test "ac2: 不正値時に shadow log 書き出しをスキップする制御フローが存在する" \
  test_ac2_shadow_skip_on_invalid

# =============================================================================
echo ""
echo "--- AC3: allowlist は /tmp / /run/user/<uid> / project_root の 3 種 ---"

# RED: 現在 allowlist に 3 種のプレフィックスチェックが存在しない
test_ac3_allowlist_has_tmp() {
  # /tmp プレフィックスチェック
  assert_file_contains "$IMPL_FILE" \
    '\/tmp.*shadow|shadow.*\/tmp|_shadow.*==.*\/tmp'
}

run_test "ac3: allowlist に /tmp プレフィックスチェックが存在する" \
  test_ac3_allowlist_has_tmp

test_ac3_allowlist_has_run_user() {
  # /run/user/<uid> プレフィックスチェック
  assert_file_contains "$IMPL_FILE" \
    '\/run\/user.*shadow|shadow.*\/run\/user|_shadow.*run.*user'
}

run_test "ac3: allowlist に /run/user/<uid> プレフィックスチェックが存在する" \
  test_ac3_allowlist_has_run_user

test_ac3_allowlist_has_project_root() {
  # project root チェック（git rev-parse --show-toplevel または pwd フォールバック）
  assert_file_contains "$IMPL_FILE" \
    'git rev-parse.*show-toplevel|_project_root.*shadow|shadow.*project.root|_shadow.*git.*rev-parse'
}

run_test "ac3: allowlist に project root チェック（git rev-parse 利用）が存在する" \
  test_ac3_allowlist_has_project_root

test_ac3_project_root_pwd_fallback() {
  # git rev-parse 失敗時に pwd にフォールバック
  assert_file_contains "$IMPL_FILE" \
    'git rev-parse.*show-toplevel.*\|\|.*pwd|show-toplevel.*2>.*pwd|rev-parse.*fallback'
}

run_test "ac3: git rev-parse 失敗時に pwd フォールバックが存在する" \
  test_ac3_project_root_pwd_fallback

test_ac3_dotdot_check() {
  # .. 含有チェック
  assert_file_contains "$IMPL_FILE" \
    '\.\.|dotdot|shadow.*\.\.'
}

run_test "ac3: AUTOPILOT_DIR の .. 含有チェックが存在する" \
  test_ac3_dotdot_check

test_ac3_absolute_path_check() {
  # 絶対パスチェック（/* で始まるか）
  assert_file_contains "$IMPL_FILE" \
    'shadow.*!=.*\/\*|shadow.*=~.*\^\/|_shadow.*absolute|_shadow.*\[.*\/\]'
}

run_test "ac3: AUTOPILOT_DIR の絶対パスチェックが存在する" \
  test_ac3_absolute_path_check

# =============================================================================
echo ""
echo "--- AC4: /run/user/\$(id -u) を hardcode（XDG_RUNTIME_DIR を使用しない）---"

# RED: 現在 _backend_shadow_send 内に /run/user/$(id -u) が存在しない
test_ac4_hardcoded_run_user() {
  # /run/user/$(id -u) の hardcode — XDG_RUNTIME_DIR を使わず id -u で固定
  assert_file_contains "$IMPL_FILE" \
    '\/run\/user\/\$\(id -u\)|\/run\/user\/\$\{UID\}'
}

run_test "ac4: /run/user/\$(id -u) が hardcode されている（XDG_RUNTIME_DIR 非使用）" \
  test_ac4_hardcoded_run_user

test_ac4_no_xdg_runtime_dir_in_shadow() {
  # _backend_shadow_send 関数内で XDG_RUNTIME_DIR を参照していない
  # ファイル全体での grep なので false negative リスクあり — 関数内限定の検証には十分
  assert_file_not_contains "$IMPL_FILE" \
    'XDG_RUNTIME_DIR.*shadow|shadow.*XDG_RUNTIME_DIR'
}

run_test "ac4: shadow send 文脈で XDG_RUNTIME_DIR が参照されていない" \
  test_ac4_no_xdg_runtime_dir_in_shadow

# =============================================================================
echo ""
echo "--- AC5: 既存の正常ケース（AUTOPILOT_DIR 未設定 → .autopilot）が動作する ---"

# GREEN: 現在この構造は存在する（regression guard）
test_ac5_default_autopilot_dir_pattern() {
  # AUTOPILOT_DIR:-.autopilot のパターンが存在する
  assert_file_contains "$IMPL_FILE" \
    'AUTOPILOT_DIR:-\.autopilot'
}

run_test "ac5: AUTOPILOT_DIR 未設定時の .autopilot デフォルト値パターンが存在する（regression guard）" \
  test_ac5_default_autopilot_dir_pattern

# =============================================================================
# Functional Tests: AC6 (a)(b)(c)(d)
# _backend_shadow_send を実際に呼び出して動作を検証する
#
# 注意: _backend_shadow_send は内部で session-comm-backend-tmux.sh を source して
# _backend_tmux_send を呼ぶ。機能テストではこれを stub する必要がある。
# テスト用 tmpdir に stub の backend-tmux.sh を配置し、
# _BACKEND_MCP_SCRIPT_DIR を上書きすることで回避する。
# =============================================================================
echo ""
echo "--- AC6: 機能テスト — _backend_shadow_send の allowlist 動作 ---"

# ヘルパー: 機能テスト用の tmpdir をセットアップ
# stub session-comm-backend-tmux.sh を配置して tmux 依存を回避する
_setup_functest_env() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  # stub backend-tmux.sh (tmux 依存を排除)
  cat > "${tmpdir}/session-comm-backend-tmux.sh" <<'STUB'
#!/bin/bash
_backend_tmux_send() {
  # stub: always succeed without tmux
  return 0
}
STUB
  chmod +x "${tmpdir}/session-comm-backend-tmux.sh"

  echo "$tmpdir"
}

# ヘルパー: backend-mcp.sh の _backend_shadow_send を subshell で呼び出す
# 引数: tmpdir target content [AUTOPILOT_DIR_VALUE]
_run_shadow_send() {
  local tmpdir="$1"
  local target="$2"
  local content="$3"
  local autopilot_dir="${4:-}"

  (
    # set -euo pipefail は source 先でも設定されているが、
    # background job 内の失敗は return code で伝播しないため親で確認
    export _BACKEND_MCP_SCRIPT_DIR="$tmpdir"
    if [[ -n "$autopilot_dir" ]]; then
      export AUTOPILOT_DIR="$autopilot_dir"
    else
      unset AUTOPILOT_DIR 2>/dev/null || true
    fi
    # _backend_mcp_python_send も stub
    _backend_mcp_python_send() { return 0; }
    export -f _backend_mcp_python_send

    # source して _backend_shadow_send を呼ぶ
    # BASH_SOURCE[0] != $0 なので直接実行パスには入らない
    # shellcheck source=/dev/null
    source "$BACKEND_MCP_SH"
    _backend_shadow_send "$target" "$content"
  )
}

# AC6(a): パストラバーサル拒否 (AUTOPILOT_DIR=../../etc)
test_ac6a_path_traversal_rejected() {
  # RED: 現在の実装では allowlist チェックがないため ../../etc でも shadow log が書き出される
  # 実装後: ../../etc を resolve すると allowlist 外 → skip → shadow log ファイルが作成されない

  [[ -f "$BACKEND_MCP_SH" ]] || return 1

  local tmpdir
  tmpdir="$(_setup_functest_env)"
  local shadow_dir="${tmpdir}/shadow_check_a"
  mkdir -p "$shadow_dir"

  # CWD を tmpdir に変えて ../../etc を cwd 相対で解決させる
  local shadow_log_path
  shadow_log_path=$(cd "$shadow_dir" && realpath "../../etc" 2>/dev/null || echo "")

  # _run_shadow_send を実行（stderr は /dev/null にリダイレクト）
  _run_shadow_send "$tmpdir" "test-target" "test-content" "../../etc" 2>/dev/null || true

  # allowlist チェック実装後: ../../etc/mailbox/shadow-*.jsonl が作成されていないこと
  # 現在（未実装）: ../../etc 配下に mkdir -p が走り得る状態 → テストは FAIL
  local resolved_shadow
  resolved_shadow="${shadow_dir}/../../etc/mailbox"
  # ファイルが作成されていないこと（実装後は pass, 現在は実装なしで fail になる）
  # Warning が stderr に出力されることを確認（実装後）
  local stderr_output
  stderr_output=$(
    export _BACKEND_MCP_SCRIPT_DIR="$tmpdir"
    export AUTOPILOT_DIR="../../etc"
    _backend_mcp_python_send() { return 0; }
    export -f _backend_mcp_python_send
    # shellcheck source=/dev/null
    source "$BACKEND_MCP_SH" 2>/dev/null || true
    _backend_shadow_send "test-target" "test-content" 2>&1 1>/dev/null || true
  )

  # RED condition: 実装前は Warning が stderr に出ない → grep が失敗 → テスト FAIL
  echo "$stderr_output" | grep -q "Warning.*AUTOPILOT_DIR\|shadow log skipped"
  local check_result=$?

  rm -rf "$tmpdir"
  return $check_result
}

run_test "ac6(a): AUTOPILOT_DIR=../../etc (パストラバーサル) → stderr に Warning が出る" \
  test_ac6a_path_traversal_rejected

# AC6(b): allowlist 外絶対パス拒否 (AUTOPILOT_DIR=/var/log/foo)
test_ac6b_outside_allowlist_rejected() {
  # RED: 現在の実装では /var/log/foo でも shadow log が書き出される
  # 実装後: /var/log/foo は /tmp / /run/user / project_root に該当しない → skip

  [[ -f "$BACKEND_MCP_SH" ]] || return 1

  local tmpdir
  tmpdir="$(_setup_functest_env)"

  local stderr_output
  stderr_output=$(
    export _BACKEND_MCP_SCRIPT_DIR="$tmpdir"
    export AUTOPILOT_DIR="/var/log/foo"
    _backend_mcp_python_send() { return 0; }
    export -f _backend_mcp_python_send
    # shellcheck source=/dev/null
    source "$BACKEND_MCP_SH" 2>/dev/null || true
    _backend_shadow_send "test-target" "test-content" 2>&1 1>/dev/null || true
  )

  # RED condition: 実装前は Warning が出ない → grep 失敗 → FAIL
  echo "$stderr_output" | grep -q "Warning.*AUTOPILOT_DIR\|shadow log skipped"
  local check_result=$?

  rm -rf "$tmpdir"
  return $check_result
}

run_test "ac6(b): AUTOPILOT_DIR=/var/log/foo (allowlist 外絶対パス) → stderr に Warning が出る" \
  test_ac6b_outside_allowlist_rejected

# AC6(c): デフォルト動作 — AUTOPILOT_DIR 未設定 (.autopilot 相対 → cwd で project 配下に解決)
test_ac6c_default_behavior_unset() {
  # GREEN after impl / RED before impl only if impl breaks default path
  # 現在の実装では AUTOPILOT_DIR 未設定時は .autopilot に fallback して動作する
  # 実装後も同動作が維持されること（regression guard として RED ではなく構造確認）
  #
  # このテストは「実装前に .autopilot が project 配下に解決されるため skip されない」
  # ことを確認する。allowlist チェックが追加された後も、
  # project_root/.autopilot は project_root allowlist に含まれるため PASS すること。

  [[ -f "$BACKEND_MCP_SH" ]] || return 1

  local tmpdir
  tmpdir="$(_setup_functest_env)"

  # tmpdir を cwd として、git rev-parse が project_root を返すよう stub
  # 実際には tmpdir に .git を作らなくても、AUTOPILOT_DIR 未設定時の挙動が
  # shadow log を書こうとする（background job）ことを確認するだけで十分
  local exit_code
  exit_code=0
  (
    export _BACKEND_MCP_SCRIPT_DIR="$tmpdir"
    unset AUTOPILOT_DIR 2>/dev/null || true
    _backend_mcp_python_send() { return 0; }
    export -f _backend_mcp_python_send
    # shellcheck source=/dev/null
    source "$BACKEND_MCP_SH" 2>/dev/null || true
    _backend_shadow_send "test-target" "test-content" 2>/dev/null || true
    # _backend_tmux_send が 0 を返せば全体として 0
  ) || exit_code=$?

  rm -rf "$tmpdir"

  # tmux_send stub が 0 を返すので、return code は 0 のはず
  [[ $exit_code -eq 0 ]]
}

run_test "ac6(c): AUTOPILOT_DIR 未設定時はエラーなく完了する（デフォルト動作）" \
  test_ac6c_default_behavior_unset

# AC6(d): /tmp 配下許可 (AUTOPILOT_DIR=/tmp/test-shadow)
test_ac6d_tmp_allowed() {
  # RED: 現在は allowlist チェックがないため /tmp でも動作するが、
  # 実装後も /tmp は allowlist に含まれるため動作すること（PASS が期待値）
  # ただし実装前は allowlist チェック自体がないため、
  # このテストは「/tmp を指定したとき Warning が出ない」ことを確認する

  [[ -f "$BACKEND_MCP_SH" ]] || return 1

  local tmpdir
  tmpdir="$(_setup_functest_env)"
  local shadow_target_dir="/tmp/test-shadow-send-1411-$$"

  local stderr_output
  stderr_output=$(
    export _BACKEND_MCP_SCRIPT_DIR="$tmpdir"
    export AUTOPILOT_DIR="$shadow_target_dir"
    _backend_mcp_python_send() { return 0; }
    export -f _backend_mcp_python_send
    # shellcheck source=/dev/null
    source "$BACKEND_MCP_SH" 2>/dev/null || true
    _backend_shadow_send "test-target" "test-content" 2>&1 1>/dev/null || true
    # background job を待つ
    wait 2>/dev/null || true
  )

  rm -rf "$tmpdir" "$shadow_target_dir" 2>/dev/null || true

  # 実装後: /tmp は allowlist に含まれるため Warning が出ない → grep が失敗 → テスト PASS
  # 実装前: allowlist チェックがないため Warning が出ない → grep が失敗 → テスト PASS
  # このテストは実装前後ともに PASS する regression guard
  # → RED にするため、「実装後に /tmp で shadow log が作成されること」を代わりに確認する
  #
  # 代替 RED チェック: 実装後は allowlist が存在するという構造確認
  # /tmp が is_allowed になるコードが実装に存在すること（AC3 の doc test と対応）
  assert_file_contains "$IMPL_FILE" \
    '_shadow.*==.*\/tmp|shadow.*\/tmp.*is_allowed|_shadow_dir.*==.*\/tmp'
}

run_test "ac6(d): AUTOPILOT_DIR=/tmp/... → allowlist 許可コードが実装されている" \
  test_ac6d_tmp_allowed

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
