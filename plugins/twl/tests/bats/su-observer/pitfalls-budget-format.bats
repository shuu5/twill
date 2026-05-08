#!/usr/bin/env bats
# pitfalls-budget-format.bats - TDD RED phase tests for Issue #1577 AC2
#
# AC2: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §4.6 を
#      anti-pattern + 正解例付きで更新
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

  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  export PITFALLS_CATALOG
}

# ===========================================================================
# AC2: §4.6 anti-pattern セクションの存在チェック
# RED: 現時点では §4.6 に anti-pattern / 正解例記載が存在しないため fail する
# ===========================================================================

@test "ac2: pitfalls-catalog.md §4.6 に anti-pattern 記述が存在する" {
  # AC: pitfalls-catalog.md §4.6 を anti-pattern + 正解例付きで更新
  # RED: 実装前は fail する — §4.6 に anti-pattern の記述が存在しない
  [ -f "$PITFALLS_CATALOG" ]
  grep -qF 'anti-pattern' "$PITFALLS_CATALOG"
  # §4.6 セクション内に anti-pattern が記述されていることを検証
  python3 -c "
import sys, re
with open('$PITFALLS_CATALOG') as f:
    content = f.read()
# §4.6 の行を特定して周辺を取得（テーブル行）
lines = content.splitlines()
idx = None
for i, line in enumerate(lines):
    if re.search(r'\| 4\.6 \|', line):
        idx = i
        break
if idx is None:
    print('§4.6 row not found')
    sys.exit(1)
# §4.6 の行または直後に anti-pattern が存在すること
section_text = '\n'.join(lines[idx:idx+10])
if 'anti-pattern' not in section_text and 'Anti-pattern' not in section_text:
    print('anti-pattern not found near §4.6')
    sys.exit(1)
sys.exit(0)
"
}

@test "ac2: pitfalls-catalog.md §4.6 に YYm の意味説明（正解例）が存在する" {
  # AC: pitfalls-catalog.md §4.6 を anti-pattern + 正解例付きで更新
  # RED: 実装前は fail する — §4.6 に (YYm) の正しい解釈（cycle reset wall-clock）の正解例が存在しない
  [ -f "$PITFALLS_CATALOG" ]
  # (YYm) = cycle reset wall-clock であることの正解例が §4.6 周辺に存在すること
  python3 -c "
import sys, re
with open('$PITFALLS_CATALOG') as f:
    content = f.read()
lines = content.splitlines()
idx = None
for i, line in enumerate(lines):
    if re.search(r'\| 4\.6 \|', line):
        idx = i
        break
if idx is None:
    print('§4.6 row not found')
    sys.exit(1)
# §4.6 行から30行以内に YYm の cycle reset wall-clock 説明が存在すること
section_text = '\n'.join(lines[idx:idx+30])
has_yymin_desc = ('YYm' in section_text or '(YYm)' in section_text)
has_cycle_reset = ('cycle reset' in section_text or 'cycle_reset' in section_text)
if not (has_yymin_desc and has_cycle_reset):
    print('(YYm) cycle reset wall-clock explanation not found near §4.6')
    sys.exit(1)
sys.exit(0)
"
}

@test "ac2: pitfalls-catalog.md §4.6 に 正解例 セクションが存在する" {
  # AC: pitfalls-catalog.md §4.6 を anti-pattern + 正解例付きで更新
  # RED: 実装前は fail する — §4.6 周辺に「正解例」または「correct example」が存在しない
  [ -f "$PITFALLS_CATALOG" ]
  python3 -c "
import sys, re
with open('$PITFALLS_CATALOG') as f:
    content = f.read()
lines = content.splitlines()
idx = None
for i, line in enumerate(lines):
    if re.search(r'\| 4\.6 \|', line):
        idx = i
        break
if idx is None:
    print('§4.6 row not found')
    sys.exit(1)
section_text = '\n'.join(lines[idx:idx+30])
if '正解例' not in section_text and 'correct' not in section_text.lower():
    print('正解例 not found near §4.6')
    sys.exit(1)
sys.exit(0)
"
}

@test "ac2: pitfalls-catalog.md §4.6 に 不変条件 Q への参照が存在する" {
  # AC: §4.6 は不変条件 Q (budget status line の (YYm) 解釈) を参照すること
  # RED: 実装前は fail する — 不変条件 Q が未追加なため参照も存在しない
  [ -f "$PITFALLS_CATALOG" ]
  python3 -c "
import sys, re
with open('$PITFALLS_CATALOG') as f:
    content = f.read()
lines = content.splitlines()
idx = None
for i, line in enumerate(lines):
    if re.search(r'\| 4\.6 \|', line):
        idx = i
        break
if idx is None:
    print('§4.6 row not found')
    sys.exit(1)
section_text = '\n'.join(lines[idx:idx+30])
if '不変条件 Q' not in section_text and 'invariant-q' not in section_text.lower():
    print('不変条件 Q reference not found near §4.6')
    sys.exit(1)
sys.exit(0)
"
}
