#!/usr/bin/env bash
# tdd-framework-detect.sh - Shared test framework detection (Issue #1633 / ADR-039)
#
# Used by: tdd-red-guard.sh, tdd-green-guard.sh
# Provides: detect_framework() → echo "pytest" | "vitest" | "testthat" | "bats" | "unknown"
#
# Detection priority: pytest > vitest > testthat > bats
# Rationale: pytest projects often have a few bats helpers (CI), but bats-primary
# projects rarely have stray test_*.py files. Order chosen for typical mixed twill repos.
#
# Excludes common artifact directories (node_modules, build, .venv, .tox, dist).

detect_framework() {
  local _excl='-not -path "*/node_modules/*" -not -path "*/build/*" -not -path "*/.venv/*" -not -path "*/.tox/*" -not -path "*/dist/*"'
  if eval "find . \\( -name 'test_*.py' -o -name '*_test.py' \\) $_excl 2>/dev/null" | grep -q .; then
    echo "pytest"
  elif eval "find . \\( -name '*.test.ts' -o -name '*.spec.ts' -o -name '*.test.mts' -o -name '*.spec.mts' \\) $_excl 2>/dev/null" | grep -q .; then
    echo "vitest"
  elif eval "find . \\( -name 'test-*.R' -o -name 'test_*.R' \\) $_excl 2>/dev/null" | grep -q .; then
    echo "testthat"
  elif eval "find . -name '*.bats' $_excl 2>/dev/null" | grep -q .; then
    echo "bats"
  else
    echo "unknown"
  fi
}
