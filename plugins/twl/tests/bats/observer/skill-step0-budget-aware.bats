#!/usr/bin/env bats
# skill-step0-budget-aware.bats - TDD RED phase tests for Issue #1577 AC6
#
# AC6: plugins/twl/skills/su-observer/SKILL.md の Step 0 サブステップ 2.6 を新設
#
# 背景: 現在 Step 0 のサブステップは 2.5 まで存在する（budget-pause.json 確認）。
#       AC6 では 2.6 として budget status line の (YYm) 解釈に関する awareness 手順を追加する。
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

  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  export SKILL_MD
}

# ===========================================================================
# AC6: Step 0 サブステップ 2.6 の存在チェック
# RED: 現時点では 2.6 が存在しないため全テストが fail する
# ===========================================================================

@test "ac6: SKILL.md Step 0 に サブステップ 2.6 が存在する" {
  # AC: SKILL.md の Step 0 サブステップ 2.6 を新設
  # RED: 実装前は fail する — 2.6 が存在しない
  [ -f "$SKILL_MD" ]
  grep -q "2\.6\." "$SKILL_MD"
}

@test "ac6: SKILL.md Step 0 サブステップ 2.6 が budget status line の (YYm) 解釈に関する記述を含む" {
  # AC: 2.6 は budget format disambiguator として (YYm) = cycle reset wall-clock を明示する
  # RED: 実装前は fail する — 2.6 が存在しない
  [ -f "$SKILL_MD" ]
  python3 -c "
import sys, re
with open('$SKILL_MD') as f:
    content = f.read()
# Step 0 セクション内を取得
step0_m = re.search(r'## Step 0:.*?(?=^## Step [1-9]|\Z)', content, re.DOTALL | re.MULTILINE)
if not step0_m:
    print('Step 0 section not found in SKILL.md')
    sys.exit(1)
step0 = step0_m.group(0)
# 2.6 サブステップが存在すること
if '2.6' not in step0:
    print('Substep 2.6 not found in Step 0')
    sys.exit(1)
# 2.6 サブステップに (YYm) または cycle reset の記述があること
lines = step0.splitlines()
idx = None
for i, line in enumerate(lines):
    if '2.6' in line:
        idx = i
        break
if idx is None:
    print('2.6 line not found in Step 0')
    sys.exit(1)
substep_text = '\n'.join(lines[idx:idx+5])
has_yymin = ('YYm' in substep_text or '(YYm)' in substep_text)
has_cycle_or_budget = ('cycle' in substep_text or 'budget' in substep_text.lower())
if not (has_yymin or has_cycle_or_budget):
    print('(YYm) / cycle reset description not found in substep 2.6')
    sys.exit(1)
sys.exit(0)
"
}

@test "ac6: SKILL.md Step 0 の順序は 2.5 の次に 2.6 が配置されている" {
  # AC: サブステップの順序が正しいこと
  # RED: 実装前は fail する — 2.6 が存在しない
  [ -f "$SKILL_MD" ]
  python3 -c "
import sys
with open('$SKILL_MD') as f:
    content = f.read()
lines = content.splitlines()
idx_25 = None
idx_26 = None
for i, line in enumerate(lines):
    if '2.5.' in line and idx_25 is None:
        idx_25 = i
    if '2.6.' in line and idx_26 is None:
        idx_26 = i
if idx_25 is None:
    print('2.5 substep not found')
    sys.exit(1)
if idx_26 is None:
    print('2.6 substep not found')
    sys.exit(1)
if idx_26 <= idx_25:
    print(f'2.6 (line {idx_26}) is not after 2.5 (line {idx_25})')
    sys.exit(1)
sys.exit(0)
"
}

@test "ac6: SKILL.md Step 0 サブステップ 2.6 が 不変条件 Q への参照を含む" {
  # AC: 2.6 は不変条件 Q（budget format invariant）を参照すること
  # RED: 実装前は fail する — 2.6 が存在せず不変条件 Q も存在しない
  [ -f "$SKILL_MD" ]
  python3 -c "
import sys, re
with open('$SKILL_MD') as f:
    content = f.read()
step0_m = re.search(r'## Step 0:.*?(?=^## Step [1-9]|\Z)', content, re.DOTALL | re.MULTILINE)
if not step0_m:
    print('Step 0 not found')
    sys.exit(1)
step0 = step0_m.group(0)
lines = step0.splitlines()
idx = None
for i, line in enumerate(lines):
    if '2.6' in line:
        idx = i
        break
if idx is None:
    print('2.6 not found in Step 0')
    sys.exit(1)
substep_text = '\n'.join(lines[idx:idx+5])
if '不変条件 Q' not in substep_text and 'invariant-q' not in substep_text.lower():
    print('不変条件 Q reference not found in substep 2.6')
    sys.exit(1)
sys.exit(0)
"
}

@test "ac6: SKILL.md Step 0 サブステップ 2.6 が ScheduleWakeup の delaySeconds 計算式を含む" {
  # AC: 2.6(c) で ScheduleWakeup delaySeconds = (YYm) × 60 + 300 の計算式を明示すること
  [ -f "$SKILL_MD" ]
  python3 -c "
import sys, re
with open('$SKILL_MD') as f:
    content = f.read()
step0_m = re.search(r'## Step 0:.*?(?=^## Step [1-9]|\Z)', content, re.DOTALL | re.MULTILINE)
if not step0_m:
    print('Step 0 not found')
    sys.exit(1)
step0 = step0_m.group(0)
lines = step0.splitlines()
idx = None
for i, line in enumerate(lines):
    if '2.6' in line:
        idx = i
        break
if idx is None:
    print('2.6 not found in Step 0')
    sys.exit(1)
# 2.6 から次のサブステップ（2.7 or 3.）まで
substep_block = []
for line in lines[idx:]:
    if re.match(r'\s*[23]\.[0-9]+\.', line) and line.strip().startswith(('2.7', '2.8', '2.9', '3.')):
        break
    substep_block.append(line)
substep_text = '\n'.join(substep_block)
has_schedulewakeup = 'ScheduleWakeup' in substep_text
has_delay_seconds = 'delaySeconds' in substep_text
if not (has_schedulewakeup and has_delay_seconds):
    print(f'ScheduleWakeup={has_schedulewakeup}, delaySeconds={has_delay_seconds}: 計算式が不足')
    sys.exit(1)
sys.exit(0)
"
}
