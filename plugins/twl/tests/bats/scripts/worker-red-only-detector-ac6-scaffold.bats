#!/usr/bin/env bats
# worker-red-only-detector-ac6-scaffold.bats
# Issue #1491 の AC1-AC5 に対応する RED フェーズ用テストスタブ
#
# テストの方針:
#   - 各テストは「現在の bats ファイルに false が残っている状態で FAIL する」
#   - 実装（false → run bash "$DETECTOR_SCRIPT" ... 置換）が完了した時点で GREEN に転じる
#   - GREEN になる条件: worker-red-only-detector.bats の各行が置換済み、かつ DETECTOR_SCRIPT 変数が定義済み
#
# 実装対象ファイル: plugins/twl/tests/bats/scripts/worker-red-only-detector.bats

load '../helpers/common'

TARGET_BATS=""

setup() {
  common_setup
  TARGET_BATS="$REPO_ROOT/tests/bats/scripts/worker-red-only-detector.bats"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: line 386 の `false` が `run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"`
#       + `assert_output --partial "CRITICAL"` に置換されている
# ---------------------------------------------------------------------------

@test "ac1: line 386 の false が DETECTOR_SCRIPT 呼び出しに置換されている" {
  # AC: worker-red-only-detector.bats line 386 の false が
  #     run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json" + assert_output --partial "CRITICAL" に置換されている
  # RED: 現在の bats ファイルに false が残っているため fail する

  [[ -f "$TARGET_BATS" ]] || {
    echo "FAIL: 実装対象ファイルが存在しない: $TARGET_BATS" >&2
    return 1
  }

  # line 386 付近に false ハードコードが残っていれば FAIL
  # 実装後は false が消え、run bash "$DETECTOR_SCRIPT" に置換される
  local context_line
  context_line=$(sed -n '385,388p' "$TARGET_BATS")

  if echo "$context_line" | grep -qF 'false  # RED: 実装前は fail する'; then
    echo "FAIL: AC #1 未実装 — line 386 に 'false  # RED: 実装前は fail する' が残っている" >&2
    echo "期待: run bash \"\$DETECTOR_SCRIPT\" --pr-json \"\$pr_json\" + assert_output --partial \"CRITICAL\"" >&2
    return 1
  fi

  # 置換後の内容確認: DETECTOR_SCRIPT 呼び出し + assert_output "CRITICAL" が存在するか
  if ! grep -qF 'run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"' "$TARGET_BATS"; then
    echo "FAIL: AC #1 未実装 — run bash \"\$DETECTOR_SCRIPT\" --pr-json \"\$pr_json\" が存在しない" >&2
    return 1
  fi
  if ! grep -qF 'assert_output --partial "CRITICAL"' "$TARGET_BATS"; then
    echo "FAIL: AC #1 未実装 — assert_output --partial \"CRITICAL\" が存在しない" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC2: line 403 の `false` が `run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"`
#       + `refute_output --partial "CRITICAL"` に置換されている
# ---------------------------------------------------------------------------

@test "ac2: line 403 の false が DETECTOR_SCRIPT 呼び出しに置換されている" {
  # AC: worker-red-only-detector.bats line 403 の false が
  #     run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json" + refute_output --partial "CRITICAL" に置換されている
  # RED: 現在の bats ファイルに false が残っているため fail する

  [[ -f "$TARGET_BATS" ]] || {
    echo "FAIL: 実装対象ファイルが存在しない: $TARGET_BATS" >&2
    return 1
  }

  local context_line
  context_line=$(sed -n '402,405p' "$TARGET_BATS")

  if echo "$context_line" | grep -qF 'false  # RED: 実装前は fail する'; then
    echo "FAIL: AC #2 未実装 — line 403 に 'false  # RED: 実装前は fail する' が残っている" >&2
    echo "期待: run bash \"\$DETECTOR_SCRIPT\" --pr-json \"\$pr_json\" + refute_output --partial \"CRITICAL\"" >&2
    return 1
  fi

  # 置換後の内容確認: refute_output "CRITICAL" が少なくとも1か所存在するか
  if ! grep -qF 'refute_output --partial "CRITICAL"' "$TARGET_BATS"; then
    echo "FAIL: AC #2 未実装 — refute_output --partial \"CRITICAL\" が存在しない" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC3: line 421 の `false` が `run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"`
#       + `refute_output --partial "CRITICAL"` に置換されている
# ---------------------------------------------------------------------------

@test "ac3: line 421 の false が DETECTOR_SCRIPT 呼び出しに置換されている" {
  # AC: worker-red-only-detector.bats line 421 の false が
  #     run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json" + refute_output --partial "CRITICAL" に置換されている
  # RED: 現在の bats ファイルに false が残っているため fail する

  [[ -f "$TARGET_BATS" ]] || {
    echo "FAIL: 実装対象ファイルが存在しない: $TARGET_BATS" >&2
    return 1
  }

  local context_line
  context_line=$(sed -n '420,423p' "$TARGET_BATS")

  if echo "$context_line" | grep -qF 'false  # RED: 実装前は fail する'; then
    echo "FAIL: AC #3 未実装 — line 421 に 'false  # RED: 実装前は fail する' が残っている" >&2
    echo "期待: run bash \"\$DETECTOR_SCRIPT\" --pr-json \"\$pr_json\" + refute_output --partial \"CRITICAL\"" >&2
    return 1
  fi

  # 置換後の内容確認: DETECTOR_SCRIPT 呼び出しが複数箇所存在するか（AC3 は2箇所目以降）
  local count
  count=$(grep -cF 'run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"' "$TARGET_BATS" || true)
  if [[ "$count" -lt 3 ]]; then
    echo "FAIL: AC #3 未実装 — run bash \"\$DETECTOR_SCRIPT\" の呼び出しが3か所未満 (現在: $count)" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC4: line 438 の `false` が `run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"`
#       + `refute_output --partial "CRITICAL"` に置換されている
# ---------------------------------------------------------------------------

@test "ac4: line 438 の false が DETECTOR_SCRIPT 呼び出しに置換されている" {
  # AC: worker-red-only-detector.bats line 438 の false が
  #     run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json" + refute_output --partial "CRITICAL" に置換されている
  # RED: 現在の bats ファイルに false が残っているため fail する

  [[ -f "$TARGET_BATS" ]] || {
    echo "FAIL: 実装対象ファイルが存在しない: $TARGET_BATS" >&2
    return 1
  }

  local context_line
  context_line=$(sed -n '437,440p' "$TARGET_BATS")

  if echo "$context_line" | grep -qF 'false  # RED: 実装前は fail する'; then
    echo "FAIL: AC #4 未実装 — line 438 に 'false  # RED: 実装前は fail する' が残っている" >&2
    echo "期待: run bash \"\$DETECTOR_SCRIPT\" --pr-json \"\$pr_json\" + refute_output --partial \"CRITICAL\"" >&2
    return 1
  fi

  # 置換後の内容確認: DETECTOR_SCRIPT 呼び出しが4か所存在するか
  local count
  count=$(grep -cF 'run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"' "$TARGET_BATS" || true)
  if [[ "$count" -lt 4 ]]; then
    echo "FAIL: AC #4 未実装 — run bash \"\$DETECTOR_SCRIPT\" の呼び出しが4か所未満 (現在: $count)" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC5: setup() 内に DETECTOR_SCRIPT 変数が定義されている
# ---------------------------------------------------------------------------

@test "ac5: setup() 内に DETECTOR_SCRIPT 変数が定義されている" {
  # AC: setup() 内に DETECTOR_SCRIPT 変数が定義されている
  # RED: 現在の setup() に DETECTOR_SCRIPT が存在しないため fail する

  [[ -f "$TARGET_BATS" ]] || {
    echo "FAIL: 実装対象ファイルが存在しない: $TARGET_BATS" >&2
    return 1
  }

  # DETECTOR_SCRIPT 変数の定義が存在するか
  if ! grep -qE 'DETECTOR_SCRIPT\s*=' "$TARGET_BATS"; then
    echo "FAIL: AC #5 未実装 — DETECTOR_SCRIPT 変数の定義が存在しない" >&2
    echo "期待: setup() 内に DETECTOR_SCRIPT=\"<path-to-detector-wrapper>\" の定義が必要" >&2
    return 1
  fi

  # setup() ブロック内に存在することを確認
  # setup() 関数から teardown() の前の範囲で DETECTOR_SCRIPT を探す
  local in_setup=0
  local found=0
  while IFS= read -r line; do
    if echo "$line" | grep -qE '^setup\s*\(\)'; then
      in_setup=1
    fi
    if [[ "$in_setup" -eq 1 ]]; then
      if echo "$line" | grep -qE 'DETECTOR_SCRIPT\s*='; then
        found=1
        break
      fi
      # teardown() に達したら setup() を抜けた
      if echo "$line" | grep -qE '^teardown\s*\(\)'; then
        break
      fi
    fi
  done < "$TARGET_BATS"

  if [[ "$found" -eq 0 ]]; then
    echo "FAIL: AC #5 未実装 — DETECTOR_SCRIPT が setup() ブロック外にある、または存在しない" >&2
    return 1
  fi
}
