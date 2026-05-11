#!/usr/bin/env bash
# tdd-green-guard.sh - TDD GREEN フェーズ guard
# 全テストが PASS しており、かつ ac-test-mapping.yaml の impl_files が
# git diff に含まれることを確認する。
#
# - 全テスト GREEN なら exit 0、1 件でも fail なら exit 1
# - impl_files が diff に含まれていなければ WARNING (exit 1)
# - 未知フレームワーク時は graceful skip (exit 0 + WARNING)
#
# Usage:
#   bash tdd-green-guard.sh [--mapping <ac-test-mapping.yaml>]

set -uo pipefail

MAPPING_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mapping) MAPPING_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Default mapping path: snapshot 配下を優先、なければ project root
if [[ -z "$MAPPING_FILE" ]]; then
  for candidate in \
    "${SNAPSHOT_DIR:-${CLAUDE_PLUGIN_ROOT:-.}/.dev-session/issue-${ISSUE_NUM:-unknown}}/ac-test-mapping.yaml" \
    "ac-test-mapping.yaml" \
    "${CLAUDE_PLUGIN_ROOT:-.}/ac-test-mapping.yaml"
  do
    if [[ -f "$candidate" ]]; then
      MAPPING_FILE="$candidate"
      break
    fi
  done
fi

# Load shared detect_framework() (Issue #1633 / ADR-039 H1 fix)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/tdd-framework-detect.sh
source "${_SCRIPT_DIR}/lib/tdd-framework-detect.sh"

FRAMEWORK=$(detect_framework)

# === Step 1: テスト実行で GREEN 確認 ===
case "$FRAMEWORK" in
  pytest)
    if ! python3 -m pytest --collect-only -q 2>&1 | grep -q "test session"; then
      echo "ERROR: pytest テスト収集失敗 — テストが生成されていない可能性があります" >&2
      exit 1
    fi
    python3 -m pytest --tb=short -q 2>/dev/null
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -ne 0 ]]; then
      echo "ERROR: テストが FAIL しています。全テスト GREEN になるまで実装を続けてください。" >&2
      exit 1
    fi
    echo "✓ TDD GREEN guard (pytest): 全テスト PASS"
    ;;

  vitest)
    if ! command -v npx &>/dev/null; then
      echo "WARNING: npx が見つかりません — vitest guard をスキップ" >&2
      exit 0
    fi
    npx vitest run --reporter=verbose 2>/dev/null
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -ne 0 ]]; then
      echo "ERROR: テストが FAIL しています。全テスト GREEN になるまで実装を続けてください。" >&2
      exit 1
    fi
    echo "✓ TDD GREEN guard (vitest): 全テスト PASS"
    ;;

  testthat)
    if ! command -v Rscript &>/dev/null; then
      echo "WARNING: Rscript が見つかりません — testthat guard をスキップ" >&2
      exit 0
    fi
    Rscript -e "testthat::test_dir('tests/testthat')" 2>/dev/null
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -ne 0 ]]; then
      echo "ERROR: テストが FAIL しています。全テスト GREEN になるまで実装を続けてください。" >&2
      exit 1
    fi
    echo "✓ TDD GREEN guard (testthat): 全テスト PASS"
    ;;

  bats)
    if ! command -v bats &>/dev/null; then
      echo "WARNING: bats が見つかりません — bats guard をスキップ" >&2
      exit 0
    fi
    mapfile -t BATS_FILES < <(find . -name "*.bats" -not -path "*/node_modules/*" -not -path "*/build/*" 2>/dev/null | head -50)
    if [[ "${#BATS_FILES[@]}" -eq 0 ]]; then
      echo "WARNING: bats テストファイルが見つかりません — guard をスキップ" >&2
      exit 0
    fi
    # stdout を残してデバッグ可能にする (H3 fix: bats fail 時の詳細が必要)
    bats "${BATS_FILES[@]}"
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -ne 0 ]]; then
      echo "ERROR: bats テストが FAIL しています。全テスト GREEN になるまで実装を続けてください。" >&2
      exit 1
    fi
    echo "✓ TDD GREEN guard (bats): ${#BATS_FILES[@]} ファイル全テスト PASS"
    ;;

  unknown)
    echo "WARNING: unknown test framework — green guard skipped" >&2
    exit 0
    ;;
esac

# === Step 2: impl_files diff 検証 ===
if [[ -z "$MAPPING_FILE" || ! -f "$MAPPING_FILE" ]]; then
  echo "WARNING: ac-test-mapping.yaml 未検出 — impl_files 検証をスキップ" >&2
  exit 0
fi

# diff 取得 (origin/main 比較、merge-base fallback)
CHANGED_FILES=""
if _files=$(git diff --name-only origin/main 2>/dev/null) && [[ -n "$_files" ]]; then
  CHANGED_FILES="$_files"
elif _files=$(git diff --name-only HEAD 2>/dev/null) && [[ -n "$_files" ]]; then
  CHANGED_FILES="$_files"
fi

if [[ -z "$CHANGED_FILES" ]]; then
  echo "WARNING: git diff が空 — impl_files 検証をスキップ" >&2
  exit 0
fi

# Python で yaml 解析 + diff 突合
# 変数は環境変数経由で渡す (C1 fix: shell injection 防止、ファイル名に `"` や `\` が含まれても安全)
MISSING=$(MAPPING_FILE="$MAPPING_FILE" CHANGED_FILES="$CHANGED_FILES" python3 - <<'PY'
import os, sys, yaml
mapping_path = os.environ["MAPPING_FILE"]
diff = set(os.environ["CHANGED_FILES"].strip().splitlines())
try:
    with open(mapping_path) as f:
        m = yaml.safe_load(f) or {}
except (OSError, yaml.YAMLError) as e:
    print(f"WARNING: mapping read failed: {e}", file=sys.stderr)
    sys.exit(0)
expected = set()
for entry in m.get("mappings", []):
    for p in entry.get("impl_files", []) or []:
        expected.add(p)
missing = sorted(expected - diff)
if missing:
    print("\n".join(missing))
PY
)

if [[ -n "$MISSING" ]]; then
  echo "ERROR: ac-test-mapping.yaml の impl_files が git diff に含まれていません:" >&2
  echo "$MISSING" | sed 's/^/  - /' >&2
  echo "GREEN 実装が未完了です。impl_files 全件を編集/作成してください。" >&2
  exit 1
fi

echo "✓ TDD GREEN guard: 全テスト PASS + impl_files 全件が diff に含まれる — GREEN フェーズ確立"
