#!/usr/bin/env bats
# record-detection-gap-deps-registered.bats
#
# SSoT 完備性テスト: plugins/twl/deps.yaml に record-detection-gap.sh の
# component entry が正しく登録されていることを assert する
#
# Coverage: --type=unit --coverage=deps-yaml-ssot
#
# AC3: deps.yaml を grep し、record-detection-gap.sh entry の存在と
#      path フィールドが正しいことを検証する

load '../helpers/common'

DEPS_YAML=""

setup() {
    common_setup
    DEPS_YAML="${REPO_ROOT}/deps.yaml"
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# AC3-1: record-detection-gap entry の存在確認
# WHEN plugins/twl/deps.yaml を grep する
# THEN record-detection-gap キーが存在する
# ---------------------------------------------------------------------------

@test "ac3: deps.yaml に record-detection-gap entry が存在する" {
    # AC: deps.yaml に record-detection-gap.sh の component entry が登録されている
    # RED: AC1 実装前は entry が存在しないため fail する
    run grep -q "^  record-detection-gap:" "$DEPS_YAML"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC3-2: path フィールドの正確性確認
# WHEN plugins/twl/deps.yaml の record-detection-gap entry を grep する
# THEN path: skills/su-observer/scripts/record-detection-gap.sh が存在する
# ---------------------------------------------------------------------------

@test "ac3: deps.yaml の record-detection-gap entry に正しい path フィールドがある" {
    # AC: path フィールドが skills/su-observer/scripts/record-detection-gap.sh であること
    # RED: AC1 実装前は entry が存在しないため fail する
    run grep -q "path: skills/su-observer/scripts/record-detection-gap.sh" "$DEPS_YAML"
    [ "$status" -eq 0 ]
}
