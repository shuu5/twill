#!/usr/bin/env bats
# issue-1391-record-detection-gap-sanitize.bats
#
# RED-phase tests for Issue #1391:
#   tech-debt(su-observer): record-detection-gap.sh の未サニタイズ引数出力（L38 / L56）
#
# AC coverage:
#   AC-1: L38 の $1（未知引数名）が改行インジェクションに対してサニタイズされる
#         $'--foo\nFAKE LOG' のような引数でも stderr にログ汚染が発生しない
#   AC-2: L38 の echo "ERROR: Unknown argument: $1" が printf '%q' 形式に置換される（静的確認）
#   AC-3: L56 の $SEVERITY が改行インジェクションに対してサニタイズされる
#         $'low\nFAKE LOG' のような値でも stderr にログ汚染が発生しない
#   AC-4: L56 の echo "ERROR: ... (got: $SEVERITY)" が printf '%q' 形式に置換される（静的確認）
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-detection-gap.sh"
  export SCRIPT

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
  cd "${TMPDIR_TEST}"
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC-1: L38 の $1（未知引数）が改行インジェクションに対してサニタイズされる（動的確認）
# ===========================================================================

@test "ac1: L38 unknown-arg — newline-injected arg does not produce injected line in stderr" {
  # AC: $1 が printf '%q' でサニタイズされ、改行インジェクションが発生しない
  # RED: 現行実装 echo "ERROR: Unknown argument: $1" は改行を展開し "FAKE LOG" が別行に出力される
  local stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "${SCRIPT}" $'--unknown-flag\nFAKE LOG' --type test --detail test \
    2>"${stderr_file}" || true
  run grep -Fx 'FAKE LOG' "${stderr_file}"
  [ "${status}" -ne 0 ]
}

@test "ac1: L38 unknown-arg — normal error prefix still appears in stderr after sanitize" {
  # AC: サニタイズ後も 'ERROR:' プレフィックスが stderr に出力される（既存動作保持）
  # PASS 可能性あり（修正前後どちらも ERROR: が出力される）
  local stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "${SCRIPT}" '--unknown-flag-1391' --type test --detail test \
    2>"${stderr_file}" || true
  run grep -qF 'ERROR:' "${stderr_file}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-2: L38 の echo が printf '%q' 形式に置換される（静的確認）
# ===========================================================================

@test "ac2: L38 raw echo 'ERROR: Unknown argument:' has been replaced — not using unquoted echo" {
  # AC: L38 の echo "ERROR: Unknown argument: \$1" が printf '%q' 形式に変更される
  # RED: 現行実装は echo を使用しているため fail
  run grep -qF 'echo "ERROR: Unknown argument:' "${SCRIPT}"
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC-3: L56 の $SEVERITY が改行インジェクションに対してサニタイズされる（動的確認）
# ===========================================================================

@test "ac3: L56 severity — newline-injected severity does not produce injected line in stderr" {
  # AC: $SEVERITY が printf '%q' またはバリデーション前サニタイズでサニタイズされる
  # RED: 現行実装 echo "...got: $SEVERITY)" は改行展開し "FAKE LOG)" が行頭から始まる → fail
  # NOTE: echo "...(got: $SEVERITY)" の末尾 ")" により行末は "FAKE LOG)" となるため
  #       grep -E '^FAKE LOG' で行頭マッチを使用
  local stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "${SCRIPT}" --type test --detail test --severity $'low\nFAKE LOG' \
    2>"${stderr_file}" || true
  run grep -E '^FAKE LOG' "${stderr_file}"
  [ "${status}" -ne 0 ]
}

@test "ac3: L56 severity — error message still mentions expected values after sanitize" {
  # AC: サニタイズ後も 'low|medium|high' が stderr に出力される（既存動作保持）
  # PASS 可能性あり（修正前後どちらも low|medium|high が出力される）
  local stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "${SCRIPT}" --type test --detail test --severity 'invalid-severity-1391' \
    2>"${stderr_file}" || true
  run grep -qF 'low|medium|high' "${stderr_file}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-4: L56 の echo "...(got: $SEVERITY)" が printf '%q' 形式に置換される（静的確認）
# ===========================================================================

@test "ac4: L56 raw echo 'got: \$SEVERITY' has been replaced — not using unquoted echo" {
  # AC: L56 の echo "ERROR: --severity must be low|medium|high (got: \$SEVERITY)" が変更される
  # RED: 現行実装は echo を使用しているため fail
  run grep -qF 'got: $SEVERITY' "${SCRIPT}"
  [ "${status}" -ne 0 ]
}
