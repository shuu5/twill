#!/usr/bin/env bash
# ac-impl-coverage-check.sh — AC↔PR diff 実装ファイル一致の機械検証
#
# Usage: ac-impl-coverage-check.sh --mapping <path>
# stdin: git diff --name-only origin/main の出力
#
# 出力 (stdout): ref-specialist-output-schema 準拠の Findings JSON 配列
# exit code:
#   0: CRITICAL なし (PASS or INFO のみ)
#   1: CRITICAL 1件以上
#   2: WARNING のみ (INFO 含む可)

set -uo pipefail

MAPPING_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mapping) MAPPING_FILE="$2"; shift 2 ;;
    *) echo "Usage: $(basename "$0") --mapping <path>" >&2
       echo "  stdin: git diff --name-only output" >&2
       exit 1 ;;
  esac
done

if [[ -z "$MAPPING_FILE" ]]; then
  echo "Usage: $(basename "$0") --mapping <path>" >&2
  exit 1
fi

if [[ ! -f "$MAPPING_FILE" ]]; then
  echo "Error: mapping file not found: $MAPPING_FILE" >&2
  exit 1
fi

DIFF_TMPFILE=$(mktemp)
trap 'rm -f "$DIFF_TMPFILE"' EXIT
cat > "$DIFF_TMPFILE"

python3 - "$MAPPING_FILE" "$DIFF_TMPFILE" <<'PYEOF'
import sys
import json
import os

mapping_file = sys.argv[1]
diff_file = sys.argv[2]

try:
    import yaml
except ImportError:
    print("[]")
    sys.exit(0)

with open(diff_file) as f:
    diff_files = set(line.strip() for line in f if line.strip())

try:
    with open(mapping_file) as f:
        data = yaml.safe_load(f) or {}
except Exception as e:
    print(f"Error reading mapping: {e}", file=sys.stderr)
    print("[]")
    sys.exit(0)

mappings = data.get("mappings", []) or []
findings = []
has_critical = False
has_warning = False

entries_with_impl = sum(
    1 for m in mappings
    if "impl_files" in m and m.get("impl_files") is not None
)
total = len(mappings)

if total > 0 and entries_with_impl == 0:
    findings.append({
        "severity": "WARNING",
        "category": "ac-impl-coverage-skip",
        "confidence": 80,
        "file": mapping_file,
        "line": 1,
        "message": "mapping 内全 AC で impl_files が欠落 — 新規生成 mapping は impl_files 必須",
        "evidence": f"total_entries: {total} / entries_with_impl: 0"
    })
    has_warning = True

for entry in mappings:
    ac_index = str(entry.get("ac_index", "?"))
    ac_text = str(entry.get("ac_text", ""))[:80]

    if "impl_files" not in entry:
        if entries_with_impl > 0:
            findings.append({
                "severity": "INFO",
                "category": "ac-impl-coverage-skip",
                "confidence": 70,
                "file": mapping_file,
                "line": 1,
                "message": f"AC #{ac_index} の impl_files が不在 — LLM fallback",
                "evidence": f"ac_index: {ac_index}"
            })
        continue

    impl_files = entry.get("impl_files") or []
    match_count = sum(1 for f in impl_files if f in diff_files)

    if match_count == 0:
        expected = ", ".join(impl_files) if impl_files else "(empty)"
        diff_sample = ", ".join(sorted(diff_files)[:5])
        findings.append({
            "severity": "CRITICAL",
            "category": "ac-impl-coverage-missing",
            "confidence": 90,
            "file": mapping_file,
            "line": 1,
            "message": f"AC #{ac_index} 『{ac_text}』の impl_files が PR diff に存在しない",
            "evidence": f"expected: [{expected}] / diff: [{diff_sample}]"
        })
        has_critical = True

print(json.dumps(findings))
if has_critical:
    sys.exit(1)
elif has_warning:
    sys.exit(2)
else:
    sys.exit(0)
PYEOF
exit $?
