#!/usr/bin/env bats
# ac-test-1626-worker-detector.bats
#
# Issue #1626: bug(merge-gate): red-only label-based bypass
#
# AC1.1: worker-red-only-detector.sh で red-only label 付き PR 判定時、
#         follow-up Issue 存在を検証する
# AC1.2: red-only label 付き AND follow-up Issue 存在 → WARNING（status: WARN、現状維持）
# AC1.3: red-only label 付き AND follow-up Issue 不在 → CRITICAL 維持（escape hatch 完全閉鎖、status: FAIL）
# AC1.4: red-only-followup-create.sh の body テンプレートに
#         <!-- follow-up-for: PR #N --> marker を追加
# AC1.5: worker-red-only-detector.md の出力スキーマを AC1 の AND 検証に合わせて更新
#
# RED: 全テストは実装前に fail する

load 'helpers/common'

SCRIPTS_DIR=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1.1: worker-red-only-detector.sh で red-only label 付き PR 判定時、
#         follow-up Issue 存在を検証する
#
# RED: 現状は follow-up Issue 存在チェックロジックが未実装のため fail
# ===========================================================================

@test "ac1.1: worker-red-only-detector.sh は red-only label 付き PR で follow-up Issue 存在を検証する" {
  # AC: red-only label 付き PR 判定時に follow-up Issue 存在を検証するロジックが必要
  # RED: 現状 follow-up Issue 検索ロジックが存在しない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue が存在する場合を模擬（issue search で結果を返す）
  stub_command "gh" 'if echo "$*" | grep -qE "issue.*list|issue.*search"; then echo "99\tfollow-up: RED-only PR #1234"; else exit 0; fi'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json"

  # follow-up Issue 存在検証が行われること（gh CLI が呼ばれること）
  # RED: 現状 gh を呼ばずに WARNING exit 0 するため、このテストは impl 後に GREEN になる
  false
}

@test "ac1.1b: worker-red-only-detector.sh は follow-up Issue 検索に marker を使用する" {
  # AC: <!-- follow-up-for: PR #N --> marker で follow-up Issue を検索する
  # RED: marker ベースの検索ロジックが未実装
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # スクリプト内に follow-up-for marker 検索ロジックが静的に存在すること
  run grep -qF 'follow-up-for' "$script"
  assert_success
}

# ===========================================================================
# AC1.2: red-only label 付き AND follow-up Issue 存在 → WARNING（status: WARN、現状維持）
#
# RED: follow-up Issue 存在チェックが未実装のため AND 条件が評価されない
# ===========================================================================

@test "ac1.2: red-only label + follow-up Issue 存在 → WARNING を返す" {
  # AC: AND 条件: label=red-only かつ follow-up Issue 存在 → WARNING（status: WARN）
  # RED: 現状は label のみで WARNING を返しており follow-up 存在確認がない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue 検索で結果あり
  stub_command "gh" 'echo "99\tfollow-up: RED-only PR #1234"'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 1234

  # status: WARN かつ WARNING メッセージが含まれること
  assert_output --partial "WARNING"
  assert_output --partial "WARN"
}

@test "ac1.2b: red-only label + follow-up Issue 存在 → exit 0 で現状維持" {
  # AC: WARNING は現状維持（exit 0 で merge を止めない）
  # RED: follow-up 存在チェックが未実装のため AND 評価がなく exit コードが不確定
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  stub_command "gh" 'echo "99\tfollow-up: RED-only PR #1234"'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 1234

  assert_success
}

# ===========================================================================
# AC1.3: red-only label 付き AND follow-up Issue 不在 → CRITICAL 維持（escape hatch 完全閉鎖）
#
# RED: 現状は label 付きで WARNING を返しており CRITICAL に戻さない
# ===========================================================================

@test "ac1.3: red-only label + follow-up Issue 不在 → CRITICAL を返す" {
  # AC: AND 条件: label=red-only かつ follow-up Issue 不在 → CRITICAL（status: FAIL）
  # RED: 現状 red-only label 付きで WARNING を返すため CRITICAL が出力されない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue 検索で結果なし（空応答）
  stub_command "gh" 'exit 0'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 9999

  assert_output --partial "CRITICAL"
}

@test "ac1.3b: red-only label + follow-up Issue 不在 → status: FAIL が含まれる" {
  # AC: escape hatch 完全閉鎖 — status: FAIL を出力
  # RED: 現状 WARNING を返し FAIL を含まない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  stub_command "gh" 'exit 0'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 9999

  assert_output --partial "FAIL"
}

@test "ac1.3c: red-only label + follow-up Issue 不在 → WARNING を出力しない（CRITICAL に昇格）" {
  # AC: follow-up 不在時は WARNING ではなく CRITICAL
  # RED: 現状 WARNING が出力される
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  stub_command "gh" 'exit 0'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 9999

  refute_output --partial "WARNING"
}

# ===========================================================================
# AC1.4: red-only-followup-create.sh の body テンプレートに
#         <!-- follow-up-for: PR #N --> marker を追加
#
# RED: 現状 body テンプレートに marker が存在しない
# ===========================================================================

@test "ac1.4: red-only-followup-create.sh の body テンプレートに follow-up-for marker が存在する" {
  # AC: <!-- follow-up-for: PR #N --> marker が body テンプレートに含まれること
  # RED: 現状 marker が存在しないため grep fail
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]

  run grep -qF '<!-- follow-up-for: PR #' "$script"
  assert_success
}

@test "ac1.4b: red-only-followup-create.sh の dry-run 出力に follow-up-for marker が含まれる" {
  # AC: 実際の body 出力に marker が含まれること（dry-run で検証）
  # RED: marker が未追加のため dry-run 出力に含まれない
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]

  run bash "$script" --pr-number 1234 --dry-run
  assert_output --partial "follow-up-for: PR #1234"
}

# ===========================================================================
# AC1.5: worker-red-only-detector.md の出力スキーマを AC1 の AND 検証に合わせて更新
#
# RED: 現状 md のスキーマが AND 検証（follow-up 存在確認）を記述していない
# ===========================================================================

@test "ac1.5: worker-red-only-detector.md に AND 検証の出力スキーマが記述される" {
  # AC: md の出力スキーマに follow-up Issue 存在確認 AND 条件が明記されること
  # RED: 現状スキーマに AND 条件の記述がない
  local md_files
  md_files=$(find "${REPO_ROOT}" -name "worker-red-only-detector.md" -not -path "*/test*" 2>/dev/null | head -3)
  [ -n "$md_files" ]

  local md_found=0
  for md in $md_files; do
    if grep -qE 'follow-up.*存在|AND.*follow-up|follow-up.*AND' "$md" 2>/dev/null; then
      md_found=1
      break
    fi
  done
  [ "$md_found" -eq 1 ]
}

@test "ac1.5b: worker-red-only-detector.md の出力スキーマに status: WARN と status: FAIL の両方が定義される" {
  # AC: AND 検証に対応した出力スキーマ — WARN（follow-up 存在時）と FAIL（不在時）を区別
  # RED: 現状スキーマが更新されていない
  local md_files
  md_files=$(find "${REPO_ROOT}" -name "worker-red-only-detector.md" -not -path "*/test*" 2>/dev/null | head -3)
  [ -n "$md_files" ]

  for md in $md_files; do
    if grep -qF 'WARN' "$md" 2>/dev/null && grep -qF 'FAIL' "$md" 2>/dev/null; then
      return 0
    fi
  done
  false
}
