#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: workflow-pr-merge/SKILL.md ★HUMAN GATE placement
# Issue: #1098 (tech-debt: ★HUMAN GATE 配置の意味的精度向上)
# Coverage level: full-ac
#
# AC1: ★HUMAN GATE を独立節 ## merge-gate ユーザー介入要件 に移動
# AC2: 移動後節内に ADR-030 適用条件（merge-gate REJECT / Layer 2 Escalate）を明示
# AC3: PR description に比較結果段落追記（プロセス AC — ここでは SKILL.md の構造のみ検証）
# AC4: grep 検証（ファイル数保全・UTF-8 健全性・anchor 保全）
# AC5: ADR-030 整合性（★HUMAN GATE 件数変更なし）
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_count_ge() {
  local count="$1"
  local min="$2"
  [[ "$count" -ge "$min" ]]
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
  $func || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++)) || true
}

SKILL_MD="skills/workflow-pr-merge/SKILL.md"
SKILL_MD_ABS="${PROJECT_ROOT}/${SKILL_MD}"

# =============================================================================
# AC1: ★HUMAN GATE の独立節移動
# =============================================================================
echo ""
echo "--- AC1: ★HUMAN GATE の独立節移動 ---"

# WHEN: SKILL.md が修正済みである
# THEN: ## merge-gate ユーザー介入要件 という独立節が存在する
test_ac1_independent_section_exists() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" '^## merge-gate ユーザー介入要件'
}
run_test "AC1: ## merge-gate ユーザー介入要件 節が存在する" test_ac1_independent_section_exists

# WHEN: SKILL.md が修正済みである
# THEN: ★HUMAN GATE は ## merge-gate ユーザー介入要件 節内に配置されている
test_ac1_human_gate_in_new_section() {
  assert_file_exists "$SKILL_MD" || return 1
  # merge-gate ユーザー介入要件 節内に ★HUMAN GATE が含まれること
  # （節の開始から次の ## まで）
  SKILL_MD_ABS="$SKILL_MD_ABS" python3 - <<'PYEOF'
import re, sys

import os
skill_md_path = os.environ.get("SKILL_MD_ABS", "plugins/twl/skills/workflow-pr-merge/SKILL.md")
with open(skill_md_path, encoding="utf-8") as f:
    content = f.read()

# セクション抽出: ## merge-gate ユーザー介入要件 から次の ## まで
m = re.search(r'^## merge-gate ユーザー介入要件.*?(?=^##|\Z)', content, re.MULTILINE | re.DOTALL)
if not m:
    print("ERROR: '## merge-gate ユーザー介入要件' section not found", file=sys.stderr)
    sys.exit(1)

section = m.group(0)
if '★HUMAN GATE' not in section:
    print("ERROR: ★HUMAN GATE not found in '## merge-gate ユーザー介入要件' section", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
}
run_test "AC1: ★HUMAN GATE が ## merge-gate ユーザー介入要件 節内に配置されている" test_ac1_human_gate_in_new_section

# WHEN: SKILL.md が修正済みである
# THEN: compaction 復帰プロトコル節内に ★HUMAN GATE が含まれていない
test_ac1_compaction_section_no_human_gate() {
  assert_file_exists "$SKILL_MD" || return 1
  SKILL_MD_ABS="$SKILL_MD_ABS" python3 - <<'PYEOF'
import re, sys, os

skill_md_path = os.environ.get("SKILL_MD_ABS", "")
with open(skill_md_path, encoding="utf-8") as f:
    content = f.read()

m = re.search(r'^## compaction 復帰プロトコル.*?(?=^##|\Z)', content, re.MULTILINE | re.DOTALL)
if not m:
    sys.exit(0)  # 節が存在しない場合は PASS（★HUMAN GATE も含まれない）

section = m.group(0)
if '★HUMAN GATE' in section:
    print("ERROR: ★HUMAN GATE found in '## compaction 復帰プロトコル' section", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "AC1: compaction 復帰プロトコル節内に ★HUMAN GATE が含まれていない" test_ac1_compaction_section_no_human_gate

# =============================================================================
# AC2: ★HUMAN GATE の意味的整合性確保
# =============================================================================
echo ""
echo "--- AC2: ★HUMAN GATE の意味的整合性確保 ---"

# WHEN: SKILL.md が修正済みである
# THEN: 新節内に「merge-gate REJECT によりエスカレーションが必要な場合」が明示されている
test_ac2_reject_escalation_condition_explicit() {
  assert_file_exists "$SKILL_MD" || return 1
  SKILL_MD_ABS="$SKILL_MD_ABS" python3 - <<'PYEOF'
import re, sys

import os
skill_md_path = os.environ.get("SKILL_MD_ABS", "plugins/twl/skills/workflow-pr-merge/SKILL.md")
with open(skill_md_path, encoding="utf-8") as f:
    content = f.read()

m = re.search(r'^## merge-gate ユーザー介入要件.*?(?=^##|\Z)', content, re.MULTILINE | re.DOTALL)
if not m:
    print("ERROR: section not found", file=sys.stderr)
    sys.exit(1)

section = m.group(0)
if 'merge-gate REJECT' not in section or 'エスカレーション' not in section:
    print("ERROR: ADR-030 condition 'merge-gate REJECT ... エスカレーション' not found in section", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "AC2: 新節内に merge-gate REJECT エスカレーション条件が明示されている" test_ac2_reject_escalation_condition_explicit

# WHEN: SKILL.md が修正済みである
# THEN: 新節内に「Layer 2 Escalate」が明示されている（ADR-030 §適用条件との整合）
test_ac2_layer2_escalate_explicit() {
  assert_file_exists "$SKILL_MD" || return 1
  SKILL_MD_ABS="$SKILL_MD_ABS" python3 - <<'PYEOF'
import re, sys

import os
skill_md_path = os.environ.get("SKILL_MD_ABS", "plugins/twl/skills/workflow-pr-merge/SKILL.md")
with open(skill_md_path, encoding="utf-8") as f:
    content = f.read()

m = re.search(r'^## merge-gate ユーザー介入要件.*?(?=^##|\Z)', content, re.MULTILINE | re.DOTALL)
if not m:
    print("ERROR: section not found", file=sys.stderr)
    sys.exit(1)

section = m.group(0)
if 'Layer 2' not in section:
    print("ERROR: 'Layer 2' not found in '## merge-gate ユーザー介入要件' section", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "AC2: 新節内に Layer 2 Escalate への言及が含まれている" test_ac2_layer2_escalate_explicit

# =============================================================================
# AC3: 関連配置との粒度整合性確認（プロセス AC — SKILL.md 構造のみ検証）
# =============================================================================
echo ""
echo "--- AC3: 関連配置との粒度整合性確認（SKILL.md 構造）---"

# AC3 の主体は PR description への追記であり SKILL.md ファイル検証では確認不能のため SKIP
run_test_skip "AC3: PR description への比較結果追記" "プロセス AC — PR description は本 test では検証不能"

# ただし co-autopilot/SKILL.md と co-architect/SKILL.md の参照元が存在することを確認
test_ac3_co_autopilot_skill_exists() {
  assert_file_exists "skills/co-autopilot/SKILL.md"
}
run_test "AC3 前提: co-autopilot/SKILL.md が存在する" test_ac3_co_autopilot_skill_exists

test_ac3_co_architect_skill_exists() {
  assert_file_exists "skills/co-architect/SKILL.md"
}
run_test "AC3 前提: co-architect/SKILL.md が存在する" test_ac3_co_architect_skill_exists

# =============================================================================
# AC4: grep 検証
# =============================================================================
echo ""
echo "--- AC4: grep 検証 ---"

# ファイル数保全: grep -rln '★HUMAN GATE' plugins/ | wc -l >= 8
test_ac4_file_count_preserved() {
  local count
  # PROJECT_ROOT = plugins/twl — plugins/ から再帰検索するとループするため REPO_ROOT を使用
  local repo_root
  repo_root="$(cd "${PROJECT_ROOT}/../.." && pwd)"
  count=$(grep -rln '★HUMAN GATE' "${repo_root}/plugins/" | wc -l)
  assert_count_ge "$count" 8
}
run_test "AC4: ★HUMAN GATE を含むファイル数が 8 以上（修正前と同数）" test_ac4_file_count_preserved

# UTF-8 健全性: SKILL.md 内に ★HUMAN GATE が UTF-8 エンコードで存在すること
test_ac4_utf8_integrity() {
  assert_file_exists "$SKILL_MD" || return 1
  # LC_ALL=C でバイト単位マッチ: ★(U+2605)= e2 98 85
  LC_ALL=C grep -qP '\xe2\x98\x85HUMAN GATE' "${PROJECT_ROOT}/${SKILL_MD}"
}
run_test "AC4: UTF-8 健全性 — SKILL.md 内に ★HUMAN GATE が存在する" test_ac4_utf8_integrity

# #1084 AC3(d) anchor 保全: 'merge-gate エスカレーション' が 1 件以上ヒット
test_ac4_anchor_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  local count
  count=$(grep -c 'merge-gate エスカレーション' "${PROJECT_ROOT}/${SKILL_MD}" || true)
  [[ "$count" -ge 1 ]]
}
run_test "AC4: #1084 AC3(d) anchor 'merge-gate エスカレーション' が保全されている" test_ac4_anchor_preserved

# =============================================================================
# AC5: ADR-030 整合性
# =============================================================================
echo ""
echo "--- AC5: ADR-030 整合性 ---"

# ADR-030 本体が存在すること
test_ac5_adr030_exists() {
  assert_file_exists "architecture/decisions/ADR-030-human-gate-marker.md"
}
run_test "AC5: ADR-030 ファイルが存在する" test_ac5_adr030_exists

# workflow-pr-merge/SKILL.md の ★HUMAN GATE 件数が修正後も 1 件であること（位置変更のみ）
test_ac5_human_gate_count_in_skill_md() {
  assert_file_exists "$SKILL_MD" || return 1
  local count
  count=$(grep -c '★HUMAN GATE' "${PROJECT_ROOT}/${SKILL_MD}" || true)
  [[ "$count" -eq 1 ]]
}
run_test "AC5: SKILL.md 内の ★HUMAN GATE 件数が 1（追加・削除なし）" test_ac5_human_gate_count_in_skill_md

# ADR-030 の ★HUMAN GATE 件数が変化していないこと（ADR-030 本体改訂不要）
test_ac5_adr030_not_modified_unnecessarily() {
  local adr="architecture/decisions/ADR-030-human-gate-marker.md"
  assert_file_exists "$adr" || return 1
  # ADR-030 に ★HUMAN GATE マーカー定義が含まれていること（健全性確認）
  assert_file_contains "$adr" '★HUMAN GATE'
}
run_test "AC5: ADR-030 に ★HUMAN GATE 定義が含まれている（本体健全性）" test_ac5_adr030_not_modified_unnecessarily

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
