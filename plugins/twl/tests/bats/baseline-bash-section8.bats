#!/usr/bin/env bats
# baseline-bash-section8.bats - Verify Issue #1143: baseline-bash.md に
# ## 8. tmux 破壊的操作のターゲット解決 セクションが追加されていること
# RED: §8 はまだ存在しないため全テストが FAIL する

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  BASELINE="${REPO_ROOT}/refs/baseline-bash.md"
  export REPO_ROOT BASELINE
}

# ===========================================================================
# AC2: ## 8. tmux 破壊的操作のターゲット解決 セクションが §7 の直後に存在する
# ===========================================================================

@test "baseline-bash-section8: AC2 section '## 8. tmux' exists" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 8\.' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 section heading includes 'tmux'" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 8\..*tmux' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 section heading includes '破壊的操作'" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 8\..*破壊的操作' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 §8 appears after §7 in file" {
  [ -f "${BASELINE}" ]
  local line_7 line_8
  line_7=$(grep -n '^## 7\.' "${BASELINE}" | head -1 | cut -d: -f1)
  line_8=$(grep -n '^## 8\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_7}" ]
  [ -n "${line_8}" ]
  [ "${line_8}" -gt "${line_7}" ]
}

# ===========================================================================
# AC2: §8 は必要な構造要素を持つ
# - BAD: window_name を直接 -t に渡す
# - GOOD: session:index 形式に解決してから渡す
# - tmux list-windows -a で解決する方法
# - pitfalls-catalog §4.11 への参照
# - tmux-resolve.sh への参照
# ===========================================================================

@test "baseline-bash-section8: AC2 section mentions 'kill-window' or 'kill-session'" {
  [ -f "${BASELINE}" ]
  grep -qE 'kill-window|kill-session|respawn-window' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 BAD block heading exists for tmux target" {
  [ -f "${BASELINE}" ]
  grep -qE '### BAD:.*tmux|### BAD:.*window_name|### BAD:.*-t.*window' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 GOOD block heading exists for tmux target" {
  [ -f "${BASELINE}" ]
  grep -qE '### GOOD:.*session:index|### GOOD:.*list-windows|### GOOD:.*tmux-resolve' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 section mentions 'list-windows'" {
  [ -f "${BASELINE}" ]
  grep -qE 'list-windows' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 section mentions 'session:index' format or 'session_name:'" {
  [ -f "${BASELINE}" ]
  grep -qE 'session:index|session_name.*window_index|#{session_name}' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 section mentions 'ambiguous target' or '誤 kill'" {
  [ -f "${BASELINE}" ]
  grep -qE 'ambiguous target|誤 kill|誤kill|ambiguous' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 section references pitfalls-catalog §4.11" {
  [ -f "${BASELINE}" ]
  grep -qE '4\.11|pitfalls.*catalog' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 section references tmux-resolve.sh" {
  [ -f "${BASELINE}" ]
  grep -qE 'tmux-resolve\.sh|tmux-resolve' "${BASELINE}"
}

@test "baseline-bash-section8: AC2 review observation line present in §8 context" {
  [ -f "${BASELINE}" ]
  local section8_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section8_start=$(grep -n '^## 8\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section8_start}" ]
  local next_section
  next_section=$(awk -v start="${section8_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section8_start}" -v e="${next_section}" 'NR >= s && NR <= e && /レビュー観点/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

# ===========================================================================
# AC5: §1–§7 の heading が §8 追加後も変更されていない（regression）
# ===========================================================================

@test "baseline-bash-section8: AC5 regression §1 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 1. Character Class のハイフン配置' "${BASELINE}"
}

@test "baseline-bash-section8: AC5 regression §2 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 2. for-loop 変数の local 宣言' "${BASELINE}"
}

@test "baseline-bash-section8: AC5 regression §3 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 3. local 宣言の set -u 初期化' "${BASELINE}"
}

@test "baseline-bash-section8: AC5 regression §4 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 4. 環境変数パースの IFS 問題' "${BASELINE}"
}

@test "baseline-bash-section8: AC5 regression §5 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 5. source スクリプトの set -e 制約' "${BASELINE}"
}

@test "baseline-bash-section8: AC5 regression §6 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 6. 複数 regex パターンの ^ アンカー一貫性' "${BASELINE}"
}

@test "baseline-bash-section8: AC5 regression §7 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 7\. recursive glob' "${BASELINE}"
}

@test "baseline-bash-section8: AC5 sections §1-§8 all present and consecutive" {
  [ -f "${BASELINE}" ]
  local count
  count=$(grep -cE '^## [1-8]\.' "${BASELINE}")
  [ "${count}" -eq 8 ]
}

# ===========================================================================
# AC5: twl check --deps-integrity が PASS する
# ===========================================================================

@test "baseline-bash-section8: AC5 twl check --deps-integrity passes" {
  run bash -c "cd '${REPO_ROOT}' && twl check --deps-integrity"
  [ "${status}" -eq 0 ]
}
