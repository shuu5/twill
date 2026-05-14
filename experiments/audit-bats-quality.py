#!/usr/bin/env python3
"""audit-bats-quality.py — bats unit test quality audit (anti-sabotage).

Phase F anti-sabotage infrastructure (registry-schema.html §10.3).

Scans bats files in test-fixtures/experiments/<category>/ and reports:
  - test count (@test occurrences)
  - skip count (skip statements)
  - assertion count (heuristic: `run`, `jq -e`, `[ ... ]`, `grep -q`, `python3 -c`)
  - skip ratio (skip / test)
  - flags: 100% skip → CRITICAL, skip > 50% → WARNING, assertions < 2/test → WARNING

Pure stdlib (re + json + argparse + pathlib).

Exit codes:
  0  all bats files pass quality threshold
  1  one or more bats files have CRITICAL or WARNING
  2  invocation error

Usage:
  python3 experiments/audit-bats-quality.py [<bats_root>]
  python3 experiments/audit-bats-quality.py --output <json>
  python3 experiments/audit-bats-quality.py --threshold-skip-ratio 0.6
"""
import argparse
import json
import re
import sys
from pathlib import Path

# Heuristic assertion patterns. Count is line-based (one match per line)
# to avoid double-counting when the same line matches multiple patterns
# (e.g., `[[ $status -eq 0 ]]` would otherwise hit 3 patterns).
#
# Patterns intentionally cover:
#   - bats `run cmd args` invocation
#   - bash test forms: [ ... ], [[ ... ]]
#   - exit-code checks: jq -e, grep -q, grep -c
#   - bats-assert library calls
#   - python inline exits (`sys.exit` inside `python3 -c <<EOF`)
#   - bats helper invocations matching `_assert_*` / `_check_*` / `_verify_*`
#     (per-test helper calls — fixes EXP-038/017 false positive where the
#     real assertions live in a shared helper function)
ASSERTION_PATTERNS = [
    r'\brun\b',                  # bats `run cmd ...`
    r'\[\s',                     # bash [ ... ] (POSIX test)
    r'\[\[\s',                   # bash [[ ... ]]
    r'jq\s+-e\b',                # jq with exit-on-false
    r'grep\s+-q\b',              # grep quiet match
    r'grep\s+-c\b',              # grep count
    r'\bassert',                 # bats-assert / inline assert
    r'\bsys\.exit',              # python3 inline exit
    r'\b_(?:assert|check|verify)_\w*',  # helper call patterns (_assert_foo, _check_bar, ...)
]
ASSERTION_RE = re.compile('|'.join(ASSERTION_PATTERNS))
TEST_RE = re.compile(r'^@test\s+', re.MULTILINE)
SKIP_RE = re.compile(r'^\s*skip\b', re.MULTILINE)
TRIVIAL_TRUE_RE = re.compile(r'\[\s*(true|1\s*-eq\s*1|0\s*-eq\s*0)\s*\]')


def audit_bats_file(path, skip_threshold=0.5, assertion_density_threshold=1.0):
    """Audit one .bats file. Returns dict with metrics + flags.

    Line-based assertion counting avoids double-counting when one line matches
    multiple patterns. Trivial-true assertions (`[ true ]`, `[ 1 -eq 1 ]`) are
    counted but also reported separately so high counts of trivial assertions
    can be detected.
    """
    try:
        content = path.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError) as e:
        return {'path': str(path), 'error': str(e), 'flags': ['READ_ERROR']}

    test_count = len(TEST_RE.findall(content))
    skip_count = len(SKIP_RE.findall(content))
    assertion_count = sum(1 for line in content.splitlines() if ASSERTION_RE.search(line))
    trivial_true_count = len(TRIVIAL_TRUE_RE.findall(content))

    flags = []
    if test_count == 0:
        flags.append('NO_TESTS')
    elif skip_count == test_count:
        flags.append('CRITICAL_ALL_SKIP')
    elif skip_count > 0 and skip_count / test_count > skip_threshold:
        flags.append('WARN_HIGH_SKIP_RATIO')

    if test_count > 0:
        density = assertion_count / test_count
        if density < assertion_density_threshold:
            flags.append('WARN_LOW_ASSERTION_DENSITY')

    # Trivial-true bypass detection: many `[ true ]` style assertions inflate
    # the assertion count without verifying anything. Flag if more than half
    # of assertions are trivial.
    if assertion_count > 0 and trivial_true_count / assertion_count > 0.5:
        flags.append('CRITICAL_TRIVIAL_ASSERTIONS')

    return {
        'path': str(path),
        'test_count': test_count,
        'skip_count': skip_count,
        'assertion_count': assertion_count,
        'trivial_true_count': trivial_true_count,
        'skip_ratio': round(skip_count / test_count, 3) if test_count else None,
        'assertion_per_test': round(assertion_count / test_count, 2) if test_count else None,
        'flags': flags,
    }


def main():
    parser = argparse.ArgumentParser(description='Audit bats unit test quality')
    parser.add_argument('bats_root', type=Path, nargs='?', default=None,
                        help='Directory containing bats files (recursive)')
    parser.add_argument('--output', type=Path, default=None)
    parser.add_argument('--threshold-skip-ratio', type=float, default=0.5,
                        help='Skip ratio above this triggers WARN_HIGH_SKIP_RATIO')
    parser.add_argument('--threshold-assertion-density', type=float, default=1.0,
                        help='Assertions/test below this triggers WARN_LOW_ASSERTION_DENSITY')
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    bats_root = args.bats_root or repo_root / 'test-fixtures' / 'experiments'
    if not bats_root.exists():
        print(f'error: bats root not found: {bats_root}', file=sys.stderr)
        return 2

    bats_files = sorted(bats_root.rglob('*.bats'))
    if not bats_files:
        print(f'warning: no .bats files found under {bats_root}', file=sys.stderr)
        return 0

    results = [audit_bats_file(p, args.threshold_skip_ratio, args.threshold_assertion_density)
               for p in bats_files]

    critical = sum(1 for r in results if any(f.startswith('CRITICAL') for f in r['flags']))
    warning = sum(1 for r in results if any(f.startswith('WARN') for f in r['flags']))
    clean = len(results) - critical - warning

    summary = {
        'total': len(results),
        'critical': critical,
        'warning': warning,
        'clean': clean,
    }

    if not args.quiet:
        for r in results:
            if r.get('flags'):
                level = 'CRITICAL' if any(f.startswith('CRITICAL') for f in r['flags']) else 'WARN'
                print(f"{level} {r['path']}: flags={r['flags']} "
                      f"tests={r.get('test_count')} skip={r.get('skip_count')} "
                      f"assertions={r.get('assertion_count')}", file=sys.stderr)
        print(f"\n===== bats quality audit =====", file=sys.stderr)
        print(f"  total:    {summary['total']}", file=sys.stderr)
        print(f"  critical: {summary['critical']}", file=sys.stderr)
        print(f"  warning:  {summary['warning']}", file=sys.stderr)
        print(f"  clean:    {summary['clean']}", file=sys.stderr)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps({'summary': summary, 'results': results}, indent=2, ensure_ascii=False) + '\n',
            encoding='utf-8',
        )

    return 1 if critical > 0 or warning > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
