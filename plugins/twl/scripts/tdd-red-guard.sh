#!/usr/bin/env bash
# tdd-red-guard.sh - TDD RED フェーズ guard
# テストが存在し、少なくとも 1 件が fail していることを確認する。
# 全テストが PASS している場合は WARNING を出力して非ゼロで終了。
#
# Usage:
#   bash tdd-red-guard.sh [--test-dir <dir>]

set -uo pipefail

TEST_DIR="${1:-}"

detect_framework() {
  if find . -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -q .; then
    echo "pytest"
  elif find . -name "*.test.ts" -o -name "*.spec.ts" 2>/dev/null | grep -q .; then
    echo "vitest"
  elif find . -name "test-*.R" -o -name "test_*.R" 2>/dev/null | grep -q .; then
    echo "testthat"
  else
    echo "unknown"
  fi
}

FRAMEWORK=$(detect_framework)

case "$FRAMEWORK" in
  pytest)
    # テスト収集確認
    if ! python3 -m pytest --collect-only -q 2>&1 | grep -q "test session"; then
      echo "ERROR: pytest テスト収集失敗 — テストが生成されていない可能性があります" >&2
      exit 1
    fi

    COLLECTED=$(python3 -m pytest --collect-only -q 2>/dev/null | grep -c "^<" || echo "0")
    if [[ "$COLLECTED" -eq 0 ]]; then
      echo "ERROR: テストが 0 件です。test-scaffold を再実行してください" >&2
      exit 1
    fi

    # 実行して fail を確認（--no-header で簡潔出力）
    python3 -m pytest -x --tb=no -q 2>/dev/null
    EXIT_CODE=$?

    if [[ "$EXIT_CODE" -eq 0 ]]; then
      echo "WARNING: 全テストが PASS しています。RED フェーズの起点として適切ではありません。" >&2
      echo "実装前に全 PASS している場合、テストが実装を検証できていない可能性があります。" >&2
      echo "テスト内容を review してください。" >&2
      exit 1
    fi

    echo "✓ TDD RED guard: ${COLLECTED} テスト収集済み、少なくとも 1 件が fail — RED フェーズ確立"
    ;;

  vitest)
    if ! command -v npx &>/dev/null; then
      echo "WARNING: npx が見つかりません — vitest guard をスキップ" >&2
      exit 0
    fi
    npx vitest run --reporter=verbose 2>/dev/null
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -eq 0 ]]; then
      echo "WARNING: 全テストが PASS しています。RED フェーズの起点として適切ではありません。" >&2
      exit 1
    fi
    echo "✓ TDD RED guard: 少なくとも 1 件が fail — RED フェーズ確立"
    ;;

  testthat)
    if ! command -v Rscript &>/dev/null; then
      echo "WARNING: Rscript が見つかりません — testthat guard をスキップ" >&2
      exit 0
    fi
    Rscript -e "testthat::test_dir('tests/testthat')" 2>/dev/null
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -eq 0 ]]; then
      echo "WARNING: 全テストが PASS しています。RED フェーズの起点として適切ではありません。" >&2
      exit 1
    fi
    echo "✓ TDD RED guard: 少なくとも 1 件が fail — RED フェーズ確立"
    ;;

  unknown)
    echo "WARNING: テストフレームワーク未検出 — guard をスキップ" >&2
    exit 0
    ;;
esac
