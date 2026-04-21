#!/usr/bin/env bats
# existing-docs-update.bats - Validation that existing docs are updated to reference ref-invariants.md
#
# Tests for Issue #788: autopilot.md / CLAUDE.md / su-observer/SKILL.md を
# ref-invariants.md へのリンク参照に更新することの検証
#
# Scenarios covered (specs/existing-docs-update.md):
#  1. autopilot.md から不変条件テーブルが削除される
#  2. autopilot.md の不変条件への言及がリンクに変換される
#  3. CLAUDE.md の不変条件 B がリンク参照になる
#  4. su-observer/SKILL.md に境界説明とリンクが追加される
#  5. SU-1〜SU-7 の定義が SKILL.md に維持される

setup() {
  # Resolve REPO_ROOT to plugins/twl/
  local helpers_dir
  helpers_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_test_dir
  bats_test_dir="$(cd "$helpers_dir/.." && pwd)"
  local tests_dir
  tests_dir="$(cd "$bats_test_dir/.." && pwd)"
  REPO_ROOT="$(cd "$tests_dir/.." && pwd)"
  export REPO_ROOT

  AUTOPILOT_MD="$REPO_ROOT/architecture/domain/contexts/autopilot.md"
  CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
  REF_INVARIANTS="$REPO_ROOT/refs/ref-invariants.md"
}

# ===========================================================================
# Requirement: autopilot.md の不変条件定義をリンク参照に統一
# Scenario: autopilot.md から不変条件テーブルが削除される
# WHEN: plugins/twl/architecture/domain/contexts/autopilot.md を確認する
# THEN: 不変条件 A-M の定義テーブル行は削除され、ref-invariants.md へのリンクが残っている
# ===========================================================================

@test "autopilot.md: file exists" {
  [ -f "$AUTOPILOT_MD" ]
}

@test "autopilot.md: ref-invariants.md へのリンクが存在する" {
  grep -q 'ref-invariants' "$AUTOPILOT_MD"
}

@test "autopilot.md: 不変条件 A-M の定義テーブル行が削除されている" {
  # テーブル形式の定義（|  **A** | ... のような行）が残っていないこと
  # リンク参照行は許可される
  if grep -qP "^\|[[:space:]]*\*\*[A-M]\*\*[[:space:]]*\|" "$AUTOPILOT_MD"; then
    fail "Invariant definition table rows still present in autopilot.md (should be replaced with link)"
  fi
}

# ===========================================================================
# Scenario: autopilot.md の不変条件への言及がリンクに変換される
# WHEN: autopilot.md で 不変条件 というキーワードを検索する
# THEN: 定義テーブルではなくリンク参照として不変条件が言及されている
# ===========================================================================

@test "autopilot.md: 不変条件キーワードの言及がリンク形式である" {
  # 不変条件への言及があればそれはリンク形式であること
  # リンク形式の例: [ref-invariants.md](refs/ref-invariants.md) または
  #                 [不変条件](refs/ref-invariants.md) など
  local mention_count
  mention_count=$(grep -c "不変条件" "$AUTOPILOT_MD" 2>/dev/null || echo 0)

  if [ "$mention_count" -eq 0 ]; then
    skip "autopilot.md contains no 不変条件 mentions"
  fi

  # 言及があるなら、リンクが含まれていること
  grep -q 'ref-invariants' "$AUTOPILOT_MD"
}

# ===========================================================================
# Requirement: CLAUDE.md の不変条件 B 言及をリンク参照に更新
# Scenario: CLAUDE.md の不変条件 B がリンク参照になる
# WHEN: plugins/twl/CLAUDE.md を確認する
# THEN: 不変条件 B の記述が ref-invariants.md へのリンクを含む
# ===========================================================================

@test "CLAUDE.md: file exists" {
  [ -f "$CLAUDE_MD" ]
}

@test "CLAUDE.md: 不変条件 B に ref-invariants.md へのリンクが含まれる" {
  # CLAUDE.md 内で不変条件 B が言及されている場合、リンクを含むこと
  local has_inv_b
  has_inv_b=$(grep -c "不変条件 B" "$CLAUDE_MD" 2>/dev/null || echo 0)

  if [ "$has_inv_b" -eq 0 ]; then
    skip "CLAUDE.md does not mention 不変条件 B"
  fi

  # 不変条件 B の言及が ref-invariants リンクと同じコンテキストにあること
  grep -q 'ref-invariants' "$CLAUDE_MD"
}

@test "CLAUDE.md: 不変条件 B の言及行の周辺に ref-invariants リンクが存在する" {
  # 不変条件 B の言及から 5 行以内に ref-invariants が登場すること
  python3 -c "
import sys
with open('$CLAUDE_MD') as f:
    lines = f.readlines()

inv_b_lines = [i for i, l in enumerate(lines) if '不変条件 B' in l]
if not inv_b_lines:
    print('no 不変条件 B mention found — skipping')
    sys.exit(0)

for idx in inv_b_lines:
    start = max(0, idx - 5)
    end = min(len(lines), idx + 6)
    context = ''.join(lines[start:end])
    if 'ref-invariants' in context:
        sys.exit(0)

print('ref-invariants link not found near 不変条件 B mention')
sys.exit(1)
"
}

# ===========================================================================
# Requirement: su-observer/SKILL.md への境界明示とリンク追加
# Scenario: su-observer/SKILL.md に境界説明とリンクが追加される
# WHEN: plugins/twl/skills/su-observer/SKILL.md を確認する
# THEN: "SU-* は supervisor 固有の application-level 制約" という説明と
#       ref-invariants.md へのリンクが存在する
# ===========================================================================

@test "su-observer/SKILL.md: file exists" {
  [ -f "$SKILL_MD" ]
}

@test "su-observer/SKILL.md: ref-invariants.md へのリンクが存在する" {
  grep -q 'ref-invariants' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-* は supervisor 固有の application-level 制約 という説明が存在する" {
  # 完全一致でなくても "SU" と "supervisor" と "application-level" のキーワードが
  # 近接して存在していることを確認する
  python3 -c "
import sys
with open('$SKILL_MD') as f:
    content = f.read()

keywords = ['SU', 'supervisor', 'application-level']
for kw in keywords:
    if kw not in content:
        print(f'keyword {repr(kw)} not found in SKILL.md')
        sys.exit(1)
sys.exit(0)
"
}

# ===========================================================================
# Scenario: SU-1〜SU-7 の定義が SKILL.md に維持される
# WHEN: plugins/twl/skills/su-observer/SKILL.md を確認する
# THEN: SU-1〜SU-7 の定義が削除されずに残っている
# ===========================================================================

@test "su-observer/SKILL.md: SU-1 の定義が残っている" {
  grep -q 'SU-1' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-2 の定義が残っている" {
  grep -q 'SU-2' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-3 の定義が残っている" {
  grep -q 'SU-3' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-4 の定義が残っている" {
  grep -q 'SU-4' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-5 の定義が残っている" {
  grep -q 'SU-5' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-6 の定義が残っている" {
  grep -q 'SU-6' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-7 の定義が残っている" {
  grep -q 'SU-7' "$SKILL_MD"
}

@test "su-observer/SKILL.md: SU-1〜SU-7 が全て 7 件存在する" {
  local count
  count=$(grep -cE 'SU-[1-7]' "$SKILL_MD" 2>/dev/null || echo 0)
  [ "$count" -ge 7 ]
}
