#!/usr/bin/env bats
# issue-1378-record-detection-gap-allowlist.bats
#
# RED-phase tests for Issue #1378:
#   tech-debt(observer): record-detection-gap.sh L61-69 のパス検証を blocklist から allowlist regex へ
#
# AC coverage:
#   AC1:  静的確認 — allowlist regex `^[A-Za-z0-9._/-]+$` が script に存在する
#   AC3:  正常パス受理 (.supervisor, .supervisor-test, nested/deep/.supervisor)
#   AC4:  絶対パス拒否 (/etc, /tmp/foo) + エラーメッセージ形式確認
#   AC5:  path traversal 拒否 (../foo, foo/../bar) + エラーメッセージ形式確認
#   AC6:  shell 特殊文字拒否 ($foo, a;b, a|b, a`b, a&b, a(b, a<b, a>b)
#   AC7:  空文字/未定義 SUPERVISOR_DIR → .supervisor フォールバック受理
#   AC8:  既存テストファイルが存在する（回帰参照）
#   AC9:  `# allowlist regex per baseline-bash §11` コメントが script に存在する
#   AC10: baseline-bash.md §11 セクションが存在する
#
# RED となるテスト: AC1 (allowlist pattern 不在), AC4b/AC5b/AC6b (error message format),
#                   AC9 (comment 不在), AC10 (§11 不在)
# PASS 可能性あり: AC3, AC7, AC8 (現行実装でも動作) — RED guard は bats では skip される

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  # tests/bats/ -> tests/ -> plugins/twl/ (REPO_ROOT)
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-detection-gap.sh"
  BASELINE_BASH="${REPO_ROOT}/refs/baseline-bash.md"
  export SCRIPT BASELINE_BASH

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
  cd "${TMPDIR_TEST}"
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: allowlist regex が script に存在する（静的確認）
# ===========================================================================

@test "ac1: script contains allowlist regex pattern ^[A-Za-z0-9._/-]" {
  # AC: blocklist 3 チェックが allowlist regex に置換されている（静的確認）
  # RED: 現在は blocklist 実装のため allowlist pattern が存在せず fail
  run grep -qE '\^\[A-Za-z0-9' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac1: script contains allowlist anchored regex ending with +\$ marker" {
  # AC: allowlist regex が ^ anchor と \$ 終端を持つ（全文一致パターン）
  # RED: 現在の blocklist は部分マッチのため fail
  run grep -qP '\^\[A-Za-z0-9[^\]]*\]\+\$' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: 正常パスが受理される
# ===========================================================================

@test "ac3: .supervisor (default) is accepted with exit 0" {
  # AC: 正常パス .supervisor が受理される（現行実装でも PASS の可能性あり）
  run bash "${SCRIPT}" --type "allowlist-test" --detail "normal path"
  [ "${status}" -eq 0 ]
}

@test "ac3: .supervisor-test is accepted with exit 0" {
  # AC: 正常パス .supervisor-test（ハイフン含む）が受理される
  SUPERVISOR_DIR=".supervisor-test" run bash "${SCRIPT}" --type "allowlist-test" --detail "hyphen path"
  [ "${status}" -eq 0 ]
}

@test "ac3: nested/deep/.supervisor is accepted with exit 0" {
  # AC: 正常パス nested/deep/.supervisor（スラッシュ含む）が受理される
  mkdir -p nested/deep
  SUPERVISOR_DIR="nested/deep/.supervisor" run bash "${SCRIPT}" --type "allowlist-test" --detail "nested path"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: 絶対パスが拒否される (exit 1 + ERROR メッセージ形式)
# ===========================================================================

@test "ac4: /etc is rejected with exit 1" {
  # AC: 絶対パス /etc は exit 1 で拒否される
  SUPERVISOR_DIR="/etc" run bash "${SCRIPT}" --type "test" --detail "absolute path"
  [ "${status}" -eq 1 ]
}

@test "ac4: /etc rejection error message contains 'invalid path:' per baseline-bash §11" {
  # AC: エラーメッセージは baseline-bash §11 パターン 'invalid path: <path>' 形式
  # RED: 現行実装のメッセージ "must not be an absolute path" は新形式と不一致 → fail
  SUPERVISOR_DIR="/etc" run bash -c "bash '${SCRIPT}' --type test --detail 'absolute path' 2>&1 >/dev/null"
  [[ "${output}" =~ "invalid path:" ]]
}

@test "ac4: /tmp/foo is rejected with exit 1" {
  # AC: 絶対パス /tmp/foo は exit 1 で拒否される
  SUPERVISOR_DIR="/tmp/foo" run bash "${SCRIPT}" --type "test" --detail "absolute path"
  [ "${status}" -eq 1 ]
}

# ===========================================================================
# AC5: path traversal を含むパスが拒否される (exit 1)
# ===========================================================================

@test "ac5: ../foo is rejected with exit 1" {
  # AC: path traversal ../foo は exit 1 で拒否される
  SUPERVISOR_DIR="../foo" run bash "${SCRIPT}" --type "test" --detail "traversal"
  [ "${status}" -eq 1 ]
}

@test "ac5: ../foo rejection error message contains 'invalid path:' per baseline-bash §11" {
  # AC: エラーメッセージは 'invalid path:' 形式
  # RED: 現行実装のメッセージ "must not contain '..'" は新形式と不一致 → fail
  SUPERVISOR_DIR="../foo" run bash -c "bash '${SCRIPT}' --type test --detail traversal 2>&1 >/dev/null"
  [[ "${output}" =~ "invalid path:" ]]
}

@test "ac5: foo/../bar is rejected with exit 1" {
  # AC: path traversal foo/../bar は exit 1 で拒否される
  SUPERVISOR_DIR="foo/../bar" run bash "${SCRIPT}" --type "test" --detail "embedded traversal"
  [ "${status}" -eq 1 ]
}

# ===========================================================================
# AC6: shell 特殊文字を含むパスが拒否される
# ===========================================================================

@test "ac6: \$foo is rejected with exit 1" {
  # AC: $foo は exit 1 で拒否される
  SUPERVISOR_DIR='$foo' run bash "${SCRIPT}" --type "test" --detail "dollar sign"
  [ "${status}" -eq 1 ]
}

@test "ac6: \$foo rejection error message contains 'invalid path:' per baseline-bash §11" {
  # AC: エラーメッセージは 'invalid path:' 形式
  # RED: 現行実装のメッセージ "must only contain allowed characters" は新形式と不一致 → fail
  SUPERVISOR_DIR='$foo' run bash -c "bash '${SCRIPT}' --type test --detail 'special char' 2>&1 >/dev/null"
  [[ "${output}" =~ "invalid path:" ]]
}

@test "ac6: a;b is rejected with exit 1" {
  # AC: セミコロンを含むパスは拒否される
  SUPERVISOR_DIR='a;b' run bash "${SCRIPT}" --type "test" --detail "semicolon"
  [ "${status}" -eq 1 ]
}

@test "ac6: a|b is rejected with exit 1" {
  # AC: パイプを含むパスは拒否される
  SUPERVISOR_DIR='a|b' run bash "${SCRIPT}" --type "test" --detail "pipe"
  [ "${status}" -eq 1 ]
}

@test "ac6: a\`b is rejected with exit 1" {
  # AC: バッククォートを含むパスは拒否される
  SUPERVISOR_DIR='a`b' run bash "${SCRIPT}" --type "test" --detail "backtick"
  [ "${status}" -eq 1 ]
}

@test "ac6: a&b is rejected with exit 1" {
  # AC: アンパサンドを含むパスは拒否される
  SUPERVISOR_DIR='a&b' run bash "${SCRIPT}" --type "test" --detail "ampersand"
  [ "${status}" -eq 1 ]
}

@test "ac6: a(b is rejected with exit 1" {
  # AC: 括弧を含むパスは拒否される
  SUPERVISOR_DIR='a(b' run bash "${SCRIPT}" --type "test" --detail "paren"
  [ "${status}" -eq 1 ]
}

@test "ac6: a<b is rejected with exit 1" {
  # AC: 不等号 < を含むパスは拒否される
  SUPERVISOR_DIR='a<b' run bash "${SCRIPT}" --type "test" --detail "less-than"
  [ "${status}" -eq 1 ]
}

@test "ac6: a>b is rejected with exit 1" {
  # AC: 不等号 > を含むパスは拒否される
  SUPERVISOR_DIR='a>b' run bash "${SCRIPT}" --type "test" --detail "greater-than"
  [ "${status}" -eq 1 ]
}

# ===========================================================================
# AC7: 空文字 / 未定義 SUPERVISOR_DIR で .supervisor フォールバックが受理される
# ===========================================================================

@test "ac7: unset SUPERVISOR_DIR falls back to .supervisor and is accepted" {
  # AC: SUPERVISOR_DIR 未設定時は .supervisor にフォールバックし受理される
  # PASS 可能性あり（現行実装でも動作する）
  unset SUPERVISOR_DIR
  run bash "${SCRIPT}" --type "fallback-test" --detail "unset supervisor dir"
  [ "${status}" -eq 0 ]
}

@test "ac7: empty SUPERVISOR_DIR falls back to .supervisor and is accepted" {
  # AC: SUPERVISOR_DIR="" のとき .supervisor フォールバックが受理される
  # PASS 可能性あり（${SUPERVISOR_DIR:-.supervisor} で空文字もフォールバック）
  SUPERVISOR_DIR="" run bash "${SCRIPT}" --type "fallback-test" --detail "empty supervisor dir"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8: 既存テストファイルが存在する（回帰参照）
# ===========================================================================

@test "ac8: regression test file record-detection-gap.bats exists" {
  # AC: 既存テストが引き続き PASS できる前提としてテストファイルが存在する
  [ -f "${REPO_ROOT}/tests/bats/observer/record-detection-gap.bats" ]
}

@test "ac8: regression test file issue-1250-record-detection-gap-flock.bats exists" {
  [ -f "${REPO_ROOT}/tests/bats/issue-1250-record-detection-gap-flock.bats" ]
}

@test "ac8: regression test file record-detection-gap-deps-registered.bats exists" {
  [ -f "${REPO_ROOT}/tests/bats/scripts/record-detection-gap-deps-registered.bats" ]
}

# ===========================================================================
# AC9: `# allowlist regex per baseline-bash §11` コメントが script に存在する
# ===========================================================================

@test "ac9: script contains comment '# allowlist regex per baseline-bash §11'" {
  # AC: 修正コードに '# allowlist regex per baseline-bash §11' コメントが存在する
  # RED: 実装前は存在しないため fail
  run grep -qF '# allowlist regex per baseline-bash §11' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC10: baseline-bash.md §11 セクションが存在し、棚卸し表からエントリが削除されている
# ===========================================================================

@test "ac10: baseline-bash.md has a section 11 for allowlist approach" {
  # AC: baseline-bash.md §11 「blocklist 方式の棚卸し」が存在する
  # RED: 現在 §1-§10 しか存在しないため fail
  run grep -qE '^## 11\.' "${BASELINE_BASH}"
  [ "${status}" -eq 0 ]
}

@test "ac10: baseline-bash.md §11 table does not contain record-detection-gap.sh entry" {
  # AC: §11 テーブルから record-detection-gap.sh の行が削除されている
  # RED: §11 が存在しないため前提 fail → false で明示的に fail
  if ! grep -qE '^## 11\.' "${BASELINE_BASH}"; then
    false  # §11 未存在 → fail
  fi
  run grep -qF 'record-detection-gap.sh' "${BASELINE_BASH}"
  [ "${status}" -ne 0 ]
}
