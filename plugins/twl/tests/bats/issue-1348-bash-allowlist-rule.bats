#!/usr/bin/env bats
# issue-1348-bash-allowlist-rule.bats - Issue #1348: baseline-bash.md に bash 入力検証の
# allowlist regex 規約セクション（§11）を追加する
#
# RED フェーズ: §11 はまだ存在しないため全テストが FAIL する

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  BASELINE="${REPO_ROOT}/refs/baseline-bash.md"
  SECURITY_CHECKLIST="${REPO_ROOT}/refs/baseline-security-checklist.md"
  SPAWN_CONTROLLER="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  export REPO_ROOT BASELINE SECURITY_CHECKLIST SPAWN_CONTROLLER
}

# ===========================================================================
# AC1: §11 allowlist regex 規約セクションが baseline-bash.md に存在する
# ===========================================================================

@test "issue-1348-bash-allowlist-rule: AC1 section '## 11.' exists in baseline-bash.md" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 11\.' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC1 section heading mentions allowlist or allow-list" {
  [ -f "${BASELINE}" ]
  grep -qiE '^## 11\..*allow.?list' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC1 section heading mentions regex or 正規表現" {
  [ -f "${BASELINE}" ]
  grep -qiE '^## 11\..*regex|^## 11\..*正規表現|^## 11\..*バリデーション|^## 11\..*入力検証' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC1 §11 appears after §10 in file" {
  [ -f "${BASELINE}" ]
  local line_10 line_11
  line_10=$(grep -n '^## 10\.' "${BASELINE}" | head -1 | cut -d: -f1)
  line_11=$(grep -n '^## 11\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${line_10}" ]
  [ -n "${line_11}" ]
  [ "${line_11}" -gt "${line_10}" ]
}

# ===========================================================================
# AC2: パターン例と blocklist 比較の記述が §11 内に存在する
# ===========================================================================

@test "issue-1348-bash-allowlist-rule: AC2 numeric pattern example present (^[1-9][0-9]*\$)" {
  [ -f "${BASELINE}" ]
  grep -qF '^[1-9][0-9]*$' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC2 safe-path pattern example present (^[A-Za-z0-9._/-]+\$)" {
  [ -f "${BASELINE}" ]
  grep -qF '^[A-Za-z0-9._/-]+$' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC2 enum pattern example present (case ... in)" {
  [ -f "${BASELINE}" ]
  # §11 内に case ... in による列挙バリデーション例が存在すること
  local section11_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section11_start=$(grep -n '^## 11\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section11_start}" ]
  local next_section
  next_section=$(awk -v start="${section11_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section11_start}" -v e="${next_section}" \
    'NR >= s && NR <= e && /case.*in|foo\|bar/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "issue-1348-bash-allowlist-rule: AC2 fail-closed benefit mentioned" {
  [ -f "${BASELINE}" ]
  grep -qiE 'fail.closed|fail_closed' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC2 blocklist comparison mentioned (境界値 or blocklist)" {
  [ -f "${BASELINE}" ]
  grep -qiE 'blocklist|block.list|境界値|denylist|deny.list' "${BASELINE}"
}

# ===========================================================================
# AC3: spawn-controller.sh の prior art への引用が §11 内に存在する
# ===========================================================================

@test "issue-1348-bash-allowlist-rule: AC3 spawn-controller.sh referenced in baseline-bash.md" {
  [ -f "${BASELINE}" ]
  grep -qE 'spawn-controller\.sh' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC3 CHAIN_ISSUE regex validation referenced" {
  [ -f "${BASELINE}" ]
  grep -qE 'CHAIN_ISSUE' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC3 VALID_SKILLS array check referenced" {
  [ -f "${BASELINE}" ]
  grep -qE 'VALID_SKILLS' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: AC3 spawn-controller.sh CHAIN_ISSUE regex exists at expected line in source" {
  # prior art として参照されるバリデーションが spawn-controller.sh L167 付近に実在すること
  [ -f "${SPAWN_CONTROLLER}" ]
  grep -qE 'CHAIN_ISSUE.*\^\[1-9\]\[0-9\]\*\$|\^\[1-9\]\[0-9\]\*\$.*CHAIN_ISSUE' "${SPAWN_CONTROLLER}"
}

@test "issue-1348-bash-allowlist-rule: AC3 spawn-controller.sh VALID_SKILLS array exists in source" {
  # prior art として参照される配列チェックが spawn-controller.sh に実在すること
  [ -f "${SPAWN_CONTROLLER}" ]
  grep -qE 'VALID_SKILLS=' "${SPAWN_CONTROLLER}"
}

# ===========================================================================
# AC4: baseline-security-checklist.md に bash 入力検証セクション or cross-link が存在する
# ===========================================================================

@test "issue-1348-bash-allowlist-rule: AC4 bash 入力検証 section exists in security checklist" {
  [ -f "${SECURITY_CHECKLIST}" ]
  grep -qiE '^##.*bash.*入力検証|^##.*bash.*input.validat|^##.*bash.*allowlist' "${SECURITY_CHECKLIST}"
}

@test "issue-1348-bash-allowlist-rule: AC4 cross-link to baseline-bash.md exists in security checklist" {
  [ -f "${SECURITY_CHECKLIST}" ]
  grep -qE 'baseline-bash\.md|baseline-bash' "${SECURITY_CHECKLIST}"
}

@test "issue-1348-bash-allowlist-rule: AC4 allowlist reference exists in security checklist" {
  [ -f "${SECURITY_CHECKLIST}" ]
  grep -qiE 'allowlist|allow.list' "${SECURITY_CHECKLIST}"
}

@test "issue-1348-bash-allowlist-rule: AC4 cross-reference to path traversal section present" {
  # bash 固有セクションがパストラバーサル節と相互参照すること
  [ -f "${SECURITY_CHECKLIST}" ]
  grep -qiE 'パストラバーサル|path.traversal' "${SECURITY_CHECKLIST}"
  # セキュリティチェックリスト内に allowlist への参照とパストラバーサルへの言及が共存する
  local has_allowlist has_path_traversal
  has_allowlist=$(grep -ciE 'allowlist|allow.list' "${SECURITY_CHECKLIST}")
  has_path_traversal=$(grep -ciE 'パストラバーサル|path.traversal' "${SECURITY_CHECKLIST}")
  [ "${has_allowlist}" -gt 0 ]
  [ "${has_path_traversal}" -gt 0 ]
}

# ===========================================================================
# AC5: NOTE のみ（follow-up Issue 起票はファイルコンテンツで検証困難）
# NOTE: AC5 は本テストファイルではカバーしない。Issue #1348 の AC5 は
#       別途 GitHub Issue 起票またはコメント記録にて完了確認する。
# ===========================================================================

# ===========================================================================
# AC6: §11 内に棚卸し結果（blocklist 方式の箇所リスト）が記録されている
# ===========================================================================

@test "issue-1348-bash-allowlist-rule: AC6 blocklist inventory section exists in baseline-bash.md §11" {
  [ -f "${BASELINE}" ]
  local section11_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section11_start=$(grep -n '^## 11\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section11_start}" ]
  local next_section
  next_section=$(awk -v start="${section11_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section11_start}" -v e="${next_section}" \
    'NR >= s && NR <= e && /棚卸し|blocklist.*箇所|blocklist.*一覧|blocklist.*リスト|inventory/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "issue-1348-bash-allowlist-rule: AC6 at least one blocklist script path recorded in §11" {
  [ -f "${BASELINE}" ]
  local section11_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section11_start=$(grep -n '^## 11\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section11_start}" ]
  local next_section
  next_section=$(awk -v start="${section11_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  # plugins/twl/scripts/ または skills/*/scripts/ 配下のパスが記録されている
  local found
  found=$(awk -v s="${section11_start}" -v e="${next_section}" \
    'NR >= s && NR <= e && /plugins\/twl\/(scripts|skills)/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

@test "issue-1348-bash-allowlist-rule: AC6 レビュー観点 line present in §11" {
  [ -f "${BASELINE}" ]
  local section11_start total_lines
  total_lines=$(wc -l < "${BASELINE}")
  section11_start=$(grep -n '^## 11\.' "${BASELINE}" | head -1 | cut -d: -f1)
  [ -n "${section11_start}" ]
  local next_section
  next_section=$(awk -v start="${section11_start}" 'NR > start && /^## [0-9]+\./ { print NR; exit }' "${BASELINE}")
  if [ -z "${next_section}" ]; then
    next_section="${total_lines}"
  fi
  local found
  found=$(awk -v s="${section11_start}" -v e="${next_section}" \
    'NR >= s && NR <= e && /レビュー観点/ { found=1 } END { print found+0 }' "${BASELINE}")
  [ "${found}" -eq 1 ]
}

# ===========================================================================
# regression: §1–§10 のヘッディングが変わっていない
# ===========================================================================

@test "issue-1348-bash-allowlist-rule: regression §1 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 1. Character Class のハイフン配置' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §2 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 2. for-loop 変数の local 宣言' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §3 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 3. local 宣言の set -u 初期化' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §4 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 4. 環境変数パースの IFS 問題' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §5 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 5. source スクリプトの set -e 制約' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §6 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qF '## 6. 複数 regex パターンの ^ アンカー一貫性' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §7 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 7\. recursive glob' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §8 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 8\. tmux 破壊的操作のターゲット解決' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §9 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 9\. bats heredoc 内変数展開' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §10 heading unchanged" {
  [ -f "${BASELINE}" ]
  grep -qE '^## 10\. source 対象スクリプトの guard' "${BASELINE}"
}

@test "issue-1348-bash-allowlist-rule: regression §1-§11 all present and consecutive" {
  [ -f "${BASELINE}" ]
  local count
  count=$(grep -cE '^## [1-9][0-9]*\.' "${BASELINE}")
  [ "${count}" -eq 11 ]
}
