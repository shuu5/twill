#!/usr/bin/env bats
# co-autopilot-skillmd-split.bats
# RED tests for Issue #982: co-autopilot SKILL.md split (controller_size + token_bloat)
#
# AC coverage:
#   AC1 - controller_size ≤ 200 lines (frontmatter excluded)
#   AC2 - token_bloat ≤ 1500 tok
#   AC3 - all refs in refs/ are 1:1 referenced by Read instructions in SKILL.md
#   AC4 - each ref file ≤ 200 lines
#   AC5 - twl check --deps-integrity 0 errors
#   AC6 - twl update-readme reflects refs/ in README.md
#   AC7 - smoke: autopilot-launch-status-gate.bats PASS (no behavior change)

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
  README="${REPO_ROOT}/README.md"

  # python-env.sh で PYTHONPATH を設定（audit module 参照用）
  # shellcheck disable=SC1091
  if [[ -f "${REPO_ROOT}/scripts/lib/python-env.sh" ]]; then
    source "${REPO_ROOT}/scripts/lib/python-env.sh" 2>/dev/null || true
  fi
}

# ===========================================================================
# AC1: controller_size ≤ 200 lines (frontmatter 除外)
# ===========================================================================

@test "ac1: co-autopilot SKILL.md body lines ≤ 200 (frontmatter excluded)" {
  [ -f "${SKILL_MD}" ]
  run python3 - "${SKILL_MD}" <<'EOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding='utf-8').splitlines()
# frontmatter 除外（audit.py の _count_body_lines と同ロジック）
body_start = 0
if lines and lines[0].strip() == '---':
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            body_start = i + 1
            break
body_lines = len(lines) - body_start
print(f"body_lines={body_lines}")
if body_lines > 200:
    print(f"FAIL: {body_lines} lines > 200 (threshold)")
    sys.exit(1)
EOF
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"body_lines="* ]]
}

# ===========================================================================
# AC2: token_bloat ≤ 1500 tok
# ===========================================================================

@test "ac2: co-autopilot SKILL.md token count ≤ 1500" {
  [ -f "${SKILL_MD}" ]
  run python3 - "${SKILL_MD}" <<'EOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')

# tiktoken が使えれば使い、なければ文字数/4 で近似
try:
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    tok = len(enc.encode(text))
    method = "tiktoken"
except ImportError:
    tok = len(text) // 4
    method = "approx(len/4)"

print(f"tokens={tok} method={method}")
if tok > 1500:
    print(f"FAIL: {tok} tok > 1500 (warn threshold)")
    sys.exit(1)
EOF
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tokens="* ]]
}

# ===========================================================================
# AC3: refs/ 内全 .md が SKILL.md の Read 指示文から 1:1 参照
# ===========================================================================

@test "ac3: refs/ directory exists" {
  [ -d "${REFS_DIR}" ]
}

@test "ac3: all refs/ files are referenced by Read instructions in SKILL.md (no orphan refs)" {
  [ -d "${REFS_DIR}" ]
  [ -f "${SKILL_MD}" ]
  run python3 - "${REFS_DIR}" "${SKILL_MD}" <<'EOF'
import sys, re
from pathlib import Path

refs_dir = Path(sys.argv[1])
skill_md = Path(sys.argv[2])

# refs/ 内の全 .md ファイル名（stem のみ）
ref_files = {p.name for p in refs_dir.glob("*.md")}

# SKILL.md 内の Read 指示文から refs/xxx.md を抽出
# パターン例: "refs/co-autopilot-emergency-bypass.md を Read"
#             "`refs/co-autopilot-phase-sanity.md` を Read"
body = skill_md.read_text(encoding='utf-8')
referenced = set(re.findall(r'refs/([\w\-]+\.md)', body))

orphan = ref_files - referenced
unreferenced_reads = referenced - ref_files

errors = []
if orphan:
    errors.append(f"FAIL: refs/ に存在するが SKILL.md で未参照: {sorted(orphan)}")
if unreferenced_reads:
    errors.append(f"WARN: SKILL.md で参照されているが refs/ に存在しない: {sorted(unreferenced_reads)}")

if errors:
    print('\n'.join(errors))
    sys.exit(1)

print(f"OK: {len(ref_files)} refs, all 1:1 referenced")
EOF
  [ "${status}" -eq 0 ]
}

@test "ac3: no Read instructions in SKILL.md point to nonexistent refs/ files" {
  [ -d "${REFS_DIR}" ]
  [ -f "${SKILL_MD}" ]
  run python3 - "${REFS_DIR}" "${SKILL_MD}" <<'EOF'
import sys, re
from pathlib import Path

refs_dir = Path(sys.argv[1])
skill_md = Path(sys.argv[2])

body = skill_md.read_text(encoding='utf-8')
referenced = set(re.findall(r'refs/([\w\-]+\.md)', body))

missing = {f for f in referenced if not (refs_dir / f).exists()}
if missing:
    print(f"FAIL: SKILL.md で参照されているが refs/ に存在しない: {sorted(missing)}")
    sys.exit(1)

print(f"OK: all {len(referenced)} Read references resolve to existing files")
EOF
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: refs/ 配下の各 ref ≤ 200 lines
# ===========================================================================

@test "ac4: each ref file in refs/ has ≤ 200 lines" {
  [ -d "${REFS_DIR}" ]
  run python3 - "${REFS_DIR}" <<'EOF'
import sys
from pathlib import Path

refs_dir = Path(sys.argv[1])
ref_files = sorted(refs_dir.glob("*.md"))

if not ref_files:
    print("FAIL: refs/ に .md ファイルが存在しない（実装未完）")
    sys.exit(1)

oversized = []
for p in ref_files:
    lines = len(p.read_text(encoding='utf-8').splitlines())
    if lines > 200:
        oversized.append(f"{p.name}: {lines} lines")

if oversized:
    print("FAIL: 200 lines 超過:")
    print('\n'.join(oversized))
    sys.exit(1)

print(f"OK: all {len(ref_files)} ref files ≤ 200 lines")
EOF
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: twl check --deps-integrity 0 errors
# ===========================================================================

@test "ac5: twl check --deps-integrity passes with 0 errors" {
  run bash -c "cd '${REPO_ROOT}' && twl check --deps-integrity --format json 2>&1"
  # exit 0 か、または json 出力に errors: 0 が含まれること
  if [ "${status}" -ne 0 ]; then
    # JSON 出力から errors count を抽出
    errors=$(echo "${output}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('errors', 'unknown'))
except Exception:
    print('parse_error')
" 2>/dev/null || echo "nonzero")
    if [[ "${errors}" != "0" ]]; then
      echo "FAIL: twl check --deps-integrity errors: ${errors}"
      return 1
    fi
  fi
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: twl update-readme 後 README.md に refs/ 構造が反映される
# ===========================================================================

@test "ac6: README.md contains co-autopilot refs/ section after update-readme" {
  # update-readme を dry-run 相当で実行（実際の README を確認）
  run bash -c "cd '${REPO_ROOT}' && twl update-readme --dry-run 2>&1 || twl update-readme 2>&1"
  # README に refs/ ファイル名が含まれるか確認
  run grep -c "co-autopilot" "${README}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]

  # refs/ が実装済みであれば、refs/ 配下のファイルが README に含まれることを確認
  if [ -d "${REFS_DIR}" ] && [ "$(ls "${REFS_DIR}"/*.md 2>/dev/null | wc -l)" -gt 0 ]; then
    run grep -l "refs/" "${README}"
    [ "${status}" -eq 0 ]
  fi
}

# ===========================================================================
# AC7: smoke — autopilot-launch-status-gate.bats が PASS（動作変更なし）
# ===========================================================================

@test "ac7: autopilot-launch-status-gate.bats passes (no behavior regression)" {
  local gate_bats
  gate_bats="$(dirname "$BATS_TEST_FILENAME")/autopilot-launch-status-gate.bats"
  [ -f "${gate_bats}" ]
  run bats "${gate_bats}"
  [ "${status}" -eq 0 ]
}
