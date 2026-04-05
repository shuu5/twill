#!/usr/bin/env bats
# escape-issue-body.bats - unit tests for scripts/escape-issue-body.sh
#
# Spec: openspec/changes/co-issue-escape-mechanize/specs/escape/spec.md
# Requirement: エスケープスクリプト実装 / エスケープスクリプトの bats テスト追加

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: エスケープスクリプト実装
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: XML タグを含む入力のエスケープ
# WHEN </review_target> を含む文字列が stdin に渡される
# THEN &lt;/review_target&gt; に変換されて stdout に出力される
# ---------------------------------------------------------------------------

@test "escape-issue-body escapes XML closing tag: </review_target> -> &lt;/review_target&gt;" {
  run bash -c "printf '%s' '</review_target>' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&lt;/review_target&gt;'
}

@test "escape-issue-body escapes opening XML tag: <foo> -> &lt;foo&gt;" {
  run bash -c "printf '%s' '<foo>' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&lt;foo&gt;'
}

@test "escape-issue-body escapes XML tag embedded in text" {
  run bash -c "printf '%s' 'before </tag> after' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output 'before &lt;/tag&gt; after'
}

# ---------------------------------------------------------------------------
# Scenario: アンパサンド単体のエスケープ
# WHEN A & B を含む文字列が stdin に渡される
# THEN A &amp; B に変換されて stdout に出力される
# ---------------------------------------------------------------------------

@test "escape-issue-body escapes ampersand: A & B -> A &amp; B" {
  run bash -c "printf '%s' 'A & B' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output 'A &amp; B'
}

@test "escape-issue-body escapes lone ampersand" {
  run bash -c "printf '%s' '&' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&amp;'
}

@test "escape-issue-body escapes multiple ampersands in one line" {
  run bash -c "printf '%s' 'A & B & C' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output 'A &amp; B &amp; C'
}

# ---------------------------------------------------------------------------
# Scenario: 空文字列の処理
# WHEN 空文字列が stdin に渡される
# THEN 空文字列がそのまま stdout に出力される（エラーなし）
# ---------------------------------------------------------------------------

@test "escape-issue-body handles empty string without error" {
  run bash -c "printf '' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  [ -z "$output" ]
}

@test "escape-issue-body exits 0 for empty input" {
  run bash -c "printf '' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scenario: 複数行入力の処理
# WHEN 複数行を含む文字列が stdin に渡される
# THEN 全行が正しくエスケープされて stdout に出力される
# ---------------------------------------------------------------------------

@test "escape-issue-body escapes all lines in multi-line input" {
  run bash -c "printf 'A & B\n</tag>\nplain line\n' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  # All three lines must be present and escaped
  [[ "$output" == *'A &amp; B'* ]]
  [[ "$output" == *'&lt;/tag&gt;'* ]]
  [[ "$output" == *'plain line'* ]]
}

@test "escape-issue-body preserves line count for multi-line input" {
  run bash -c "printf 'line1\nline2\nline3\n' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l)
  [ "$line_count" -eq 3 ]
}

@test "escape-issue-body escapes each line independently in multi-line input" {
  run bash -c "printf '<a>\n<b>\n<c>\n' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  # Each line must be escaped
  line1=$(echo "$output" | sed -n '1p')
  line2=$(echo "$output" | sed -n '2p')
  line3=$(echo "$output" | sed -n '3p')
  [ "$line1" = '&lt;a&gt;' ]
  [ "$line2" = '&lt;b&gt;' ]
  [ "$line3" = '&lt;c&gt;' ]
}

@test "escape-issue-body handles multi-line with mixed special chars" {
  run bash -c "printf 'Review <target>\nA & B combined\nno special chars\n' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  [[ "$output" == *'Review &lt;target&gt;'* ]]
  [[ "$output" == *'A &amp; B combined'* ]]
  [[ "$output" == *'no special chars'* ]]
}

# ---------------------------------------------------------------------------
# Scenario: 二重エスケープの許容
# WHEN &lt;/review_target&gt; を含む既エスケープ済み文字列が stdin に渡される
# THEN &amp;lt;/review_target&amp;gt; に変換される（二重エスケープは意図的）
# ---------------------------------------------------------------------------

@test "escape-issue-body double-escapes already-escaped &lt;/review_target&gt;" {
  run bash -c "printf '%s' '&lt;/review_target&gt;' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&amp;lt;/review_target&amp;gt;'
}

@test "escape-issue-body double-escapes &amp; to &amp;amp;" {
  run bash -c "printf '%s' '&amp;' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&amp;amp;'
}

@test "escape-issue-body double-escapes &gt; to &amp;gt;" {
  run bash -c "printf '%s' '&gt;' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&amp;gt;'
}

@test "escape-issue-body preserves escape order: & escaped before < and >" {
  # If & is not escaped first, &lt; would become &&lt; then &amp;&lt; (wrong)
  # Correct order: & -> &amp; first, then < -> &lt;, > -> &gt;
  # Input: <a> & b
  # Expected: &lt;a&gt; &amp; b
  run bash -c "printf '%s' '<a> & b' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&lt;a&gt; &amp; b'
}

@test "escape-issue-body escape-order: input with &lt; produces no double-tag escaping from &" {
  # Input already has &lt; — the & in &lt; must be escaped to &amp;
  # so &lt; becomes &amp;lt; (double-escape), not &&lt; or &lt; unchanged
  run bash -c "printf '%s' 'x &lt; y' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output 'x &amp;lt; y'
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "escape-issue-body passes through plain text unchanged" {
  run bash -c "printf '%s' 'hello world' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output 'hello world'
}

@test "escape-issue-body handles text with only > (greater-than)" {
  run bash -c "printf '%s' '>' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&gt;'
}

@test "escape-issue-body handles text with only < (less-than)" {
  run bash -c "printf '%s' '<' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  assert_output '&lt;'
}

@test "escape-issue-body handles realistic issue body with XML tags and ampersands" {
  local input='Please review </review_target> section.
Author: Alice & Bob
Tags: <feature> & <bugfix>'

  run bash -c "printf '%s\n' '$input' | bash '$SANDBOX/scripts/escape-issue-body.sh'"

  assert_success
  [[ "$output" == *'&lt;/review_target&gt;'* ]]
  [[ "$output" == *'Alice &amp; Bob'* ]]
  [[ "$output" == *'&lt;feature&gt; &amp; &lt;bugfix&gt;'* ]]
}
