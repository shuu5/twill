#!/usr/bin/env bats
# ref-invariants-structure.bats - Structural validation of ref-invariants.md
#
# Tests for Issue #788: plugins/twl/refs/ref-invariants.md 新規作成
#
# Scenarios covered (specs/ref-invariants-doc.md):
#  1. 全 13 件の section が存在する
#  2. 半角コロンと半角大文字を使用する
#  3. ADR なし条件（H/A/C/L）の根拠フィールド
#  4. DeltaSpec spec リンク条件（D/E/F/G/I/J/K）の根拠フィールド
#  5. L/M の検証方法フィールド
#  6. deps.yaml に ref-invariants エントリが存在する
#  7. README Refs に ref-invariants が追加される

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

  REF_FILE="$REPO_ROOT/refs/ref-invariants.md"
  DEPS_FILE="$REPO_ROOT/deps.yaml"
  README_FILE="$REPO_ROOT/README.md"
}

# ===========================================================================
# Requirement: ref-invariants.md 新規作成
# Scenario: 全 13 件の section が存在する
# ===========================================================================

@test "ref-invariants: file exists" {
  [ -f "$REF_FILE" ]
}

@test "ref-invariants: section A exists" {
  grep -q "^## 不変条件 A:" "$REF_FILE"
}

@test "ref-invariants: section B exists" {
  grep -q "^## 不変条件 B:" "$REF_FILE"
}

@test "ref-invariants: section C exists" {
  grep -q "^## 不変条件 C:" "$REF_FILE"
}

@test "ref-invariants: section D exists" {
  grep -q "^## 不変条件 D:" "$REF_FILE"
}

@test "ref-invariants: section E exists" {
  grep -q "^## 不変条件 E:" "$REF_FILE"
}

@test "ref-invariants: section F exists" {
  grep -q "^## 不変条件 F:" "$REF_FILE"
}

@test "ref-invariants: section G exists" {
  grep -q "^## 不変条件 G:" "$REF_FILE"
}

@test "ref-invariants: section H exists" {
  grep -q "^## 不変条件 H:" "$REF_FILE"
}

@test "ref-invariants: section I exists" {
  grep -q "^## 不変条件 I:" "$REF_FILE"
}

@test "ref-invariants: section J exists" {
  grep -q "^## 不変条件 J:" "$REF_FILE"
}

@test "ref-invariants: section K exists" {
  grep -q "^## 不変条件 K:" "$REF_FILE"
}

@test "ref-invariants: section L exists" {
  grep -q "^## 不変条件 L:" "$REF_FILE"
}

@test "ref-invariants: section M exists" {
  grep -q "^## 不変条件 M:" "$REF_FILE"
}

@test "ref-invariants: exactly 13 sections exist (A through M)" {
  local count
  count=$(grep -c "^## 不変条件 [A-M]:" "$REF_FILE")
  [ "$count" -eq 13 ]
}

# ===========================================================================
# Scenario: 半角コロンと半角大文字を使用する
# WHEN: ref-invariants.md の section ヘッダーを検査する
# THEN: ## 不変条件 A: 〜 ## 不変条件 M: に全角文字・全角コロンが含まれない
# ===========================================================================

@test "ref-invariants: no full-width colon in section headers (全角コロン混入検出)" {
  # 全角コロン U+FF1A を検出したら FAIL
  if grep -P "^## \xe4\xb8\x8d\xe5\xa4\x89\xe6\x9d\xa1\xe4\xbb\xb6\s+[A-M]：" "$REF_FILE" 2>/dev/null; then
    fail "full-width colon found in section header"
  fi
  # Python による全角コロン検出（より確実）
  if python3 -c "
import sys
with open('$REF_FILE') as f:
    for i, line in enumerate(f, 1):
        if line.startswith('## 不変条件') and '：' in line:
            print(f'line {i}: {line.rstrip()}')
            sys.exit(1)
sys.exit(0)
"; then
    true
  else
    fail "full-width colon detected in section header"
  fi
}

@test "ref-invariants: no full-width alphabet in section headers (全角大文字混入検出)" {
  # 全角英大文字 A-M (U+FF21〜U+FF2D) を検出したら FAIL
  if python3 -c "
import sys
fullwidth = set(chr(i) for i in range(0xFF21, 0xFF2E))  # A-M fullwidth
with open('$REF_FILE') as f:
    for i, line in enumerate(f, 1):
        if line.startswith('## 不変条件'):
            for ch in fullwidth:
                if ch in line:
                    print(f'line {i}: full-width char {repr(ch)} in: {line.rstrip()}')
                    sys.exit(1)
sys.exit(0)
"; then
    true
  else
    fail "full-width alphabet detected in section header"
  fi
}

# ===========================================================================
# Scenario: ADR なし条件（H/A/C/L）の根拠フィールド
# WHEN: 不変条件 H、A、C、L の根拠フィールドを確認する
# THEN: "ADR なし — 慣習的制約" と記載されている
# ===========================================================================

@test "ref-invariants: invariant-A 根拠フィールドに 'ADR なし — 慣習的制約' が含まれる" {
  # Extract section A and check for the rationale text
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
# Find section A
m = re.search(r'## 不変条件 A:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section A not found')
    sys.exit(1)
section = m.group(0)
if 'ADR なし' not in section or '慣習的制約' not in section:
    print('ADR なし — 慣習的制約 not found in section A')
    sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-C 根拠フィールドに 'ADR なし — 慣習的制約' が含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 C:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section C not found')
    sys.exit(1)
section = m.group(0)
if 'ADR なし' not in section or '慣習的制約' not in section:
    print('ADR なし — 慣習的制約 not found in section C')
    sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-H 根拠フィールドに 'ADR なし — 慣習的制約' が含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 H:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section H not found')
    sys.exit(1)
section = m.group(0)
if 'ADR なし' not in section or '慣習的制約' not in section:
    print('ADR なし — 慣習的制約 not found in section H')
    sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-L 根拠フィールドに 'ADR なし — 慣習的制約' が含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 L:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section L not found')
    sys.exit(1)
section = m.group(0)
if 'ADR なし' not in section or '慣習的制約' not in section:
    print('ADR なし — 慣習的制約 not found in section L')
    sys.exit(1)
sys.exit(0)
"
}

# ===========================================================================
# Scenario: DeltaSpec spec リンク条件（D/E/F/G/I/J/K）の根拠フィールド
# WHEN: 不変条件 D、E、F、G、I、J、K の根拠フィールドを確認する
# THEN: autopilot-lifecycle.md または merge-gate.md の anchor リンクが記載されている
# ===========================================================================

@test "ref-invariants: invariant-D 根拠フィールドに spec リンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 D:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section D not found'); sys.exit(1)
section = m.group(0)
if 'autopilot-lifecycle.md' not in section and 'merge-gate.md' not in section:
    print('spec link not found in section D'); sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-E 根拠フィールドに spec リンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 E:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section E not found'); sys.exit(1)
section = m.group(0)
if 'autopilot-lifecycle.md' not in section and 'merge-gate.md' not in section:
    print('spec link not found in section E'); sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-F 根拠フィールドに spec リンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 F:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section F not found'); sys.exit(1)
section = m.group(0)
if 'autopilot-lifecycle.md' not in section and 'merge-gate.md' not in section:
    print('spec link not found in section F'); sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-G 根拠フィールドに spec リンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 G:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section G not found'); sys.exit(1)
section = m.group(0)
if 'autopilot-lifecycle.md' not in section and 'merge-gate.md' not in section:
    print('spec link not found in section G'); sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-I 根拠フィールドに spec リンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 I:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section I not found'); sys.exit(1)
section = m.group(0)
if 'autopilot-lifecycle.md' not in section and 'merge-gate.md' not in section:
    print('spec link not found in section I'); sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-J 根拠フィールドに spec リンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 J:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section J not found'); sys.exit(1)
section = m.group(0)
if 'autopilot-lifecycle.md' not in section and 'merge-gate.md' not in section:
    print('spec link not found in section J'); sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-K 根拠フィールドに spec リンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 K:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section K not found'); sys.exit(1)
section = m.group(0)
if 'autopilot-lifecycle.md' not in section and 'merge-gate.md' not in section:
    print('spec link not found in section K'); sys.exit(1)
sys.exit(0)
"
}

# ===========================================================================
# Scenario: L/M の検証方法フィールド
# WHEN: 不変条件 L、M の検証方法フィールドを確認する
# THEN: "#789 で bats テスト生成予定" と注記されている
# ===========================================================================

@test "ref-invariants: invariant-L 検証方法フィールドに bats テストリンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 L:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section L not found'); sys.exit(1)
section = m.group(0)
if 'invariant-L' not in section or 'autopilot-invariants.bats' not in section:
    print('bats test link not found in section L'); sys.exit(1)
sys.exit(0)
"
}

@test "ref-invariants: invariant-M 検証方法フィールドに bats テストリンクが含まれる" {
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 M:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('Section M not found'); sys.exit(1)
section = m.group(0)
if 'invariant-M' not in section or 'autopilot-invariants.bats' not in section:
    print('bats test link not found in section M'); sys.exit(1)
sys.exit(0)
"
}

# ===========================================================================
# Requirement: deps.yaml への ref-invariants エントリ追加
# Scenario: deps.yaml に ref-invariants エントリが存在する
# WHEN: plugins/twl/deps.yaml を確認する
# THEN: ref-invariants という名前のエントリが type: reference で存在する
# ===========================================================================

@test "deps-yaml: ref-invariants エントリが存在する" {
  grep -q 'ref-invariants' "$DEPS_FILE"
}

@test "deps-yaml: ref-invariants エントリが type: reference である" {
  python3 -c "
import sys, yaml
with open('$DEPS_FILE') as f:
    data = yaml.safe_load(f)
refs = data.get('refs', {})
if 'ref-invariants' not in refs:
    print('ref-invariants not found in refs section'); sys.exit(1)
entry = refs['ref-invariants']
if entry.get('type') != 'reference':
    print(f'type is {entry.get(\"type\")!r}, expected reference'); sys.exit(1)
sys.exit(0)
"
}

# ===========================================================================
# Requirement: README.md の Refs 一覧更新
# Scenario: README Refs に ref-invariants が追加される
# WHEN: plugins/twl/README.md の Refs セクションを確認する
# THEN: ref-invariants エントリが存在し、Refs の合計カウントが 19 である
# ===========================================================================

@test "README: ref-invariants エントリが Refs セクションに存在する" {
  grep -q 'ref-invariants' "$README_FILE"
}

@test "README: Refs の合計カウントが 19 である" {
  # 合計カウント表記（例: "Refs: 19" または "19 refs" など）を検出
  grep -qE 'Refs.*19|19.*[Rr]ef' "$README_FILE"
}

# ===========================================================================
# Issue #1577: 不変条件 Q 追加後のカウントアサーション
# Scenario: 不変条件 Q（budget status line の (YYm) 解釈）追加後の section 数検証
# WHEN: ref-invariants.md に不変条件 Q を追加した後
# THEN: [A-Z] pattern の不変条件セクション数が 17 以上になる（A-P=16 + Q=17）
#
# 背景: 不変条件 A-M (13件) → N/O/P 追加で 16 件（Issue #1577 実装前時点）
#       Issue #1577 で Q を追加 → 17 件になること
# RED: 実装前は fail する — 不変条件 Q が存在しないため count = 16 < 17
# ===========================================================================

@test "ref-invariants: 不変条件 Q 追加後: section 数が 17 以上になる (Issue #1577)" {
  # AC1: ref-invariants.md に不変条件 Q を新設した後の構造検証
  # RED: 実装前は fail する — Q が存在せず count=16 のため [ 16 -ge 17 ] が false
  local count
  count=$(grep -c "^## 不変条件 [A-Z]:" "$REF_FILE")
  [ "$count" -ge 17 ] || {
    echo "FAIL: 不変条件 Q が未追加。現在のセクション数: ${count}（期待: 17 以上）"
    grep "^## 不変条件 [A-Z]:" "$REF_FILE" || true
    return 1
  }
}

@test "ref-invariants: 不変条件 Q セクションが存在する (Issue #1577)" {
  # AC1: 不変条件 Q の具体的な存在確認
  # RED: 実装前は fail する — 不変条件 Q が存在しない
  grep -q "^## 不変条件 Q:" "$REF_FILE"
}

# ===========================================================================
# Step 3-4 / ADR-043: 不変条件 T/U/V/W/X 追加後のカウントアサーション
# Scenario: 第 5 弾 dig で追加された T-X 5 件 (A-X 24 件) の存在検証
# WHEN: ref-invariants.md に不変条件 T/U/V/W/X を追加した後
# THEN: [A-Z] pattern の不変条件セクション数が 24 以上になる
#       (A-Q=17 + R/S=19 + T/U/V/W/X=24)
#
# 背景:
#   - A-M = 13 件 (initial)
#   - N/O/P 追加 → 16 件
#   - Q 追加 → 17 件 (Issue #1577)
#   - R/S 追加 → 19 件
#   - T (mailbox atomic) / U (atomic skill verification) / V (per-specialist scope) /
#     W (gate hook) / X (deploy-verify セット) 追加 → 24 件 (ADR-043)
#
# 関連: plugins/twl/architecture/decisions/ADR-043-twill-radical-rebuild.md
# ===========================================================================

@test "ref-invariants: 不変条件 T-X 追加後: section 数が 24 以上になる (ADR-043)" {
  local count
  count=$(grep -c "^## 不変条件 [A-Z]:" "$REF_FILE")
  [ "$count" -ge 24 ] || {
    echo "FAIL: 不変条件 T-X (24 件) が未完備。現在のセクション数: ${count}（期待: 24 以上）"
    grep "^## 不変条件 [A-Z]:" "$REF_FILE" || true
    return 1
  }
}

@test "ref-invariants: 不変条件 T セクションが存在する (ADR-043: mailbox atomic)" {
  grep -q "^## 不変条件 T:" "$REF_FILE"
}

@test "ref-invariants: 不変条件 U セクションが存在する (ADR-043: atomic skill verification)" {
  grep -q "^## 不変条件 U:" "$REF_FILE"
}

@test "ref-invariants: 不変条件 V セクションが存在する (ADR-043: per-specialist checkpoint)" {
  grep -q "^## 不変条件 V:" "$REF_FILE"
}

@test "ref-invariants: 不変条件 W セクションが存在する (ADR-043: gate hook)" {
  grep -q "^## 不変条件 W:" "$REF_FILE"
}

@test "ref-invariants: 不変条件 X セクションが存在する (ADR-043: deploy-verify セット)" {
  grep -q "^## 不変条件 X:" "$REF_FILE"
}
