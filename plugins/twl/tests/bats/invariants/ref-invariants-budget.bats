#!/usr/bin/env bats
# ref-invariants-budget.bats - TDD RED phase tests for Issue #1577 AC1
#
# AC1: plugins/twl/refs/ref-invariants.md に不変条件 Q を新設する
#      （budget status line の (YYm) 解釈）
#
# 【命名決定】Issue #1577 の AC1/AC7 は「不変条件 P」と記載しているが、
# 不変条件 P は Issue #1578 (PR #1591) で「Issue 起票 flow 大原則」として
# 既に使用済み（ref-invariants.md L205）。
# そのため、budget format 不変条件は「不変条件 Q」として実装する。
# 実装者はこのファイルの不変条件 Q アサーションに従い、不変条件 Q を実装すること。
# （AC に「不変条件 P」と書かれていても「不変条件 Q」で実装する）
#
# RED: 全テストは実装前の状態で fail する

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir
  bats_dir="$(cd "${this_dir}/.." && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  REF_FILE="${REPO_ROOT}/refs/ref-invariants.md"
  export REF_FILE
}

# ===========================================================================
# AC1: 不変条件 Q セクションの存在チェック
# RED: 不変条件 Q は未追加なため全テストが fail する
# ===========================================================================

@test "ac1: ref-invariants.md に 不変条件 Q セクションが存在する" {
  # AC: ref-invariants.md に不変条件 Q を新設する（budget status line の (YYm) 解釈）
  # RED: 実装前は fail する — 不変条件 Q が存在しない
  [ -f "$REF_FILE" ]
  grep -q "^## 不変条件 Q:" "$REF_FILE"
}

@test "ac1: 不変条件 Q セクションに budget status line (YYm) の説明が含まれる" {
  # AC: budget status line の (YYm) 解釈を不変条件として明文化
  # RED: 実装前は fail する — 不変条件 Q が存在しない
  [ -f "$REF_FILE" ]
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 Q:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('不変条件 Q section not found')
    sys.exit(1)
section = m.group(0)
has_yymin = ('YYm' in section or '(YYm)' in section)
has_cycle = ('cycle reset' in section or 'cycle_reset' in section)
if not (has_yymin and has_cycle):
    print('(YYm) cycle reset wall-clock description not found in 不変条件 Q')
    sys.exit(1)
sys.exit(0)
"
}

@test "ac1: 不変条件 Q セクションに budget_status_line アンカーが存在する" {
  # AC: 他ファイルから参照可能なアンカーが設定されていること
  # RED: 実装前は fail する — 不変条件 Q セクション自体が存在しない
  [ -f "$REF_FILE" ]
  grep -qE '<a id="invariant-q' "$REF_FILE"
}

@test "ac1: ref-invariants.md の不変条件セクション数が P + Q で 16 以上になる" {
  # AC: 不変条件 Q 追加後はセクション数が増加する
  # RED: 現在は P まで（15 個: A-O + P = 16 個）の状態で Q が存在しないため 16 で fail する
  [ -f "$REF_FILE" ]
  local count
  count=$(grep -c "^## 不変条件 [A-Z]:" "$REF_FILE")
  # 不変条件 Q 追加後は 17 以上になるはず（現在 A-P = 16）
  [ "$count" -ge 17 ]
}

@test "ac1: 不変条件 Q に 根拠フィールドが存在する" {
  # AC: 不変条件 Q は根拠を持つこと（ADR 参照または説明文）
  # RED: 実装前は fail する — 不変条件 Q が存在しない
  [ -f "$REF_FILE" ]
  python3 -c "
import sys, re
with open('$REF_FILE') as f:
    content = f.read()
m = re.search(r'## 不変条件 Q:.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not m:
    print('不変条件 Q section not found')
    sys.exit(1)
section = m.group(0)
if '根拠' not in section and '**根拠**' not in section:
    print('根拠フィールドが不変条件 Q に存在しない')
    sys.exit(1)
sys.exit(0)
"
}
