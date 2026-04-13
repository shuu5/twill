#!/usr/bin/env bats
# check-workers-redos.bats - check_workers() ReDoS 対策テスト（Issue #525）
#
# monitor-channel-catalog.md の check_workers() で使用する safe_pattern 変換が
# カタストロフィックバックトラックを起こさないことを保証する。

# safe_pattern 変換ロジック（monitor-channel-catalog.md check_workers() から抽出）
convert_to_safe_pattern() {
  local pattern="$1"
  printf '%s' "${pattern//\*/GLOB_STAR}" | sed 's/[.+?()[\]{}^$|\\]/\\&/g; s/GLOB_STAR/.*/g'
}

# ---------------------------------------------------------------------------
# Case 1: glob 特殊文字を含むパターンが grep -E で valid regex になる（exit 2 なし）
# ---------------------------------------------------------------------------

@test "check_workers safe_pattern: glob wildcard ap-* produces valid grep -E regex" {
  local safe
  safe=$(convert_to_safe_pattern "ap-*")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

@test "check_workers safe_pattern: dot in pattern does not break grep -E" {
  local safe
  safe=$(convert_to_safe_pattern "foo.bar")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

@test "check_workers safe_pattern: plus sign in pattern does not break grep -E" {
  local safe
  safe=$(convert_to_safe_pattern "a+b")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

@test "check_workers safe_pattern: question mark in pattern does not break grep -E" {
  local safe
  safe=$(convert_to_safe_pattern "a?b")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

@test "check_workers safe_pattern: parens in pattern do not break grep -E" {
  local safe
  safe=$(convert_to_safe_pattern "(test)")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

@test "check_workers safe_pattern: brackets in pattern do not break grep -E" {
  local safe
  safe=$(convert_to_safe_pattern "[abc]")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

@test "check_workers safe_pattern: multiple special chars in one pattern do not break grep -E" {
  # ap-*.log のような典型的なパターン
  local safe
  safe=$(convert_to_safe_pattern "ap-*.log")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

# ---------------------------------------------------------------------------
# Case 2: 長大パターンで ReDoS が発生しない（1 秒以内に完了）
# ---------------------------------------------------------------------------

@test "check_workers safe_pattern: 100+ wildcard chars completes within 1 second" {
  # 100 文字超の * を含む長大パターン（ReDoS 再現候補）
  local long_pattern
  long_pattern=$(printf '*%.0s' {1..55})  # 55 個の * で 55 文字

  local safe
  safe=$(convert_to_safe_pattern "$long_pattern")

  # timeout 1s: exit 124 = タイムアウト（= ReDoS 発生）でないこと
  run timeout 1s bash -c "echo 'test' | grep -E '^${safe}$' >/dev/null 2>&1; true"
  [ "$status" -ne 124 ]
}

@test "check_workers safe_pattern: catastrophic backtrack input is neutralized" {
  # カタストロフィックバックトラックを引き起こす典型入力 (a+)+ が
  # safe_pattern 変換後は grep -E で valid regex になること（exit 2 でないこと）
  local pattern="(a+)+"
  local safe
  safe=$(convert_to_safe_pattern "$pattern")
  local exit_code=0
  echo "test" | grep -E "^${safe}$" >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -ne 2 ]
}

# ---------------------------------------------------------------------------
# Case 3: monitor-channel-catalog.md に ReDoS 対策コメントが存在する
# ---------------------------------------------------------------------------

setup() {
  local helpers_dir
  helpers_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_test_dir
  bats_test_dir="$(cd "$helpers_dir/.." && pwd)"
  local tests_dir
  tests_dir="$(cd "$bats_test_dir/.." && pwd)"
  REPO_ROOT="$(cd "$tests_dir/.." && pwd)"
  export REPO_ROOT
}

@test "monitor-channel-catalog: safe_pattern block has ReDoS 対策（Issue #525）comment" {
  local file="$REPO_ROOT/skills/su-observer/refs/monitor-channel-catalog.md"
  [ -f "$file" ]
  grep -q 'ReDoS 対策（Issue #525）' "$file"
}

@test "monitor-channel-catalog: safe_pattern conversion line exists in check_workers snippet" {
  local file="$REPO_ROOT/skills/su-observer/refs/monitor-channel-catalog.md"
  [ -f "$file" ]
  grep -q 'safe_pattern' "$file"
  grep -q 'GLOB_STAR' "$file"
}
