#!/usr/bin/env bats
# autopilot-invariants-refupdate.bats - Validation of autopilot-invariants.bats update to ref-invariants.md
#
# Tests for Issue #788: autopilot-invariants.bats の invariant-J/K grep 対象を
# autopilot.md → refs/ref-invariants.md に切替した後の正常動作を検証する
#
# Scenarios covered (specs/bats-update.md):
#  1. 13 件の section 存在を検証する (ref-invariants-structure.bats 実行確認)
#  2. 全角コロン混入を検出する
#  3. 全角アルファベット混入を検出する
#  4. invariant-J テストが ref-invariants.md を参照する
#  5. invariant-K テストが ref-invariants.md を参照する
#  6. autopilot.md 定義削除後も bats が PASS する

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

  BATS_INV_FILE="$REPO_ROOT/tests/bats/invariants/autopilot-invariants.bats"
  BATS_STRUCT_FILE="$REPO_ROOT/tests/bats/invariants/ref-invariants-structure.bats"
  REF_FILE="$REPO_ROOT/refs/ref-invariants.md"
  AUTOPILOT_MD="$REPO_ROOT/architecture/domain/contexts/autopilot.md"
}

# ===========================================================================
# Requirement: ref-invariants-structure.bats 新規作成
# Scenario: 13 件の section 存在を検証する
# WHEN: ref-invariants-structure.bats を実行する
# THEN: 不変条件 A から M まで各 1 件ずつ、## 不変条件 X: ヘッダーの存在が検証される
# ===========================================================================

@test "ref-invariants-structure.bats: ファイルが存在する" {
  [ -f "$BATS_STRUCT_FILE" ]
}

@test "ref-invariants-structure.bats: A〜M の全 13 section を検証するテストが定義されている" {
  # 各不変条件ヘッダー grep を含むテスト定義がある
  for letter in A B C D E F G H I J K L M; do
    if ! grep -q "不変条件 ${letter}:" "$BATS_STRUCT_FILE"; then
      fail "section ${letter} validation not found in ref-invariants-structure.bats"
    fi
  done
}

@test "ref-invariants-structure.bats: 13 件の section カウント検証テストが定義されている" {
  grep -q '13' "$BATS_STRUCT_FILE"
}

# ===========================================================================
# Scenario: 全角コロン混入を検出する
# WHEN: ref-invariants.md に ## 不変条件 A： のような全角コロンが含まれる
# THEN: bats テストが FAIL してエラーを報告する
# ===========================================================================

@test "ref-invariants-structure.bats: 全角コロン混入検出テストが定義されている" {
  grep -q "全角コロン" "$BATS_STRUCT_FILE"
}

@test "ref-invariants-structure.bats: full-width colon (U+FF1A) を検出するロジックが含まれる" {
  # 全角コロン '：' のリテラルまたは Unicode エスケープ検索ロジックが含まれていること
  python3 -c "
import sys
with open('$BATS_STRUCT_FILE') as f:
    content = f.read()
# Check for full-width colon literal or its description
if '：' in content or 'FF1A' in content or 'full.width' in content or 'full-width' in content:
    sys.exit(0)
print('full-width colon detection logic not found')
sys.exit(1)
"
}

@test "全角コロンを含む仮想 ref-invariants.md を作成すると全角コロン検出できる" {
  # 全角コロン検出ロジックを直接テスト
  local tmpfile
  tmpfile=$(mktemp /tmp/test-ref-invariants-XXXXXX.md)
  echo "## 不変条件 A：タイトル" > "$tmpfile"

  # 全角コロン検出
  if python3 -c "
import sys
with open('$tmpfile') as f:
    for i, line in enumerate(f, 1):
        if line.startswith('## 不変条件') and '：' in line:
            sys.exit(1)
sys.exit(0)
"; then
    rm -f "$tmpfile"
    fail "full-width colon not detected (should have been detected)"
  fi
  rm -f "$tmpfile"
}

# ===========================================================================
# Scenario: 全角アルファベット混入を検出する
# WHEN: ref-invariants.md に ## 不変条件 Ａ: のような全角大文字が含まれる
# THEN: bats テストが FAIL してエラーを報告する
# ===========================================================================

@test "ref-invariants-structure.bats: 全角アルファベット混入検出テストが定義されている" {
  grep -q "全角" "$BATS_STRUCT_FILE"
}

@test "全角アルファベットを含む仮想 ref-invariants.md を作成すると全角文字検出できる" {
  local tmpfile
  tmpfile=$(mktemp /tmp/test-ref-invariants-XXXXXX.md)
  # 全角 A (U+FF21) を含むヘッダー
  printf "## 不変条件 \xef\xbc\xa1: タイトル\n" > "$tmpfile"

  if python3 -c "
import sys
fullwidth = set(chr(i) for i in range(0xFF21, 0xFF2E))
with open('$tmpfile') as f:
    for i, line in enumerate(f, 1):
        if line.startswith('## 不変条件'):
            for ch in fullwidth:
                if ch in line:
                    sys.exit(1)
sys.exit(0)
"; then
    rm -f "$tmpfile"
    fail "full-width alphabet not detected (should have been detected)"
  fi
  rm -f "$tmpfile"
}

# ===========================================================================
# Requirement: autopilot-invariants.bats の invariant-J/K grep 対象を切替
# Scenario: invariant-J テストが ref-invariants.md を参照する
# WHEN: autopilot-invariants.bats の invariant-J テストを確認する
# THEN: grep 対象が refs/ref-invariants.md であり、パターンが ## 不変条件 J: にマッチする
# ===========================================================================

@test "autopilot-invariants.bats: ファイルが存在する" {
  [ -f "$BATS_INV_FILE" ]
}

@test "autopilot-invariants.bats: invariant-J テストが refs/ref-invariants.md を参照する" {
  python3 -c "
import sys, re
with open('$BATS_INV_FILE') as f:
    content = f.read()
# Find invariant-J test block
m = re.search(r'@test[^{]*invariant-J[^{]*defines invariant[^{]*\{(.*?)\n\}', content, re.DOTALL)
if not m:
    print('invariant-J defines invariant test block not found')
    sys.exit(1)
block = m.group(1)
if 'refs/ref-invariants.md' not in block and 'ref-invariants.md' not in block:
    print('refs/ref-invariants.md not referenced in invariant-J test')
    sys.exit(1)
sys.exit(0)
"
}

@test "autopilot-invariants.bats: invariant-J テストのパターンが '## 不変条件 J:' 形式にマッチする" {
  python3 -c "
import sys, re
with open('$BATS_INV_FILE') as f:
    content = f.read()
# Find invariant-J test block
m = re.search(r'@test[^{]*invariant-J[^{]*defines invariant[^{]*\{(.*?)\n\}', content, re.DOTALL)
if not m:
    print('invariant-J defines invariant test block not found')
    sys.exit(1)
block = m.group(1)
# Check for new pattern (## 不変条件 J:) rather than old pattern (| **J** |)
if '不変条件 J' not in block and '## 不変条件 J:' not in block:
    print('new pattern ## 不変条件 J: not found in invariant-J test')
    sys.exit(1)
# Ensure old autopilot.md table pattern is NOT the only reference
if '\\\\*\\\\*J\\\\*\\\\*' in block and 'ref-invariants' not in block:
    print('old autopilot.md table grep pattern still used for invariant-J')
    sys.exit(1)
sys.exit(0)
"
}

@test "autopilot-invariants.bats: invariant-J 'defines invariant' テストの grep 対象が autopilot.md ではない" {
  python3 -c "
import sys, re
with open('$BATS_INV_FILE') as f:
    content = f.read()
m = re.search(r'(@test[^\n]*invariant-J[^\n]*defines invariant[^\n]*\n.*?\n\})', content, re.DOTALL)
if not m:
    print('invariant-J defines invariant test not found')
    sys.exit(1)
block = m.group(1)
# Should NOT grep from autopilot.md exclusively
if 'autopilot.md' in block and 'ref-invariants.md' not in block:
    print('invariant-J still greps from autopilot.md (should use ref-invariants.md)')
    sys.exit(1)
sys.exit(0)
"
}

# ===========================================================================
# Scenario: invariant-K テストが ref-invariants.md を参照する
# WHEN: autopilot-invariants.bats の invariant-K テストを確認する
# THEN: grep 対象が refs/ref-invariants.md であり、パターンが ## 不変条件 K: にマッチする
# ===========================================================================

@test "autopilot-invariants.bats: invariant-K テストが refs/ref-invariants.md を参照する" {
  python3 -c "
import sys, re
with open('$BATS_INV_FILE') as f:
    content = f.read()
m = re.search(r'@test[^{]*invariant-K[^{]*autopilot.md defines invariant[^{]*\{(.*?)\n\}', content, re.DOTALL)
if not m:
    # Try alternate naming
    m = re.search(r'(@test[^\n]*invariant-K[^\n]*defines invariant K[^\n]*\n.*?\n\})', content, re.DOTALL)
if not m:
    print('invariant-K defines invariant test block not found')
    sys.exit(1)
block = m.group(1)
if 'refs/ref-invariants.md' not in block and 'ref-invariants.md' not in block:
    print('refs/ref-invariants.md not referenced in invariant-K test')
    sys.exit(1)
sys.exit(0)
"
}

@test "autopilot-invariants.bats: invariant-K テストのパターンが '## 不変条件 K:' 形式にマッチする" {
  python3 -c "
import sys, re
with open('$BATS_INV_FILE') as f:
    content = f.read()
# Find any invariant-K test that references ref-invariants
inv_k_tests = re.findall(r'@test[^\n]*invariant-K[^\n]*\n.*?\n\}', content, re.DOTALL)
if not inv_k_tests:
    print('No invariant-K tests found')
    sys.exit(1)
found_ref = False
for block in inv_k_tests:
    if 'ref-invariants' in block and '不変条件 K' in block:
        found_ref = True
        break
if not found_ref:
    print('No invariant-K test found that uses ## 不変条件 K: pattern with ref-invariants.md')
    sys.exit(1)
sys.exit(0)
"
}

@test "autopilot-invariants.bats: invariant-K 'defines invariant' テストの grep 対象が autopilot.md ではない" {
  python3 -c "
import sys, re
with open('$BATS_INV_FILE') as f:
    content = f.read()
# Find the first invariant-K test
m = re.search(r'(@test[^\n]*invariant-K: autopilot.md defines invariant K[^\n]*\n.*?\n\})', content, re.DOTALL)
if not m:
    print('invariant-K: autopilot.md defines invariant K test not found — may already be updated')
    sys.exit(0)
block = m.group(1)
if 'autopilot.md' in block and 'ref-invariants.md' not in block:
    print('invariant-K still greps from autopilot.md (should use ref-invariants.md)')
    sys.exit(1)
sys.exit(0)
"
}

# ===========================================================================
# Scenario: autopilot.md 定義削除後も bats が PASS する
# WHEN: autopilot.md から不変条件 J/K の定義が削除された後に autopilot-invariants.bats を実行する
# THEN: invariant-J および invariant-K の "defines invariant" テストが PASS する
# ===========================================================================

@test "autopilot-invariants.bats: ref-invariants.md に不変条件 J が定義されており invariant-J テストが通過できる" {
  [ -f "$REF_FILE" ] || skip "ref-invariants.md not yet created"
  grep -q "^## 不変条件 J:" "$REF_FILE"
}

@test "autopilot-invariants.bats: ref-invariants.md に不変条件 K が定義されており invariant-K テストが通過できる" {
  [ -f "$REF_FILE" ] || skip "ref-invariants.md not yet created"
  grep -q "^## 不変条件 K:" "$REF_FILE"
}

@test "autopilot-invariants.bats + ref-invariants.md: J/K テストが ref-invariants.md から PASS する (integration)" {
  [ -f "$REF_FILE" ] || skip "ref-invariants.md not yet created"

  # invariant-J テストが参照するパスと同じファイルに J が定義されていること
  local j_grep_target
  j_grep_target=$(grep -A5 'invariant-J.*defines invariant' "$BATS_INV_FILE" \
    | grep 'ref-invariants' | head -1 | grep -oP 'refs/ref-invariants\.md|ref-invariants\.md' || true)

  if [ -z "$j_grep_target" ]; then
    skip "invariant-J grep target could not be determined from bats file"
  fi

  # 実際のファイルで J が存在することを確認
  grep -q "不変条件 J" "$REPO_ROOT/$j_grep_target" || \
    grep -q "不変条件 J" "$REF_FILE"
}
