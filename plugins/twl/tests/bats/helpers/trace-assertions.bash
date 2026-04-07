#!/usr/bin/env bash
# trace-assertions.bash - Issue #144 / Phase 4-A Layer 2
#
# bats workflow-scenarios 用の trace 検証ヘルパー。
# TWL_CHAIN_TRACE が指す JSON Lines ファイルから step の出現順序を検証する。
#
# 想定 trace 形式（chain-runner.sh trace_event() / dry-run-lib.sh と一致）:
#   {"step":"<name>","phase":"start|end","ts":"...","exit_code":...,"pid":...}
#
# 備考: bats 内では `run` でラップして status を assert することを推奨。
# stderr に詳細を出すので失敗時は ${output} で内容確認できる。

# assert_trace_order <step1> <step2> ... <stepN>
# 与えられた step が trace に「この順序で」現れることを確認する（start phase で判定）。
# 失敗時は exit 1 + stderr に詳細を出力。
assert_trace_order() {
  local trace_file="${TWL_CHAIN_TRACE:-}"
  if [[ -z "$trace_file" || ! -f "$trace_file" ]]; then
    echo "FAIL: trace file not found: ${trace_file:-<unset>}" >&2
    return 1
  fi
  local prev_idx=0 step idx
  for step in "$@"; do
    # start phase の最初の出現行番号を取得
    idx=$(grep -nE "\"step\":\"${step}\",\"phase\":\"start\"" "$trace_file" 2>/dev/null \
      | head -1 | cut -d: -f1)
    if [[ -z "$idx" ]]; then
      echo "FAIL: step '$step' not found in trace ($trace_file)" >&2
      echo "--- trace contents ---" >&2
      cat "$trace_file" >&2
      return 1
    fi
    if (( idx <= prev_idx )); then
      echo "FAIL: step '$step' (line $idx) is at or before previous step (line $prev_idx)" >&2
      echo "--- trace contents ---" >&2
      cat "$trace_file" >&2
      return 1
    fi
    prev_idx=$idx
  done
  return 0
}

# assert_trace_contains <step1> <step2> ... <stepN>
# 与えられた step が trace に（順序問わず）全て出現することを確認する。
assert_trace_contains() {
  local trace_file="${TWL_CHAIN_TRACE:-}"
  if [[ -z "$trace_file" || ! -f "$trace_file" ]]; then
    echo "FAIL: trace file not found: ${trace_file:-<unset>}" >&2
    return 1
  fi
  local step
  for step in "$@"; do
    if ! grep -qE "\"step\":\"${step}\"" "$trace_file"; then
      echo "FAIL: step '$step' not found in trace ($trace_file)" >&2
      echo "--- trace contents ---" >&2
      cat "$trace_file" >&2
      return 1
    fi
  done
  return 0
}

# assert_trace_not_contains <step1> ...
# 与えられた step が trace に出現しないことを確認する。
assert_trace_not_contains() {
  local trace_file="${TWL_CHAIN_TRACE:-}"
  if [[ -z "$trace_file" || ! -f "$trace_file" ]]; then
    # ファイルが無い = 何も含まない → 成功
    return 0
  fi
  local step
  for step in "$@"; do
    if grep -qE "\"step\":\"${step}\"" "$trace_file"; then
      echo "FAIL: step '$step' should NOT be in trace but was found" >&2
      echo "--- trace contents ---" >&2
      cat "$trace_file" >&2
      return 1
    fi
  done
  return 0
}
