#!/usr/bin/env bash
# verify-coverage.sh — tool-architect PostToolUse helper (spec verify gap detection)
#
# Scans architecture/spec/*.html for inferred / deduced status badges and
# emits warnings to stderr. Designed to run as PostToolUse helper after
# tool-architect edits a spec file, so verify gaps surface in real time.
#
# Behavior (per tool-architecture.html §3.2, EXP-027):
#   - exit 0 always (PostToolUse cannot block; warn-only by design)
#   - stderr: human-readable warning lines per file
#
# Phase C minimum viable: badge counting only. Phase D adds:
#   - git diff new sections without <a class="exp-link"> attribute
#   - changelog.html cross-check (today's entry presence)
#
# Usage:
#   verify-coverage.sh <file1.html> [<file2.html> ...]

set -uo pipefail

if [[ $# -lt 1 ]]; then
    exit 0
fi

total_inferred=0
total_deduced=0

for f in "$@"; do
    [[ -f "$f" && "$f" == *.html ]] || continue
    # Use grep -o + wc -l for occurrence count (grep -c gives line count and
    # under-counts when multiple badges sit on the same line).
    n_inf=$(grep -o '<span class="vs inferred">' "$f" 2>/dev/null | wc -l)
    n_ded=$(grep -o '<span class="vs deduced">' "$f" 2>/dev/null | wc -l)
    if [[ "$n_inf" -gt 0 ]]; then
        echo "warn: $f has ${n_inf} inferred status badge(s) (not yet verified)" >&2
        total_inferred=$((total_inferred + n_inf))
    fi
    if [[ "$n_ded" -gt 0 ]]; then
        echo "warn: $f has ${n_ded} deduced status badge(s) (not yet verified)" >&2
        total_deduced=$((total_deduced + n_ded))
    fi
done

if [[ $((total_inferred + total_deduced)) -gt 0 ]]; then
    echo "verify-coverage: ${total_inferred} inferred + ${total_deduced} deduced unverified claims across ${#} file(s)" >&2
fi
exit 0
