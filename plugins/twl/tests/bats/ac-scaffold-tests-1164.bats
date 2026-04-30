#!/usr/bin/env bats
# ac-scaffold-tests-1164.bats - Issue #1164: ac-scaffold-tests.md に bats heredoc/source
# guard チェック記述を追加し、baseline-bash.md に §9/§10 を追加することの RED テスト。
# RED: 実装前は全テストが FAIL する。

load 'helpers/common'

setup() {
  common_setup
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  AGENT_FILE="${REPO_ROOT}/agents/ac-scaffold-tests.md"
  BASELINE="${REPO_ROOT}/refs/baseline-bash.md"
  export REPO_ROOT AGENT_FILE BASELINE
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: ac-scaffold-tests.md に bats heredoc quote 形式の使い分けルールが記述されている
# ===========================================================================

@test "ac-scaffold-tests-1164: AC1 agent file exists" {
  # AC: ac-scaffold-tests.md が存在する
  [ -f "${AGENT_FILE}" ]
}

@test "ac-scaffold-tests-1164: AC1 heredoc or MOCKEOF or シングルクォート keyword present" {
  # AC: grep -E "heredoc|<<.MOCKEOF|シングルクォート" の結果がコメント行を除いて 1 件以上
  # RED: 現在 ac-scaffold-tests.md にこれらのキーワードが存在しない
  local count
  count=$(grep -E "heredoc|<<.MOCKEOF|シングルクォート" "${AGENT_FILE}" | grep -v '^#' | wc -l)
  [ "${count}" -ge 1 ]
}

@test "ac-scaffold-tests-1164: AC1 explanation mentions 外部変数 or parent shell or 展開されない" {
  # AC: 「外部変数」「parent shell」「展開されない」のいずれか相当の説明文が含まれる
  # RED: 現在 ac-scaffold-tests.md にこれらの説明が存在しない
  grep -qE "外部変数|parent shell|展開されない|variable expansion|not expanded" "${AGENT_FILE}"
}

@test "ac-scaffold-tests-1164: AC1 BAD or GOOD example for heredoc quoting present" {
  # AC: BAD/GOOD 例 or @refs/baseline-bash.md §9 引用が含まれる
  # RED: 現在 bats heredoc に関する BAD/GOOD 例が存在しない
  grep -qE "BAD.*heredoc|GOOD.*heredoc|<<'EOF'|<<'MOCKEOF'|@refs/baseline-bash.*§9|baseline-bash.*9\." "${AGENT_FILE}"
}

# ===========================================================================
# AC2: ac-scaffold-tests.md に source guard チェック手順が記述されている
# ===========================================================================

@test "ac-scaffold-tests-1164: AC2 BASH_SOURCE or source guard or source-only keyword present" {
  # AC: grep -E "BASH_SOURCE|source guard|--source-only|function-only|_DAEMON_LOAD_ONLY" が 1 件以上
  # RED: 現在 ac-scaffold-tests.md にこれらのキーワードが存在しない
  local count
  count=$(grep -E "BASH_SOURCE|source guard|--source-only|function-only|_DAEMON_LOAD_ONLY" "${AGENT_FILE}" | grep -v '^#' | wc -l)
  [ "${count}" -ge 1 ]
}

@test "ac-scaffold-tests-1164: AC2 explanation mentions main 到達前 return or set -euo pipefail exit" {
  # AC: 「main 到達前 return」「set -euo pipefail で exit に巻き込まれる」相当の説明が含まれる
  # RED: 現在 ac-scaffold-tests.md にこれらの説明が存在しない
  grep -qE "main 到達前|set -euo pipefail.*exit|exit に巻き込まれる|exit.*巻き込む|source.*exit|return.*main" "${AGENT_FILE}"
}

@test "ac-scaffold-tests-1164: AC2 BAD or GOOD example for source guard check present" {
  # AC: bats から source <script> を生成する前のチェック手順が BAD/GOOD 例 or §10 引用と共に記述
  # RED: 現在 source guard に関する BAD/GOOD 例が存在しない
  grep -qE 'BAD.*source|GOOD.*source|BASH_SOURCE.*==.*\$\{0\}|@refs/baseline-bash.*§10|baseline-bash.*10\.' "${AGENT_FILE}"
}

# ===========================================================================
# AC3: baseline-bash.md に §9 bats heredoc 内変数展開 セクションが追加されている
# ===========================================================================

@test "ac-scaffold-tests-1164: AC3 baseline-bash.md section '## 9.' exists" {
  # AC: grep -c "^## 9\." plugins/twl/refs/baseline-bash.md >= 1
  # RED: 現在 baseline-bash.md に §9 が存在しない
  local count
  count=$(grep -c "^## 9\." "${BASELINE}")
  [ "${count}" -ge 1 ]
}

@test "ac-scaffold-tests-1164: AC3 section heading includes 'heredoc' or 'bats' or '変数展開'" {
  # AC: §9 は bats heredoc 内変数展開 のセクション
  # RED: §9 が存在しないため fail
  grep -qE "^## 9\..*heredoc|^## 9\..*bats|^## 9\..*変数展開" "${BASELINE}"
}

@test "ac-scaffold-tests-1164: AC3 BAD block uses single-quote heredoc with external variable" {
  # AC: BAD コードブロック (<<'EOF' ... $EXT_VAR ... EOF) が含まれる
  # RED: §9 が存在しないため fail
  local section9_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section9_start=$(grep -n "^## 9\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section9_start}" ]
  local next_section
  next_section=$(awk -v start="${section9_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section9_start}" -v e="${next_section}" "NR >= s && NR <= e && /<<'EOF'|<<'MOCKEOF'/ { found=1 } END { print found+0 }" "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "ac-scaffold-tests-1164: AC3 GOOD block uses unquoted heredoc or EXT=\$EXT bash pattern" {
  # AC: GOOD コードブロック (<<EOF または EXT=$EXT bash <<'EOF') が §9 に含まれる
  # RED: §9 が存在しないため fail
  local section9_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section9_start=$(grep -n "^## 9\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section9_start}" ]
  local next_section
  next_section=$(awk -v start="${section9_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section9_start}" -v e="${next_section}" 'NR >= s && NR <= e && /<<EOF|EXT=.*bash.*<</ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "ac-scaffold-tests-1164: AC3 section §9 contains レビュー観点 paragraph" {
  # AC: §9 に「レビュー観点」段落が含まれる
  # RED: §9 が存在しないため fail
  local section9_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section9_start=$(grep -n "^## 9\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section9_start}" ]
  local next_section
  next_section=$(awk -v start="${section9_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section9_start}" -v e="${next_section}" 'NR >= s && NR <= e && /レビュー観点/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

# ===========================================================================
# AC4: baseline-bash.md に §10 source guard / function-only セクションが追加されている
# ===========================================================================

@test "ac-scaffold-tests-1164: AC4 baseline-bash.md section '## 10.' exists" {
  # AC: grep -c "^## 10\." plugins/twl/refs/baseline-bash.md >= 1
  # RED: 現在 baseline-bash.md に §10 が存在しない
  local count
  count=$(grep -c "^## 10\." "${BASELINE}")
  [ "${count}" -ge 1 ]
}

@test "ac-scaffold-tests-1164: AC4 section heading includes 'source' or 'guard' or 'function-only'" {
  # AC: §10 は source 対象スクリプトの guard / function-only load mode のセクション
  # RED: §10 が存在しないため fail
  grep -qE "^## 10\..*source|^## 10\..*guard|^## 10\..*function-only|^## 10\..*BASH_SOURCE" "${BASELINE}"
}

@test "ac-scaffold-tests-1164: AC4 BAD block in section §10 present" {
  # AC: §10 に BAD コードブロックが含まれる
  # RED: §10 が存在しないため fail
  local section10_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section10_start=$(grep -n "^## 10\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section10_start}" ]
  local next_section
  next_section=$(awk -v start="${section10_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section10_start}" -v e="${next_section}" 'NR >= s && NR <= e && /### BAD:/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "ac-scaffold-tests-1164: AC4 GOOD block in section §10 present" {
  # AC: §10 に GOOD コードブロックが含まれる
  # RED: §10 が存在しないため fail
  local section10_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section10_start=$(grep -n "^## 10\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section10_start}" ]
  local next_section
  next_section=$(awk -v start="${section10_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section10_start}" -v e="${next_section}" 'NR >= s && NR <= e && /### GOOD:/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "ac-scaffold-tests-1164: AC4 section §10 contains BASH_SOURCE guard pattern" {
  # AC: §10 に BASH_SOURCE guard または --source-only 相当のパターンが含まれる
  # RED: §10 が存在しないため fail
  local section10_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section10_start=$(grep -n "^## 10\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section10_start}" ]
  local next_section
  next_section=$(awk -v start="${section10_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section10_start}" -v e="${next_section}" 'NR >= s && NR <= e && /BASH_SOURCE|source-only|function.only|_DAEMON_LOAD_ONLY/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "ac-scaffold-tests-1164: AC4 section §10 contains レビュー観点 paragraph" {
  # AC: §10 に「レビュー観点」段落が含まれる
  # RED: §10 が存在しないため fail
  local section10_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section10_start=$(grep -n "^## 10\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section10_start}" ]
  local next_section
  next_section=$(awk -v start="${section10_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section10_start}" -v e="${next_section}" 'NR >= s && NR <= e && /レビュー観点/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "ac-scaffold-tests-1164: AC4 §10 appears after §9 in file" {
  # AC: §10 は §9 の直後に存在する
  # RED: §9/§10 が存在しないため fail
  local line_9 line_10
  line_9=$(grep -n "^## 9\." "${BASELINE}" | head -1 | cut -d: -f1)
  line_10=$(grep -n "^## 10\." "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_9}" ]
  [ -n "${line_10}" ]
  [ "${line_10}" -gt "${line_9}" ]
}

# ===========================================================================
# AC5: twl check が全て PASS する
# ===========================================================================

@test "ac-scaffold-tests-1164: AC5 twl check --deps-integrity passes" {
  # AC: twl check --deps-integrity が PASS する
  # RED: 実装変更が未完了の場合 fail する可能性があるが、deps 整合性は現時点で PASS のはず
  run bash -c "cd '${REPO_ROOT}' && twl check --deps-integrity"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# リグレッション: §1–§8 heading が変更されていないこと
# ===========================================================================

@test "ac-scaffold-tests-1164: regression §1 heading unchanged" {
  grep -qF '## 1. Character Class のハイフン配置' "${BASELINE}"
}

@test "ac-scaffold-tests-1164: regression §2 heading unchanged" {
  grep -qF '## 2. for-loop 変数の local 宣言' "${BASELINE}"
}

@test "ac-scaffold-tests-1164: regression §3 heading unchanged" {
  grep -qF '## 3. local 宣言の set -u 初期化' "${BASELINE}"
}

@test "ac-scaffold-tests-1164: regression §4 heading unchanged" {
  grep -qF '## 4. 環境変数パースの IFS 問題' "${BASELINE}"
}

@test "ac-scaffold-tests-1164: regression §5 heading unchanged" {
  grep -qF '## 5. source スクリプトの set -e 制約' "${BASELINE}"
}

@test "ac-scaffold-tests-1164: regression §6 heading unchanged" {
  grep -qF '## 6. 複数 regex パターンの ^ アンカー一貫性' "${BASELINE}"
}

@test "ac-scaffold-tests-1164: regression §7 heading unchanged" {
  grep -qE '^## 7\. recursive glob' "${BASELINE}"
}

@test "ac-scaffold-tests-1164: regression §8 heading unchanged" {
  grep -qE '^## 8\. tmux' "${BASELINE}"
}
