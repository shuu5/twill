#!/usr/bin/env bash
# check-catalog-integrity.sh - Validate integrity of catalog reference files
#
# Reads deps.yaml refs section to discover reference files dynamically.
# No hardcoding of catalog names — new catalogs are picked up automatically.
#
# Usage:
#   check-catalog-integrity.sh [--repo-root <dir>] [--deps <file>] MODE [<file>...]
#
# Modes (default: --all):
#   --check-existence   All deps.yaml refs section files exist on disk
#   --check-sections    Section number continuity (## N. format)
#   --check-must        MUST / MUST NOT contradiction detection
#   --check-xref        Internal §N cross-reference validation
#   --all               Run all checks
#
# Exit codes:  0 = all passed,  1 = failures,  2 = usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPS_YAML="${REPO_ROOT}/deps.yaml"
FAIL_COUNT=0

_fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
_ok()   { echo "  ok: $*"; }

# Extract paths from deps.yaml refs section (type: reference entries)
_get_ref_paths() {
  python3 - "${DEPS_YAML}" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for val in (data.get('refs') or {}).values():
    if isinstance(val, dict) and val.get('type') == 'reference' and 'path' in val:
        print(val['path'])
PYEOF
}

# --check-existence: verify every deps.yaml refs entry exists on disk
check_existence() {
  local ok=0 fail=0
  while IFS= read -r relpath; do
    if [[ -f "${REPO_ROOT}/${relpath}" ]]; then
      ok=$((ok + 1))
    else
      _fail "missing reference file: ${relpath}"
      fail=$((fail + 1))
    fi
  done < <(_get_ref_paths)
  [[ $fail -eq 0 ]] && _ok "existence: all ${ok} reference files present"
}

# --check-sections: ## N. section number continuity
check_sections() {
  local file="$1"
  local relpath="${file#${REPO_ROOT}/}"
  local nums=() line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^##[[:space:]]+([0-9]+)\. ]] && nums+=("${BASH_REMATCH[1]}")
  done < "$file"

  [[ ${#nums[@]} -eq 0 ]] && return 0

  local expected="${nums[0]}" ok=0
  for n in "${nums[@]}"; do
    if [[ "$n" -ne "$expected" ]]; then
      _fail "section gap in ${relpath}: expected §${expected} got §${n}"
      ok=1
    fi
    expected=$((expected + 1))
  done
  [[ $ok -eq 0 ]] && _ok "sections: ${relpath} (${#nums[@]} sections §${nums[0]}-$((expected-1)))"
}

# --check-must: detect MUST / MUST NOT contradictions within a file
check_must() {
  local file="$1"
  local relpath="${file#${REPO_ROOT}/}"
  local out="" rc=0

  out=$(python3 - "${file}" "${relpath}" <<'PYEOF'
import sys, re

filepath, rel = sys.argv[1], sys.argv[2]
with open(filepath) as f:
    lines = f.readlines()

must_do  = {}  # token -> first line_num
must_not = {}  # token -> first line_num

for i, line in enumerate(lines, 1):
    m = re.search(r'MUST\s+NOT\s+(\S+)', line)
    if m:
        tok = re.sub(r'[.,;:）)：\s]+$', '', m.group(1)).lower()
        if len(tok) >= 4 and tok not in must_not:
            must_not[tok] = i
        continue
    m = re.search(r'MUST\s+(\S+)', line)
    if m:
        tok = re.sub(r'[.,;:）)：\s]+$', '', m.group(1)).lower()
        if len(tok) >= 4 and tok not in ('not', 'have', 'also', 'only', 'be') and tok not in must_do:
            must_do[tok] = i

hits = [(tok, must_do[tok], must_not[tok]) for tok in must_do if tok in must_not]
if hits:
    print(f"MUST contradiction in {rel}:")
    for tok, ln_do, ln_not in hits:
        print(f"  line {ln_do}: MUST '{tok}'  vs  line {ln_not}: MUST NOT '{tok}'")
    sys.exit(1)
PYEOF
  ) || rc=$?

  if [[ $rc -ne 0 ]]; then
    _fail "$out"
  else
    _ok "must: ${relpath} (no contradictions)"
  fi
}

# --check-xref: validate §N internal cross-references (§N where N is top-level section)
check_xref() {
  local file="$1"
  local relpath="${file#${REPO_ROOT}/}"
  local defined=() line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^##[[:space:]]+([0-9]+)\. ]] && defined+=("${BASH_REMATCH[1]}")
  done < "$file"

  [[ ${#defined[@]} -eq 0 ]] && return 0  # nothing to validate against

  local fail=0 out="" rc=0
  out=$(python3 - "${file}" "${relpath}" "${defined[@]}" <<'PYEOF'
import sys, re

filepath, rel = sys.argv[1], sys.argv[2]
defined = set(sys.argv[3:])

broken = []
with open(filepath) as f:
    for i, line in enumerate(f, 1):
        if re.match(r'^##\s+', line):
            continue  # skip header lines
        for m in re.finditer(r'§(\d+)(?![.\d])', line):
            sec = m.group(1)
            if sec not in defined:
                broken.append(f"  line {i}: §{sec} not defined in {rel}")

if broken:
    print(f"Broken xref(s) in {rel}:")
    print('\n'.join(broken))
    sys.exit(1)
PYEOF
  ) || rc=$?

  if [[ $rc -ne 0 ]]; then
    _fail "$out"
  else
    _ok "xref: ${relpath}"
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

MODE="--all"
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)  REPO_ROOT="$2"; DEPS_YAML="${REPO_ROOT}/deps.yaml"; shift 2 ;;
    --deps)       DEPS_YAML="$2"; shift 2 ;;
    --check-existence|--check-sections|--check-must|--check-xref|--all)
                  MODE="$1"; shift ;;
    --)           shift; break ;;
    -*)           echo "Unknown option: $1" >&2; exit 2 ;;
    *)            FILES+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

_run_on_all_refs() {
  local fn="$1"
  while IFS= read -r _rp; do
    _ap="${REPO_ROOT}/${_rp}"
    [[ -f "$_ap" ]] && "$fn" "$_ap"
  done < <(_get_ref_paths)
}

case "$MODE" in
  --check-existence)
    check_existence
    ;;
  --check-sections)
    if [[ ${#FILES[@]} -gt 0 ]]; then
      for f in "${FILES[@]}"; do check_sections "$f"; done
    else
      _run_on_all_refs check_sections
    fi
    ;;
  --check-must)
    if [[ ${#FILES[@]} -gt 0 ]]; then
      for f in "${FILES[@]}"; do check_must "$f"; done
    else
      _run_on_all_refs check_must
    fi
    ;;
  --check-xref)
    if [[ ${#FILES[@]} -gt 0 ]]; then
      for f in "${FILES[@]}"; do check_xref "$f"; done
    else
      _run_on_all_refs check_xref
    fi
    ;;
  --all)
    check_existence
    _run_on_all_refs check_sections
    _run_on_all_refs check_must
    _run_on_all_refs check_xref
    ;;
esac

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "FAILED: ${FAIL_COUNT} error(s)" >&2
  exit 1
fi

echo "PASS: catalog integrity checks passed"
exit 0
