#!/usr/bin/env bats
# baseline-bash-section7.bats - Verify Issue #1090: baseline-bash.md に
# ## 7. recursive glob (**) と globstar 設定 セクションが追加されていること

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  BASELINE="${REPO_ROOT}/refs/baseline-bash.md"
  export REPO_ROOT BASELINE
}

# ===========================================================================
# AC1: ## 7. recursive glob (**) と globstar 設定 セクションが §6 の直後に存在する
# ===========================================================================

@test "baseline-bash-section7: AC1 section '## 7. recursive glob' exists" {
  [ -f "${BASELINE}" ]
  grep -qF '## 7. recursive glob' "${BASELINE}"
}

@test "baseline-bash-section7: AC1 section heading includes 'globstar'" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 7\..*globstar' "${BASELINE}"
}

@test "baseline-bash-section7: AC1 §7 appears after §6 in file" {
  [ -f "${BASELINE}" ]
  local line_6 line_7
  line_6=$(grep -n '^## 6\.' "${BASELINE}" | head -1 | cut -d: -f1)
  line_7=$(grep -n '^## 7\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_6}" ]
  [ -n "${line_7}" ]
  [ "${line_7}" -gt "${line_6}" ]
}

# ===========================================================================
# AC2: §7 は必要な構造要素を持つ
# - 説明段落（shopt -s globstar 未設定 + set -euo pipefail サイレント失敗）
# - **Why** (Issue #1081 / tech-stack-detect.sh:54 / commit 6d9bffa):
# - ### BAD: globstar 未設定で **/*.ext を使う
# - ### GOOD: --include で再帰検索を明示する
# - GOOD 代替策（find または shopt -s globstar 局所化）
# - **レビュー観点**:
# ===========================================================================

@test "baseline-bash-section7: AC2 description mentions 'shopt -s globstar'" {
  [ -f "${BASELINE}" ]
  grep -qE 'shopt -s globstar' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 description mentions 'set -euo pipefail' and silent failure" {
  [ -f "${BASELINE}" ]
  grep -qE 'set -euo pipefail' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 Why note references Issue #1081" {
  [ -f "${BASELINE}" ]
  grep -qE '\*\*Why\*\*.*#1081|#1081.*tech-stack-detect' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 Why note references commit 6d9bffa" {
  [ -f "${BASELINE}" ]
  grep -qE '6d9bffa' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 BAD block heading exists" {
  [ -f "${BASELINE}" ]
  grep -qF '### BAD: globstar' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 BAD block contains '**/*.py' pattern" {
  [ -f "${BASELINE}" ]
  grep -qF '**/*.py' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 GOOD block '--include' heading exists" {
  [ -f "${BASELINE}" ]
  grep -qF '### GOOD: ' "${BASELINE}"
  grep -qE '### GOOD:.*--include|--include.*で再帰' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 GOOD block contains '--include' grep example" {
  [ -f "${BASELINE}" ]
  grep -qE "grep.*--include='\*\.py'" "${BASELINE}"
}

@test "baseline-bash-section7: AC2 alternative GOOD strategy present (find or shopt)" {
  [ -f "${BASELINE}" ]
  grep -qE 'find.*-name.*\*\.py|shopt -s globstar nullglob' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 review observation line present" {
  [ -f "${BASELINE}" ]
  grep -qE '^\*\*レビュー観点\*\*:' "${BASELINE}"
}

@test "baseline-bash-section7: AC2 review observation mentions VAR/**/*.ext pattern check" {
  [ -f "${BASELINE}" ]
  grep -qE '\$VAR/\*\*/\*\.ext|\*\*/\*\.' "${BASELINE}"
}

# ===========================================================================
# AC3: §7 の説明文に set -euo pipefail 前提が明記されている
# ===========================================================================

@test "baseline-bash-section7: AC3 set -euo pipefail mentioned in §7 context" {
  [ -f "${BASELINE}" ]
  # Already covered by AC2, but verify it's in §7 section specifically
  local section7_start section7_end total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section7_start=$(grep -n '^## 7\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section7_start}" ]
  # Check within the section (from §7 start to end of file or next §8)
  local next_section
  next_section=$(awk -v start="${section7_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section7_start}" -v e="${next_section}" 'NR >= s && NR <= e && /set -euo pipefail/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

# ===========================================================================
# AC4: regression — 既存 §1–§6 の heading 階層が変更されていない
# ===========================================================================

@test "baseline-bash-section7: AC4 regression §1 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 1. Character Class のハイフン配置' "${BASELINE}"
}

@test "baseline-bash-section7: AC4 regression §2 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 2. for-loop 変数の local 宣言' "${BASELINE}"
}

@test "baseline-bash-section7: AC4 regression §3 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 3. local 宣言の set -u 初期化' "${BASELINE}"
}

@test "baseline-bash-section7: AC4 regression §4 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 4. 環境変数パースの IFS 問題' "${BASELINE}"
}

@test "baseline-bash-section7: AC4 regression §5 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 5. source スクリプトの set -e 制約' "${BASELINE}"
}

@test "baseline-bash-section7: AC4 regression §6 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 6. 複数 regex パターンの ^ アンカー一貫性' "${BASELINE}"
}

@test "baseline-bash-section7: AC4 sections §1-§7 all present and consecutive" {
  [ -f "${BASELINE}" ]
  local count
  count=$(grep -cE '^## [1-7]\.' "${BASELINE}")
  [ "${count}" -eq 7 ]
}

# ===========================================================================
# AC5: frontmatter が変更されていない
# ===========================================================================

@test "baseline-bash-section7: AC5 frontmatter name field unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF 'name: twl:baseline-bash' "${BASELINE}"
}

@test "baseline-bash-section7: AC5 frontmatter type field unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF 'type: reference' "${BASELINE}"
}

@test "baseline-bash-section7: AC5 frontmatter disable-model-invocation unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF 'disable-model-invocation: true' "${BASELINE}"
}

# ===========================================================================
# AC6: twl check --deps-integrity が PASS する（baseline-bash.md は ref 型）
# ===========================================================================

@test "baseline-bash-section7: AC6 twl check --deps-integrity passes" {
  run bash -c "cd '${REPO_ROOT}' && twl check --deps-integrity"
  [ "${status}" -eq 0 ]
}
