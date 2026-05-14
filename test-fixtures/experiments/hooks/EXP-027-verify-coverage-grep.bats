#!/usr/bin/env bats
# EXP-027: verify-coverage.sh grep boundary
#
# 検証内容 (tool-architecture.html §3.2):
#   verify-coverage.sh が architecture/spec/*.html の <span class="vs inferred|deduced">
#   badge を grep で検出し、warn を stderr に出す。verified / experiment-verified は
#   検出しない (4-state badge の前 2 状態のみが target)。
#
# 検証手法 (bats unit):
#   - SANDBOX に 4 状態の status badge を含む HTML fixture を生成
#   - verify-coverage.sh を呼び stderr の warn line 数 / 内容を assertion

load '../common'

setup() {
    exp_common_setup
    VERIFY_COVERAGE="${REPO_ROOT}/plugins/twl/scripts/lib/verify-coverage.sh"
}

teardown() {
    exp_common_teardown
}

@test "verify-coverage: script exists and is executable" {
    [ -x "$VERIFY_COVERAGE" ]
}

@test "verify-coverage: inferred badge は warn を出す" {
    local fix="${SANDBOX}/has-inferred.html"
    cat > "$fix" <<'EOF'
<html><body>
  <span class="vs inferred">inferred</span>
</body></html>
EOF
    run bash "$VERIFY_COVERAGE" "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 inferred"* ]] || [[ "$output" == *"has 1 inferred"* ]]
}

@test "verify-coverage: deduced badge は warn を出す" {
    local fix="${SANDBOX}/has-deduced.html"
    cat > "$fix" <<'EOF'
<html><body>
  <span class="vs deduced">deduced</span>
</body></html>
EOF
    run bash "$VERIFY_COVERAGE" "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 deduced"* ]] || [[ "$output" == *"has 1 deduced"* ]]
}

@test "verify-coverage: verified のみの HTML は warn を出さない (grep boundary)" {
    local fix="${SANDBOX}/clean.html"
    cat > "$fix" <<'EOF'
<html><body>
  <span class="vs verified">verified</span>
  <span class="vs experiment-verified">experiment-verified</span>
</body></html>
EOF
    run bash "$VERIFY_COVERAGE" "$fix"
    [ "$status" -eq 0 ]
    # stdout は空 (script は stderr にのみ出力するが run は両方 capture)
    # warn 文字列が含まれないことを確認
    [[ "$output" != *"warn:"* ]]
    [[ "$output" != *"inferred"* ]]
    [[ "$output" != *"deduced"* ]]
}

@test "verify-coverage: inferred + deduced 複合は両方 warn する" {
    local fix="${SANDBOX}/mixed.html"
    cat > "$fix" <<'EOF'
<html><body>
  <span class="vs inferred">inferred</span>
  <span class="vs inferred">inferred</span>
  <span class="vs deduced">deduced</span>
  <span class="vs verified">verified</span>
</body></html>
EOF
    run bash "$VERIFY_COVERAGE" "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 inferred"* ]]
    [[ "$output" == *"1 deduced"* ]]
}

@test "verify-coverage: 複数 file の集計 total 行を出力" {
    local f1="${SANDBOX}/a.html"
    local f2="${SANDBOX}/b.html"
    cat > "$f1" <<'EOF'
<span class="vs inferred">inferred</span>
EOF
    cat > "$f2" <<'EOF'
<span class="vs deduced">deduced</span>
EOF
    run bash "$VERIFY_COVERAGE" "$f1" "$f2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verify-coverage:"* ]]
    [[ "$output" == *"1 inferred"* ]]
    [[ "$output" == *"1 deduced"* ]]
}

@test "verify-coverage: 引数なしは no-op (exit 0)" {
    run bash "$VERIFY_COVERAGE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "verify-coverage: 存在しない file は skip" {
    run bash "$VERIFY_COVERAGE" "${SANDBOX}/nonexistent.html"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "verify-coverage: .md file は skip (HTML のみ対象、grep boundary)" {
    local fix="${SANDBOX}/has-inferred.md"
    cat > "$fix" <<'EOF'
<span class="vs inferred">inferred</span>
EOF
    run bash "$VERIFY_COVERAGE" "$fix"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
