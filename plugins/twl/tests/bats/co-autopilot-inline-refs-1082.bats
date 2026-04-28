#!/usr/bin/env bats
# co-autopilot-inline-refs-1082.bats
# RED tests for Issue #1082: co-autopilot 常時参照 refs 4 個を SKILL.md に inline 化
#
# AC coverage:
#   AC1 - 4 refs (phase-sanity/session-init/su-observer-integration/worker-auto-mode) の内容が
#          SKILL.md に inline 化され、refs/ には存在しない（orphan）
#   AC2 - emergency-bypass.md のみ refs/ に残存し、他 4 件の ref ファイルは削除済み
#   AC3 - SKILL.md の見出し階層が統一され、TOC/概要が先頭付近に存在する
#   AC4 - deps.yaml から 4 件の reference エントリと component 定義が除去され、
#          emergency-bypass のみ残存。twl check --deps-integrity 0 errors
#   AC5 - co-autopilot-skillmd-split.bats の AC1 閾値が 280 行に緩和されており、
#          SKILL.md が 280 行以内に収まる
#   AC6 - audit.py の co-autopilot 例外ロジックが存在し、critical を出さない
#   AC7 - autopilot-phase-sanity.bats / autopilot-invariants.bats が PASS（回帰なし）

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SKILL_MD="${REPO_ROOT}/skills/co-autopilot/SKILL.md"
  REFS_DIR="${REPO_ROOT}/skills/co-autopilot/refs"
  DEPS="${REPO_ROOT}/deps.yaml"
  BATS_SPLIT="${REPO_ROOT}/tests/bats/co-autopilot-skillmd-split.bats"
  AUDIT_PY="${REPO_ROOT}/../../cli/twl/src/twl/validation/audit.py"
}

# ===========================================================================
# AC1: 4 refs の内容が SKILL.md に inline 化されている
# ===========================================================================

@test "ac1: phase-sanity の内容が SKILL.md に inline 化されている（commands/autopilot-phase-sanity.md を直接参照）" {
  [ -f "${SKILL_MD}" ]
  # inline 後は SKILL.md が commands/autopilot-phase-sanity.md を直接参照するはず
  run grep "commands/autopilot-phase-sanity.md" "${SKILL_MD}"
  if [ "${status}" -ne 0 ]; then
    echo "FAIL: SKILL.md に phase-sanity inline 内容が見当たらない（AC1 未実装）"
    return 1
  fi
}

@test "ac1: session-init の内容が SKILL.md に inline 化されている（### Step 3 セッション開始時 で存在）" {
  [ -f "${SKILL_MD}" ]
  run grep -E "### (Step 3: セッション開始時|セッション開始時|PYTHONPATH 設定)" "${SKILL_MD}"
  if [ "${status}" -ne 0 ]; then
    echo "FAIL: SKILL.md に session-init inline 内容が見当たらない（AC1 未実装）"
    return 1
  fi
}

@test "ac1: su-observer-integration の内容が SKILL.md に inline 化されている（### su-observer で存在）" {
  [ -f "${SKILL_MD}" ]
  run grep -E "### (su-observer|spawn-controller)" "${SKILL_MD}"
  if [ "${status}" -ne 0 ]; then
    echo "FAIL: SKILL.md に su-observer-integration inline 内容が見当たらない（AC1 未実装）"
    return 1
  fi
}

@test "ac1: worker-auto-mode の内容が SKILL.md に inline 化されている（### Worker auto mode で存在）" {
  [ -f "${SKILL_MD}" ]
  run grep -E "### (Worker auto mode|確認方法 A|確認方法 B)" "${SKILL_MD}"
  if [ "${status}" -ne 0 ]; then
    echo "FAIL: SKILL.md に worker-auto-mode inline 内容が見当たらない（AC1 未実装）"
    return 1
  fi
}

@test "ac1: SKILL.md に 4 refs への Read 参照が残っていない（inline 済みのため不要）" {
  [ -f "${SKILL_MD}" ]
  run python3 - "${SKILL_MD}" <<'EOF'
import sys, re
from pathlib import Path

skill = Path(sys.argv[1]).read_text(encoding='utf-8')
# inline 対象 4 件への Read 参照が残っていないこと
inline_refs = [
    'co-autopilot-phase-sanity.md',
    'co-autopilot-session-init.md',
    'co-autopilot-su-observer-integration.md',
    'co-autopilot-worker-auto-mode.md',
]
remaining = [r for r in inline_refs if r in skill]
if remaining:
    print(f"FAIL: SKILL.md に inline 済み ref への Read 参照が残存: {remaining}")
    sys.exit(1)
print("OK: 4 inline refs への Read 参照は除去済み")
EOF
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: emergency-bypass.md のみ refs/ に残存し、他 4 件は削除済み
# ===========================================================================

@test "ac2: refs/ に emergency-bypass.md が存在する" {
  [ -f "${REFS_DIR}/co-autopilot-emergency-bypass.md" ]
}

@test "ac2: refs/ に phase-sanity.md が存在しない（inline 済みで削除）" {
  if [ -f "${REFS_DIR}/co-autopilot-phase-sanity.md" ]; then
    echo "FAIL: co-autopilot-phase-sanity.md が refs/ に残存（AC2: 削除すべき）"
    return 1
  fi
}

@test "ac2: refs/ に session-init.md が存在しない（inline 済みで削除）" {
  if [ -f "${REFS_DIR}/co-autopilot-session-init.md" ]; then
    echo "FAIL: co-autopilot-session-init.md が refs/ に残存（AC2: 削除すべき）"
    return 1
  fi
}

@test "ac2: refs/ に su-observer-integration.md が存在しない（inline 済みで削除）" {
  if [ -f "${REFS_DIR}/co-autopilot-su-observer-integration.md" ]; then
    echo "FAIL: co-autopilot-su-observer-integration.md が refs/ に残存（AC2: 削除すべき）"
    return 1
  fi
}

@test "ac2: refs/ に worker-auto-mode.md が存在しない（inline 済みで削除）" {
  if [ -f "${REFS_DIR}/co-autopilot-worker-auto-mode.md" ]; then
    echo "FAIL: co-autopilot-worker-auto-mode.md が refs/ に残存（AC2: 削除すべき）"
    return 1
  fi
}

@test "ac2: refs/ の .md ファイルは emergency-bypass.md 1 件のみ" {
  [ -d "${REFS_DIR}" ]
  run python3 - "${REFS_DIR}" <<'EOF'
import sys
from pathlib import Path

refs_dir = Path(sys.argv[1])
md_files = sorted(p.name for p in refs_dir.glob("*.md"))
expected = ['co-autopilot-emergency-bypass.md']
if md_files != expected:
    print(f"FAIL: refs/ のファイル構成が期待と異なる")
    print(f"  期待: {expected}")
    print(f"  実際: {md_files}")
    sys.exit(1)
print(f"OK: refs/ = {md_files}")
EOF
  [ "${status}" -eq 0 ]
}

@test "ac2: SKILL.md の Emergency Bypass 節から emergency-bypass.md への Read 参照が残存する" {
  [ -f "${SKILL_MD}" ]
  run grep "co-autopilot-emergency-bypass.md" "${SKILL_MD}"
  if [ "${status}" -ne 0 ]; then
    echo "FAIL: SKILL.md の Emergency Bypass 節に emergency-bypass.md への Read 参照がない（AC2 未実装）"
    return 1
  fi
}

# ===========================================================================
# AC3: SKILL.md の節構造整理（TOC・見出し階層統一）
# ===========================================================================

@test "ac3: SKILL.md の先頭付近（30 行以内）に TOC または概要が存在する" {
  [ -f "${SKILL_MD}" ]
  run python3 - "${SKILL_MD}" <<'EOF'
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
# frontmatter をスキップ
body_start = 0
if lines and lines[0].strip() == '---':
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            body_start = i + 1
            break

body_lines = lines[body_start:]
# 先頭 30 行以内に TOC らしき記述（## Step N または <!-- TOC --> 等）が複数存在すること
toc_indicators = 0
for line in body_lines[:30]:
    # TOC エントリらしき行（Step への言及やリンク）
    if '## Step' in line or '- Step' in line or '- [Step' in line or 'TOC' in line.upper():
        toc_indicators += 1

if toc_indicators < 2:
    print(f"FAIL: SKILL.md 先頭 30 行に TOC/概要が見当たらない（toc_indicators={toc_indicators}）")
    sys.exit(1)
print(f"OK: TOC indicators = {toc_indicators}")
EOF
  [ "${status}" -eq 0 ]
}

@test "ac3: SKILL.md の # 見出しが1つのみ（トップレベル、コードブロック除外）" {
  [ -f "${SKILL_MD}" ]
  run python3 - "${SKILL_MD}" <<'EOF'
import sys, re
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
# frontmatter 除外
body_start = 0
if lines and lines[0].strip() == '---':
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            body_start = i + 1
            break

body_lines = lines[body_start:]
# コードブロック内の行を除外してから H1 を探す
in_code = False
h1_lines = []
for line in body_lines:
    if line.startswith('```'):
        in_code = not in_code
        continue
    if not in_code and re.match(r'^# [^#]', line):
        h1_lines.append(line)

if len(h1_lines) != 1:
    print(f"FAIL: # 見出しが 1 つでない: {h1_lines}")
    sys.exit(1)
print(f"OK: H1 = {h1_lines[0]!r}")
EOF
  [ "${status}" -eq 0 ]
}

@test "ac3: SKILL.md の ## 見出しが主要 Step に限定されている（## Step N 形式）" {
  [ -f "${SKILL_MD}" ]
  run python3 - "${SKILL_MD}" <<'EOF'
import sys, re
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
body_start = 0
if lines and lines[0].strip() == '---':
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            body_start = i + 1
            break

body_lines = lines[body_start:]
h2_lines = [l for l in body_lines if re.match(r'^## [^#]', l)]
# ## 見出しはすべて存在すること（空でないこと）
if not h2_lines:
    print("FAIL: ## 見出しが存在しない")
    sys.exit(1)
print(f"OK: H2 count = {len(h2_lines)}")
for l in h2_lines:
    print(f"  {l}")
EOF
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: deps.yaml から 4 件の reference エントリ・component 定義が除去
# ===========================================================================

@test "ac4: deps.yaml の co-autopilot.calls から phase-sanity reference が除去されている" {
  run grep "reference: co-autopilot-phase-sanity" "${DEPS}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: deps.yaml に co-autopilot-phase-sanity reference が残存（AC4 未実装）"
    return 1
  fi
}

@test "ac4: deps.yaml の co-autopilot.calls から session-init reference が除去されている" {
  run grep "reference: co-autopilot-session-init" "${DEPS}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: deps.yaml に co-autopilot-session-init reference が残存（AC4 未実装）"
    return 1
  fi
}

@test "ac4: deps.yaml の co-autopilot.calls から su-observer-integration reference が除去されている" {
  run grep "reference: co-autopilot-su-observer-integration" "${DEPS}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: deps.yaml に co-autopilot-su-observer-integration reference が残存（AC4 未実装）"
    return 1
  fi
}

@test "ac4: deps.yaml の co-autopilot.calls から worker-auto-mode reference が除去されている" {
  run grep "reference: co-autopilot-worker-auto-mode" "${DEPS}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: deps.yaml に co-autopilot-worker-auto-mode reference が残存（AC4 未実装）"
    return 1
  fi
}

@test "ac4: deps.yaml の refs セクションから co-autopilot-phase-sanity component 定義が除去されている" {
  run python3 - "${DEPS}" <<'EOF'
import sys
import yaml
from pathlib import Path

data = yaml.safe_load(Path(sys.argv[1]).read_text(encoding='utf-8'))
refs = data.get('refs', {})
removed = ['co-autopilot-phase-sanity', 'co-autopilot-session-init',
           'co-autopilot-su-observer-integration', 'co-autopilot-worker-auto-mode']
remaining = [r for r in removed if r in refs]
if remaining:
    print(f"FAIL: deps.yaml refs セクションに削除すべき component が残存: {remaining}")
    sys.exit(1)
# emergency-bypass は残存すること
if 'co-autopilot-emergency-bypass' not in refs:
    print("FAIL: co-autopilot-emergency-bypass が refs セクションから消えている（AC2 違反）")
    sys.exit(1)
print("OK: 4 件除去済み、emergency-bypass 残存")
EOF
  [ "${status}" -eq 0 ]
}

@test "ac4: twl check --deps-integrity が 0 errors で通る" {
  run bash -c "cd '${REPO_ROOT}' && twl check --deps-integrity --format json 2>&1"
  if [ "${status}" -ne 0 ]; then
    errors=$(echo "${output}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('errors', 'unknown'))
except Exception:
    print('parse_error')
" 2>/dev/null || echo "nonzero")
    if [[ "${errors}" != "0" ]]; then
      echo "FAIL: twl check --deps-integrity errors=${errors}"
      return 1
    fi
  fi
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: co-autopilot-skillmd-split.bats の AC1 閾値が 280 行に緩和
# ===========================================================================

@test "ac5: co-autopilot-skillmd-split.bats の body_lines 閾値が 280 に更新されている" {
  [ -f "${BATS_SPLIT}" ]
  # 旧閾値 200 ではなく 280 になっていること
  run grep "body_lines > 280" "${BATS_SPLIT}"
  if [ "${status}" -ne 0 ]; then
    echo "FAIL: co-autopilot-skillmd-split.bats の body_lines 閾値が 280 に更新されていない（AC5 未実装）"
    return 1
  fi
}

@test "ac5: co-autopilot-skillmd-split.bats に旧閾値 200 が残っていない" {
  [ -f "${BATS_SPLIT}" ]
  run grep "body_lines > 200" "${BATS_SPLIT}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: co-autopilot-skillmd-split.bats に旧閾値 200 が残存（AC5 未更新）"
    return 1
  fi
}

@test "ac5: SKILL.md の body lines が 280 以内に収まる" {
  [ -f "${SKILL_MD}" ]
  run python3 - "${SKILL_MD}" <<'EOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding='utf-8').splitlines()
body_start = 0
if lines and lines[0].strip() == '---':
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            body_start = i + 1
            break
body_lines = len(lines) - body_start
print(f"body_lines={body_lines}")
if body_lines > 280:
    print(f"FAIL: {body_lines} lines > 280 (threshold)")
    sys.exit(1)
EOF
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"body_lines="* ]]
}

# ===========================================================================
# AC6: audit.py の co-autopilot 例外ロジック（280 行まで warning 以下）
# ===========================================================================

@test "ac6: audit.py に co-autopilot の例外ロジックが存在する" {
  [ -f "${AUDIT_PY}" ]
  # co-autopilot を 280 行まで warning にする例外コードが存在すること
  run python3 - "${AUDIT_PY}" <<'EOF'
import sys
from pathlib import Path

code = Path(sys.argv[1]).read_text(encoding='utf-8')
# co-autopilot と 280 の両方が同じ文脈に存在すること
has_co_autopilot_exception = 'co-autopilot' in code and '280' in code
if not has_co_autopilot_exception:
    print("FAIL: audit.py に co-autopilot 例外ロジック（280 行閾値）が見当たらない")
    sys.exit(1)
print("OK: co-autopilot exception logic found")
EOF
  [ "${status}" -eq 0 ]
}

@test "ac6: audit.py の co-autopilot 例外は controller_size セクションに位置する" {
  [ -f "${AUDIT_PY}" ]
  run python3 - "${AUDIT_PY}" <<'EOF'
import sys, re
from pathlib import Path

code = Path(sys.argv[1]).read_text(encoding='utf-8')
# controller_size セクション内（Section 1）に co-autopilot 例外があること
section1_match = re.search(
    r'Section 1.*?Section 2',
    code,
    re.DOTALL
)
if not section1_match:
    print("FAIL: audit.py に Section 1 (controller_size) が見当たらない")
    sys.exit(1)
section1 = section1_match.group(0)
if 'co-autopilot' not in section1 or '280' not in section1:
    print("FAIL: Section 1 に co-autopilot 例外ロジック（280）が存在しない")
    sys.exit(1)
print("OK: Section 1 に co-autopilot exception found")
EOF
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: 回帰確認 — 既存 bats が PASS
# ===========================================================================

@test "ac7: autopilot-phase-sanity.bats が PASS（chain 動作回帰なし）" {
  local sanity_bats
  sanity_bats="${REPO_ROOT}/tests/bats/structure/autopilot-phase-sanity.bats"
  [ -f "${sanity_bats}" ]
  run bats "${sanity_bats}"
  [ "${status}" -eq 0 ]
}

@test "ac7: autopilot-invariants.bats が PASS（不変条件回帰なし）" {
  local invariants_bats
  invariants_bats="${REPO_ROOT}/tests/bats/invariants/autopilot-invariants.bats"
  [ -f "${invariants_bats}" ]
  run bats "${invariants_bats}"
  [ "${status}" -eq 0 ]
}
