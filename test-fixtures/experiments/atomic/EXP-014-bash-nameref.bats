#!/usr/bin/env bats
# EXP-014: bash local -n nameref version check
#
# 検証内容 (GNU bash 4.3 changelog):
#   - `local -n` (nameref declaration) は bash 4.3+ で導入
#   - CI image / runner で bash --version ≥ 4.3 を保証
#   - nameref を使った sample script が動作することを確認
#
# 検証手法 (bats unit):
#   - bash --version で version number 抽出 + ≥ 4.3 確認
#   - nameref を使う minimal sample を inline 実行し、期待 output を assertion

load '../common'

setup() {
    exp_common_setup
}

teardown() {
    exp_common_teardown
}

@test "bash-nameref: bash version >= 4.3 (local -n requirement)" {
    local version_line major minor
    version_line="$(bash --version | head -1)"
    [[ "$version_line" =~ version[[:space:]]([0-9]+)\.([0-9]+) ]]
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    [ "$major" -gt 4 ] || { [ "$major" -eq 4 ] && [ "$minor" -ge 3 ]; }
}

@test "bash-nameref: 'declare -n' is recognized (bash 4.3+ feature)" {
    # bash should not error on `declare -n` syntax
    run bash -c 'declare -n ref; ref=x; echo recognized'
    [ "$status" -eq 0 ]
    [[ "$output" == *recognized* ]]
}

@test "bash-nameref: 'local -n' in function passes value by reference" {
    local script="${SANDBOX}/nameref.sh"
    cat > "$script" <<'EOF'
#!/usr/bin/env bash
set_to_42() {
    local -n ref="$1"
    ref=42
}
target=0
set_to_42 target
echo "$target"
EOF
    chmod +x "$script"
    run bash "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
}

@test "bash-nameref: nameref in main scope captures variable name dynamically" {
    local script="${SANDBOX}/nameref2.sh"
    cat > "$script" <<'EOF'
#!/usr/bin/env bash
foo="hello"
bar_name="foo"
declare -n alias="$bar_name"
echo "$alias"
EOF
    chmod +x "$script"
    run bash "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "bash-nameref: ssot-design.html §3.3 bash 互換性注記 が registry.yaml に反映 (情報的)" {
    # registry.yaml に bash version 要件を inline で記載するかは Phase 2 で判断。
    # 現状は spec 文書 (ssot-design.html) で記載されており、bats では bash version check で代替確認。
    skip "ssot-design.html §3.3 への bash 4.3+ 要件記載は Phase 2 で formal 化"
}
