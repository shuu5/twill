#!/usr/bin/env bats
# baseline-bash-section12.bats - Verify Issue #1451: baseline-bash.md に
# ## 12. bats 非インタラクティブ SIGINT 送信 セクションが追加されていること
# RED: §12 はまだ存在しないため全テストが FAIL する

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  BASELINE="${REPO_ROOT}/refs/baseline-bash.md"
  export REPO_ROOT BASELINE
}

# ===========================================================================
# AC1: ## 12. bats 非インタラクティブ SIGINT 送信 セクションが §11 の直後に存在する
# ===========================================================================

@test "baseline-bash-section12: AC1 section '## 12.' exists" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 12\.' "${BASELINE}"
}

@test "baseline-bash-section12: AC1 section heading includes 'SIGINT'" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 12\..*SIGINT' "${BASELINE}"
}

@test "baseline-bash-section12: AC1 section heading includes 'bats'" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 12\..*bats' "${BASELINE}"
}

@test "baseline-bash-section12: AC1 §12 appears after §11 in file" {
  [ -f "${BASELINE}" ]
  local line_11 line_12
  line_11=$(grep -n '^## 11\.' "${BASELINE}" | head -1 | cut -d: -f1)
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_11}" ]
  [ -n "${line_12}" ]
  [ "${line_12}" -gt "${line_11}" ]
}

# ===========================================================================
# AC2: §12 は推奨パターンの核心要素を含む
# - set -m (job control) の説明
# - kill -INT -$pgid (プロセスグループ指定) のパターン
# - trap 'set +m' RETURN によるスコープ漏れ防止
# - pgid 数値検証による空文字 kill 事故防止
# ===========================================================================

@test "baseline-bash-section12: AC2 mentions 'set -m'" {
  [ -f "${BASELINE}" ]
  local line_12
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_12}" ]
  tail -n +"${line_12}" "${BASELINE}" | grep -qF 'set -m'
}

@test "baseline-bash-section12: AC2 mentions 'kill -INT' with process group" {
  [ -f "${BASELINE}" ]
  local line_12
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_12}" ]
  tail -n +"${line_12}" "${BASELINE}" | grep -qE 'kill -INT.*-\$pgid|kill.*-INT.*pgid'
}

@test "baseline-bash-section12: AC2 mentions 'trap' for set +m cleanup" {
  [ -f "${BASELINE}" ]
  local line_12
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_12}" ]
  tail -n +"${line_12}" "${BASELINE}" | grep -qE "trap.*set \+m|trap.*RETURN"
}

@test "baseline-bash-section12: AC2 includes pgid numeric validation" {
  [ -f "${BASELINE}" ]
  local line_12
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_12}" ]
  tail -n +"${line_12}" "${BASELINE}" | grep -qE '\^\[1-9\]\[0-9\]\*\$|pgid.*=~.*\^.*\[0-9\]'
}

# ===========================================================================
# AC3: §12 は BAD/GOOD ブロック構造を持つ（既存セクションのパターンに準拠）
# ===========================================================================

@test "baseline-bash-section12: AC3 has BAD block for kill -INT without process group" {
  [ -f "${BASELINE}" ]
  local line_12
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_12}" ]
  tail -n +"${line_12}" "${BASELINE}" | grep -qE '^### BAD:|^#### BAD'
}

@test "baseline-bash-section12: AC3 has GOOD block with recommended pattern" {
  [ -f "${BASELINE}" ]
  local line_12
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_12}" ]
  tail -n +"${line_12}" "${BASELINE}" | grep -qE '^### GOOD:|^#### GOOD'
}

# ===========================================================================
# AC4: §12 はトリガー条件（POSIX 規定）の説明を含む
# bats 非インタラクティブシェルでは SIGINT が SIG_IGN になる原因
# ===========================================================================

@test "baseline-bash-section12: AC4 mentions non-interactive shell or POSIX constraint" {
  [ -f "${BASELINE}" ]
  local line_12
  line_12=$(grep -n '^## 12\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_12}" ]
  tail -n +"${line_12}" "${BASELINE}" | grep -qE '非インタラクティブ|non-interactive|SIG_IGN|POSIX'
}
