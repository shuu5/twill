#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-autopilot chain resume 手順
# Coverage level: documentation-presence
# Verifies:
#   - ref-chain-resume.md が存在し Case A/B/C を含む
#   - su-observer/SKILL.md の「問題を検出した場合」から ref-chain-resume.md を参照している
#   - Case A/B/C に必要コマンドが含まれている
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
ERRORS=()

run_check() {
  local name="$1"
  shift
  if "$@"; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

file_contains() {
  local file="${PROJECT_ROOT}/$1"
  local pattern="$2"
  [[ -f "$file" ]] && grep -q "$pattern" "$file"
}

REF_FILE="refs/ref-chain-resume.md"
OBSERVER_SKILL="skills/su-observer/SKILL.md"

echo ""
echo "--- Requirement: ref-chain-resume.md の存在と Case A/B/C 記載 ---"

run_check "ref-chain-resume.md が存在する" \
  file_contains "$REF_FILE" "chain-resume"

run_check "Case A (state file 不在) が記載されている" \
  file_contains "$REF_FILE" "Case A"

run_check "Case B (chain 停止) が記載されている" \
  file_contains "$REF_FILE" "Case B"

run_check "Case C (PR マージ済み) が記載されている" \
  file_contains "$REF_FILE" "Case C"

run_check "state write コマンドが含まれている" \
  file_contains "$REF_FILE" "autopilot.state"

run_check "force-done オプションが含まれている" \
  file_contains "$REF_FILE" "force-done"

run_check "診断手順が含まれている" \
  file_contains "$REF_FILE" "診断手順"

echo ""
echo "--- Requirement: su-observer/SKILL.md からの参照 ---"

run_check "su-observer/SKILL.md に ref-chain-resume.md 参照が含まれる" \
  file_contains "$OBSERVER_SKILL" "ref-chain-resume.md"

run_check "「問題を検出した場合」セクションに chain 停止参照が記載" \
  file_contains "$OBSERVER_SKILL" "chain-resume"

echo ""
echo "--- Requirement: 関連ファイル参照 ---"

run_check "ref-chain-resume.md が ref-compaction-recovery.md を参照している" \
  file_contains "$REF_FILE" "ref-compaction-recovery.md"

run_check "ref-chain-resume.md が intervention-catalog.md を参照している" \
  file_contains "$REF_FILE" "intervention-catalog.md"

echo ""
echo "============================================="
echo "Results: PASS=${PASS} FAIL=${FAIL}"
if [[ "${#ERRORS[@]}" -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
  exit 1
fi
exit 0
