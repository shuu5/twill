#!/usr/bin/env bats
# su-observer-window-check.bats - Issue #948 AC9/AC10/AC11 RED テスト
#
# AC9: monitor-channel-catalog.md の window 存在確認例を has-session 誤用から正しい方法に差し替え
#      方法 A/B/C を記載、誤用例と正しい例を対比表示
# AC10: su-observer 配下の shell snippet から has-session -t <window-name> 誤用を修正
#       修正後 grep -rn "has-session -t" plugins/twl/skills/su-observer/ が 0 件
# AC11: _check_window_alive() ヘルパー関数を追加
#       共通ライブラリ plugins/twl/scripts/lib/observer-window-check.sh に実装
#
# Coverage: unit（ドキュメント + スクリプト存在確認 + 関数動作検証）

load '../helpers/common'

MONITOR_CATALOG_MD=""
OBSERVER_LIB=""
SU_OBSERVER_DIR=""

setup() {
  common_setup
  MONITOR_CATALOG_MD="$REPO_ROOT/skills/su-observer/refs/monitor-channel-catalog.md"
  OBSERVER_LIB="$REPO_ROOT/../scripts/lib/observer-window-check.sh"
  SU_OBSERVER_DIR="$REPO_ROOT/skills/su-observer"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC9: monitor-channel-catalog.md の has-session 誤用修正確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: monitor-channel-catalog.md に window 存在確認の方法 A/B/C が記載されている
# WHEN: monitor-channel-catalog.md を参照する
# THEN: 方法 A, B, C が記載されている
# ---------------------------------------------------------------------------

@test "AC9: monitor-channel-catalog.md に window 存在確認 方法 A が記載されている" {
  # RED: ドキュメント未更新のため fail する
  [[ -f "$MONITOR_CATALOG_MD" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG_MD"

  grep -qiE '方法[[:space:]]*A|Method[[:space:]]*A|方法A' "$MONITOR_CATALOG_MD" \
    || fail "monitor-channel-catalog.md に window 存在確認 方法 A が存在しない"
}

@test "AC9: monitor-channel-catalog.md に window 存在確認 方法 B が記載されている" {
  # RED: ドキュメント未更新のため fail する
  [[ -f "$MONITOR_CATALOG_MD" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG_MD"

  grep -qiE '方法[[:space:]]*B|Method[[:space:]]*B|方法B' "$MONITOR_CATALOG_MD" \
    || fail "monitor-channel-catalog.md に window 存在確認 方法 B が存在しない"
}

@test "AC9: monitor-channel-catalog.md に window 存在確認 方法 C が記載されている" {
  # RED: ドキュメント未更新のため fail する
  [[ -f "$MONITOR_CATALOG_MD" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG_MD"

  grep -qiE '方法[[:space:]]*C|Method[[:space:]]*C|方法C' "$MONITOR_CATALOG_MD" \
    || fail "monitor-channel-catalog.md に window 存在確認 方法 C が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: monitor-channel-catalog.md に has-session -t 誤用例と正しい例の対比が存在する
# WHEN: monitor-channel-catalog.md を参照する
# THEN: 誤用例と正しい例が対比表示されている
# ---------------------------------------------------------------------------

@test "AC9: monitor-channel-catalog.md に has-session 誤用例と正しい例の対比が存在する" {
  # RED: ドキュメント未更新のため fail する
  [[ -f "$MONITOR_CATALOG_MD" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG_MD"

  grep -qiE '誤用|誤り|NG|incorrect|wrong' "$MONITOR_CATALOG_MD" \
    || fail "monitor-channel-catalog.md に has-session 誤用例の対比記述が存在しない"
}

# ===========================================================================
# AC10: su-observer 配下の has-session -t 誤用件数が 0 件
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: su-observer/ 配下に has-session -t <window-name> 誤用が存在しない
# WHEN: grep -rn "has-session -t" plugins/twl/skills/su-observer/ を実行する
# THEN: テストモック以外で 0 件（テストファイル除外後 0 件）
# ---------------------------------------------------------------------------

@test "AC10: su-observer/ 配下に has-session -t の誤用が 0 件である（テストファイル除外）" {
  # RED: 修正未実施のため fail する（誤用が残っている場合）
  [[ -d "$SU_OBSERVER_DIR" ]] \
    || fail "su-observer ディレクトリが存在しない: $SU_OBSERVER_DIR"

  # テストファイル（*.bats）と文書ファイル（*.md）を除外して shell script の誤用のみを検索
  # .md ファイルは誤用パターンの説明文として has-session -t を含む場合があるため除外
  local count
  count=$(grep -rn "has-session -t" "$SU_OBSERVER_DIR" \
    --include="*.sh" --include="*.bash" \
    2>/dev/null | wc -l)

  [[ "$count" -eq 0 ]] \
    || fail "su-observer/ 配下に has-session -t 誤用が ${count} 件残っている（AC10 未実装）"
}

# ===========================================================================
# AC11: _check_window_alive() ヘルパー関数の実装確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: observer-window-check.sh が共通ライブラリとして存在する
# WHEN: plugins/twl/scripts/lib/observer-window-check.sh を参照する
# THEN: ファイルが存在する
# ---------------------------------------------------------------------------

@test "AC11: scripts/lib/observer-window-check.sh が存在する" {
  # RED: ライブラリ未作成のため fail する
  local lib_path
  lib_path="$REPO_ROOT/scripts/lib/observer-window-check.sh"

  [[ -f "$lib_path" ]] \
    || fail "observer-window-check.sh が存在しない: $lib_path"
}

# ---------------------------------------------------------------------------
# Scenario: observer-window-check.sh に _check_window_alive 関数が定義されている
# WHEN: observer-window-check.sh を source する
# THEN: _check_window_alive 関数が定義されている
# ---------------------------------------------------------------------------

@test "AC11: observer-window-check.sh に _check_window_alive() が定義されている" {
  # RED: ライブラリ未作成のため fail する
  local lib_path
  lib_path="$REPO_ROOT/scripts/lib/observer-window-check.sh"

  [[ -f "$lib_path" ]] \
    || fail "observer-window-check.sh が存在しない（前提条件 AC11 未実装）"

  grep -q '_check_window_alive' "$lib_path" \
    || fail "observer-window-check.sh に _check_window_alive() が定義されていない"
}

# ---------------------------------------------------------------------------
# Scenario: _check_window_alive は存在しない window で exit 1 を返す
# WHEN: _check_window_alive に存在しない window 名を渡す
# THEN: exit 1（window 不在）を返す
# ---------------------------------------------------------------------------

@test "AC11: _check_window_alive は存在しない window で exit 1 を返す" {
  # RED: ライブラリ未作成のため fail する
  local lib_path
  lib_path="$REPO_ROOT/scripts/lib/observer-window-check.sh"

  [[ -f "$lib_path" ]] \
    || fail "observer-window-check.sh が存在しない（前提条件 AC11 未実装）"

  # tmux stub: list-windows が空を返すことで window 不在をシミュレート
  stub_command "tmux" '
if echo "$*" | grep -q "list-windows"; then
  exit 1
else
  exit 0
fi'

  # observer-window-check.sh を source して _check_window_alive を呼び出す
  run bash -c "
    source '$lib_path'
    _check_window_alive 'non-existent-window-99999'
  "

  assert_failure
}

# ---------------------------------------------------------------------------
# Scenario: _check_window_alive は存在する window で exit 0 を返す
# WHEN: _check_window_alive に存在する window 名を渡す
# THEN: exit 0（window 生存確認）を返す
# ---------------------------------------------------------------------------

@test "AC11: _check_window_alive は存在する window で exit 0 を返す" {
  # RED: ライブラリ未作成のため fail する
  local lib_path
  lib_path="$REPO_ROOT/scripts/lib/observer-window-check.sh"

  [[ -f "$lib_path" ]] \
    || fail "observer-window-check.sh が存在しない（前提条件 AC11 未実装）"

  # tmux stub: list-windows が window 名を返すことで window 存在をシミュレート
  stub_command "tmux" '
if echo "$*" | grep -q "list-windows"; then
  echo "ap-42"
  echo "wt-co-autopilot-123456"
  exit 0
else
  exit 0
fi'

  # observer-window-check.sh を source して _check_window_alive を呼び出す
  run bash -c "
    source '$lib_path'
    _check_window_alive 'ap-42'
  "

  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: _check_window_alive は has-session -t を使用しない
# WHEN: observer-window-check.sh の実装を確認する
# THEN: has-session -t による誤った window 存在確認が含まれていない
# ---------------------------------------------------------------------------

@test "AC11: observer-window-check.sh が has-session -t を使用しない（誤用回避）" {
  # RED: ライブラリ未作成のため fail する
  local lib_path
  lib_path="$REPO_ROOT/scripts/lib/observer-window-check.sh"

  [[ -f "$lib_path" ]] \
    || fail "observer-window-check.sh が存在しない（前提条件 AC11 未実装）"

  run grep 'has-session -t' "$lib_path"

  # has-session -t が存在しないことが期待（exit 1 = not found = PASS）
  assert_failure
}
