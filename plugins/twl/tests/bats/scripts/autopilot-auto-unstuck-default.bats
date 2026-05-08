#!/usr/bin/env bats
# autopilot-auto-unstuck-default.bats
# Issue #1582: AUTOPILOT_AUTO_UNSTUCK default=1 切替
#
# AC4 (default=1): ${AUTOPILOT_AUTO_UNSTUCK:-0} → ${AUTOPILOT_AUTO_UNSTUCK:-1}
#                  + AUTOPILOT_AUTO_UNSTUCK_DISABLE=1 で OFF できる path を追加
# AC5 (regression): AUTOPILOT_AUTO_UNSTUCK 未設定で default=1 動作 + DISABLE=1 で無効化
#
# RED: 実装前は全テストが fail（orchestrator は依然 :-0 参照、DISABLE path 未実装）
# GREEN: 実装後に全テスト PASS

load '../helpers/common'

ORCHESTRATOR_SH=""

setup() {
  common_setup
  ORCHESTRATOR_SH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC4 structural: orchestrator.sh の default 値変更 + DISABLE path 確認
# ===========================================================================

@test "ac4: autopilot-orchestrator.sh に AUTOPILOT_AUTO_UNSTUCK:-1 参照が存在する (L643相当)" {
  # RED: 実装前は ${AUTOPILOT_AUTO_UNSTUCK:-0} のまま :-1 が存在しないため fail
  run grep -qF 'AUTOPILOT_AUTO_UNSTUCK:-1' "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac4: autopilot-orchestrator.sh に AUTOPILOT_AUTO_UNSTUCK:-0 参照が残っていない (default=1 完全移行確認)" {
  # RED: 実装前は :-0 が残っているため fail
  run grep -qF 'AUTOPILOT_AUTO_UNSTUCK:-0' "$ORCHESTRATOR_SH"
  assert_failure
}

@test "ac4: autopilot-orchestrator.sh に AUTOPILOT_AUTO_UNSTUCK_DISABLE 参照が存在する" {
  # RED: 実装前は AUTOPILOT_AUTO_UNSTUCK_DISABLE が参照されていないため fail
  run grep -qF 'AUTOPILOT_AUTO_UNSTUCK_DISABLE' "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac4: AUTOPILOT_AUTO_UNSTUCK_DISABLE=1 が unstuck を無効化するロジックが存在する" {
  # RED: DISABLE path 未実装のため fail
  run grep -qE 'AUTOPILOT_AUTO_UNSTUCK_DISABLE.*1.*|1.*AUTOPILOT_AUTO_UNSTUCK_DISABLE' "$ORCHESTRATOR_SH"
  assert_success
}

# ===========================================================================
# AC5 behavioral: AUTOPILOT_AUTO_UNSTUCK 未設定で default=1 動作
# test double でランタイム挙動を検証する
# ===========================================================================

# ---------------------------------------------------------------------------
# _create_unstuck_logic_double:
#   autopilot-orchestrator.sh から AUTOPILOT_AUTO_UNSTUCK の default 値と
#   AUTOPILOT_AUTO_UNSTUCK_DISABLE の有無を抽出して test double を生成する。
#
#   実装前 (:-0) では FORCE_BYPASS が発生しないため、default=1 期待テストが RED になる。
#   実装後 (:-1 + DISABLE path) は FORCE_BYPASS が正しく動作し GREEN になる。
#
# 引数:
#   --elapsed N    デッドロック経過秒数（必須）
#   --sec N        AUTOPILOT_AUTO_UNSTUCK_SEC 相当のタイムアウト秒数（デフォルト: 600）
#
# 環境変数:
#   AUTOPILOT_AUTO_UNSTUCK    （未設定で default 値（実装から抽出）が適用される）
#   AUTOPILOT_AUTO_UNSTUCK_DISABLE  （1 で unstuck 無効化（実装後のみ有効））
#
# 出力:
#   stdout: "FORCE_BYPASS" — force bypass が実行された場合
#   stdout: "NO_BYPASS"    — force bypass が実行されなかった場合
# ---------------------------------------------------------------------------
_create_unstuck_logic_double() {
  # orchestrator.sh から AUTOPILOT_AUTO_UNSTUCK の default 値（0 または 1）を抽出
  local _extracted_default
  _extracted_default=$(grep -oE 'AUTOPILOT_AUTO_UNSTUCK:-[01]' "$ORCHESTRATOR_SH" 2>/dev/null \
    | head -1 | grep -oE '[01]$' || echo "0")

  # orchestrator.sh に AUTOPILOT_AUTO_UNSTUCK_DISABLE が実装されているか確認
  local _has_disable_path="false"
  grep -qF 'AUTOPILOT_AUTO_UNSTUCK_DISABLE' "$ORCHESTRATOR_SH" 2>/dev/null && _has_disable_path="true" || true

  # 抽出した値を test double に埋め込む（非クォート heredoc で変数展開）
  cat > "$SANDBOX/scripts/unstuck-logic-double.sh" <<DOUBLE_EOF
#!/usr/bin/env bash
# unstuck-logic-double.sh — AUTOPILOT_AUTO_UNSTUCK deadlock ロジックの test double
# extracted_default=${_extracted_default}  has_disable=${_has_disable_path}
set -euo pipefail

ELAPSED=0
TIMEOUT_SEC=600

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --elapsed) ELAPSED="\$2"; shift 2 ;;
    --sec)     TIMEOUT_SEC="\$2"; shift 2 ;;
    *) echo "Unknown arg: \$1" >&2; exit 1 ;;
  esac
done

# AUTOPILOT_AUTO_UNSTUCK_DISABLE=1 の場合は unstuck 無効（実装済み時のみ有効）
if [[ "${_has_disable_path}" == "true" && "\${AUTOPILOT_AUTO_UNSTUCK_DISABLE:-0}" == "1" ]]; then
  echo "NO_BYPASS"
  exit 0
fi

# 実装から抽出した default 値（実装前: 0 → NO_BYPASS、実装後: 1 → FORCE_BYPASS）
_auto_unstuck="\${AUTOPILOT_AUTO_UNSTUCK:-${_extracted_default}}"

if [[ "\$_auto_unstuck" == "1" ]] && (( ELAPSED >= TIMEOUT_SEC )); then
  echo "FORCE_BYPASS"
else
  echo "NO_BYPASS"
fi
DOUBLE_EOF
  chmod +x "$SANDBOX/scripts/unstuck-logic-double.sh"
}

@test "ac5: AUTOPILOT_AUTO_UNSTUCK 未設定で 600s deadlock 後に FORCE_BYPASS が実行される（default=1 動作）" {
  _create_unstuck_logic_double

  # AC4 実装前: orchestrator.sh は :-0 なので NO_BYPASS のまま
  # AC4 実装後: :-1 なので 600s 超過で FORCE_BYPASS
  # このテストは test double の実装に依存するため、orchestrator.sh の :-1 変更が
  # test double にも反映されていることを確認する structural test と組み合わせる

  # AUTOPILOT_AUTO_UNSTUCK 環境変数を未設定にして実行
  unset AUTOPILOT_AUTO_UNSTUCK 2>/dev/null || true
  run bash "$SANDBOX/scripts/unstuck-logic-double.sh" --elapsed 601 --sec 600
  assert_success
  assert_output "FORCE_BYPASS"
}

@test "ac5: AUTOPILOT_AUTO_UNSTUCK 未設定で 599s deadlock では FORCE_BYPASS が実行されない" {
  _create_unstuck_logic_double

  unset AUTOPILOT_AUTO_UNSTUCK 2>/dev/null || true
  run bash "$SANDBOX/scripts/unstuck-logic-double.sh" --elapsed 599 --sec 600
  assert_success
  assert_output "NO_BYPASS"
}

@test "ac5: AUTOPILOT_AUTO_UNSTUCK_DISABLE=1 で 600s deadlock でも FORCE_BYPASS が実行されない" {
  _create_unstuck_logic_double

  # DISABLE=1 が最優先で unstuck を無効化することを確認
  unset AUTOPILOT_AUTO_UNSTUCK 2>/dev/null || true
  AUTOPILOT_AUTO_UNSTUCK_DISABLE=1 \
    run bash "$SANDBOX/scripts/unstuck-logic-double.sh" --elapsed 601 --sec 600
  assert_success
  assert_output "NO_BYPASS"
}

@test "ac5: AUTOPILOT_AUTO_UNSTUCK=1 明示設定で AUTOPILOT_AUTO_UNSTUCK_DISABLE=1 が優先される" {
  _create_unstuck_logic_double

  # DISABLE=1 は明示的な AUTOPILOT_AUTO_UNSTUCK=1 より優先する（Issue #1582 AC4 要件）
  AUTOPILOT_AUTO_UNSTUCK=1 AUTOPILOT_AUTO_UNSTUCK_DISABLE=1 \
    run bash "$SANDBOX/scripts/unstuck-logic-double.sh" --elapsed 601 --sec 600
  assert_success
  assert_output "NO_BYPASS"
}

@test "ac5: 既存テスト互換 — AUTOPILOT_AUTO_UNSTUCK=0 明示設定で FORCE_BYPASS が実行されない" {
  _create_unstuck_logic_double

  # 旧 opt-in 挙動の互換性確認（AUTOPILOT_AUTO_UNSTUCK=0 明示で無効）
  AUTOPILOT_AUTO_UNSTUCK=0 \
    run bash "$SANDBOX/scripts/unstuck-logic-double.sh" --elapsed 601 --sec 600
  assert_success
  assert_output "NO_BYPASS"
}
