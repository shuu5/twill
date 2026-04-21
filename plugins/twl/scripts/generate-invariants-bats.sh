#!/usr/bin/env bash
# generate-invariants-bats.sh - ref-invariants.md から bats テスト網羅性を確認・補完
#
# ref-invariants.md の各不変条件セクションに記載された 検証方法 フィールドを解析し、
# autopilot-invariants.bats に対応する @test が存在するかを確認する。
#
# Usage:
#   bash scripts/generate-invariants-bats.sh [--check] [--generate]
#
# Options:
#   --check     網羅漏れがあれば exit 1（CI 用）
#   --generate  漏れたテストのスタブを autopilot-invariants.bats に追記

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REF_FILE="${REPO_ROOT}/refs/ref-invariants.md"
BATS_FILE="${REPO_ROOT}/tests/bats/invariants/autopilot-invariants.bats"

CHECK_ONLY=false
GENERATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)    CHECK_ONLY=true; shift ;;
    --generate) GENERATE=true; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--check] [--generate]"
      echo "  --check      網羅漏れがあれば exit 1（CI 用）"
      echo "  --generate   漏れたテストのスタブを autopilot-invariants.bats に追記"
      exit 0 ;;
    *) echo "[generate-invariants-bats] Error: 不明な引数: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$REF_FILE" ]] || {
  echo "[generate-invariants-bats] Error: ref-invariants.md が見つかりません: $REF_FILE" >&2
  exit 1
}
[[ -f "$BATS_FILE" ]] || {
  echo "[generate-invariants-bats] Error: autopilot-invariants.bats が見つかりません: $BATS_FILE" >&2
  exit 1
}

# ref-invariants.md の 検証方法 フィールドからテスト名を抽出
# 対象パターン: [`invariant-X: test name`](path)
EXPECTED_TESTS=$(python3 - "$REF_FILE" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    content = f.read()

tests = re.findall(r'\[`(invariant-[A-M][^`]+)`\]', content)
for t in tests:
    print(t.strip())
PYEOF
)

if [[ -z "$EXPECTED_TESTS" ]]; then
  echo "[generate-invariants-bats] ⚠️  ref-invariants.md の 検証方法 フィールドにテスト名が見つかりません" >&2
  exit 0
fi

# autopilot-invariants.bats に存在しないテスト名を検出
# ref-invariants.md は test name の短縮形を使う場合があるため、bats 内に
# ref 名を含む @test が存在すれば coverage ありと見なす（substring match）
BATS_TESTS=$(grep -oP '(?<=@test ")invariant-[A-M][^"]+' "$BATS_FILE" || true)

MISSING=()
while IFS= read -r test_name; do
  [[ -z "$test_name" ]] && continue
  if ! echo "$BATS_TESTS" | grep -qF "$test_name"; then
    MISSING+=("$test_name")
  fi
done <<< "$EXPECTED_TESTS"

EXPECTED_COUNT=$(echo "$EXPECTED_TESTS" | grep -c . || echo 0)

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "✓ generate-invariants-bats: 全 ${EXPECTED_COUNT} テスト網羅済み"
  exit 0
fi

echo "⚠️  generate-invariants-bats: ${#MISSING[@]}/${EXPECTED_COUNT} テスト未実装:" >&2
for t in "${MISSING[@]}"; do
  echo "  - ${t}" >&2
done

if [[ "$GENERATE" == "true" ]]; then
  echo "" >> "$BATS_FILE"
  echo "# Auto-generated stubs — $(date -u +"%Y-%m-%d")" >> "$BATS_FILE"
  for test_name in "${MISSING[@]}"; do
    letter=$(echo "$test_name" | grep -oP '(?<=invariant-)[A-M]' || echo "?")
    cat >> "$BATS_FILE" <<STUB

@test "${test_name}" {
  # AUTO-GENERATED: refs/ref-invariants.md 不変条件 ${letter} の検証方法を実装してください
  skip "未実装: ${test_name}"
}
STUB
  done
  echo "[generate-invariants-bats] ${#MISSING[@]} スタブを $(basename "$BATS_FILE") に追記しました"
fi

[[ "$CHECK_ONLY" == "true" ]] && exit 1
exit 0
