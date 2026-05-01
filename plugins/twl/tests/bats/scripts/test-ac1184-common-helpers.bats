#!/usr/bin/env bats
# test-ac1184-common-helpers.bats
# Issue #1184: autopilot-launch-*.bats の共通ヘルパーを helpers/common.bash に集約
#
# TDD RED フェーズ: 実装前は全件 FAIL する。
# 実装後に GREEN となることを期待する。

load '../helpers/common'

# ---------------------------------------------------------------------------
# AC1: helpers/common.bash に共通ヘルパーが追加されていること
# ---------------------------------------------------------------------------

@test "ac1: common.bash に _get_tmux_cmd が定義されている" {
  # AC: helpers/common.bash に _get_tmux_cmd() が存在すること
  # RED: 実装前は common.bash に _get_tmux_cmd が存在しないため FAIL する
  local common_file
  common_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../helpers" && pwd)/common.bash"
  grep -qE '^_get_tmux_cmd\(\)' "$common_file"
}

@test "ac1: common.bash に _tmux_cmd_contains が定義されている" {
  # AC: helpers/common.bash に _tmux_cmd_contains() が存在すること
  # RED: 実装前は common.bash に _tmux_cmd_contains が存在しないため FAIL する
  local common_file
  common_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../helpers" && pwd)/common.bash"
  grep -qE '^_tmux_cmd_contains\(\)' "$common_file"
}

@test "ac1: common.bash に _run_launch (2引数版) が定義されている" {
  # AC: helpers/common.bash に _run_launch() (issue, extra_args の2引数版) が存在すること
  # RED: 実装前は common.bash に _run_launch が存在しないため FAIL する
  local common_file
  common_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../helpers" && pwd)/common.bash"
  grep -qE '^_run_launch\(\)' "$common_file"
}

# ---------------------------------------------------------------------------
# AC2: 3ファイルから _get_tmux_cmd / _tmux_cmd_contains の重複定義が削除され、
#      load '../helpers/common' で参照される形に refactor されていること
# ---------------------------------------------------------------------------

@test "ac2: autopilot-launch-merge-context.bats に _get_tmux_cmd の独自定義がない" {
  # AC: merge-context.bats から _get_tmux_cmd の重複定義が削除されていること
  # RED: 実装前は merge-context.bats に _get_tmux_cmd の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-merge-context.bats"
  ! grep -qE '^_get_tmux_cmd\(\)' "$target_file"
}

@test "ac2: autopilot-launch-merge-context.bats に _tmux_cmd_contains の独自定義がない" {
  # AC: merge-context.bats から _tmux_cmd_contains の重複定義が削除されていること
  # RED: 実装前は merge-context.bats に _tmux_cmd_contains の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-merge-context.bats"
  ! grep -qE '^_tmux_cmd_contains\(\)' "$target_file"
}

@test "ac2: autopilot-launch-merge-context.bats に _run_launch の独自定義がない" {
  # AC: merge-context.bats から _run_launch の重複定義が削除されていること
  # RED: 実装前は merge-context.bats に _run_launch の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-merge-context.bats"
  ! grep -qE '^_run_launch\(\)' "$target_file"
}

@test "ac2: autopilot-launch-snapshot-dir.bats に _get_tmux_cmd の独自定義がない" {
  # AC: snapshot-dir.bats から _get_tmux_cmd の重複定義が削除されていること
  # RED: 実装前は snapshot-dir.bats に _get_tmux_cmd の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-snapshot-dir.bats"
  ! grep -qE '^_get_tmux_cmd\(\)' "$target_file"
}

@test "ac2: autopilot-launch-snapshot-dir.bats に _tmux_cmd_contains の独自定義がない" {
  # AC: snapshot-dir.bats から _tmux_cmd_contains の重複定義が削除されていること
  # RED: 実装前は snapshot-dir.bats に _tmux_cmd_contains の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-snapshot-dir.bats"
  ! grep -qE '^_tmux_cmd_contains\(\)' "$target_file"
}

@test "ac2: autopilot-launch-snapshot-dir.bats に _run_launch の独自定義がない" {
  # AC: snapshot-dir.bats から _run_launch の重複定義が削除されていること
  # RED: 実装前は snapshot-dir.bats に _run_launch の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-snapshot-dir.bats"
  ! grep -qE '^_run_launch\(\)' "$target_file"
}

@test "ac2: autopilot-launch-autopilotdir.bats に _get_tmux_cmd の独自定義がない" {
  # AC: autopilotdir.bats から _get_tmux_cmd の重複定義が削除されていること
  # RED: 実装前は autopilotdir.bats に _get_tmux_cmd の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-autopilotdir.bats"
  ! grep -qE '^_get_tmux_cmd\(\)' "$target_file"
}

@test "ac2: autopilot-launch-autopilotdir.bats に _tmux_cmd_contains の独自定義がない" {
  # AC: autopilotdir.bats から _tmux_cmd_contains の重複定義が削除されていること
  # RED: 実装前は autopilotdir.bats に _tmux_cmd_contains の定義が残っているため FAIL する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-autopilotdir.bats"
  ! grep -qE '^_tmux_cmd_contains\(\)' "$target_file"
}

@test "ac2: autopilot-launch-audit-bootstrap.bats には _run_launch の独自定義が残っている (1引数版保持)" {
  # AC: audit-bootstrap.bats の _run_launch (1引数版) は削除しない
  # GREEN: この検証は現在も PASS する（保持確認）
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-audit-bootstrap.bats"
  grep -qE '^_run_launch\(\)' "$target_file"
}

@test "ac2: autopilot-launch-autopilotdir.bats には _run_launch の独自定義が残っている (3引数版保持)" {
  # AC: autopilotdir.bats の _run_launch (3引数版) は削除しない
  # RED: 実装前は _get_tmux_cmd / _tmux_cmd_contains と一緒に _run_launch も残ったまま
  #      実装後は _run_launch(3引数版)のみ残り _get_tmux_cmd / _tmux_cmd_contains は削除される
  # このテスト自体は「3引数版が残っていること」を確認するため、実装後も PASS する
  local target_file
  target_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/autopilot-launch-autopilotdir.bats"
  grep -qE '^_run_launch\(\)' "$target_file"
}

# ---------------------------------------------------------------------------
# AC3: refactor 後、既存 bats 全件が PASS する（機能的等価性の保証）
# ---------------------------------------------------------------------------

@test "ac3: autopilot-launch-merge-context.bats の全テストが PASS する" {
  # AC: refactor 後も merge-context.bats の全テストが PASS すること
  # RED: 実装前は common.bash に _get_tmux_cmd / _tmux_cmd_contains が存在しないため
  #      load 後に関数未定義エラーで FAIL する
  local scripts_dir
  scripts_dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  run bats "${scripts_dir}/autopilot-launch-merge-context.bats"
  assert_success
}

@test "ac3: autopilot-launch-snapshot-dir.bats の全テストが PASS する" {
  # AC: refactor 後も snapshot-dir.bats の全テストが PASS すること
  # RED: 実装前は common.bash に _get_tmux_cmd / _tmux_cmd_contains が存在しないため
  #      load 後に関数未定義エラーで FAIL する
  local scripts_dir
  scripts_dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  run bats "${scripts_dir}/autopilot-launch-snapshot-dir.bats"
  assert_success
}

@test "ac3: autopilot-launch-autopilotdir.bats の全テストが PASS する" {
  # AC: refactor 後も autopilotdir.bats の全テストが PASS すること
  # RED: 実装前は common.bash に _get_tmux_cmd / _tmux_cmd_contains が存在しないため
  #      load 後に関数未定義エラーで FAIL する
  local scripts_dir
  scripts_dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  run bats "${scripts_dir}/autopilot-launch-autopilotdir.bats"
  assert_success
}

# ---------------------------------------------------------------------------
# AC4: 共通化後の重複ヘルパー定義数が 2 件以下であること
#      (baseline: 10件 → 期待値: 2件 = audit-bootstrap の _run_launch + autopilotdir の _run_launch)
# ---------------------------------------------------------------------------

@test "ac4: autopilot-launch-*.bats 内の重複ヘルパー定義数が 2 件以下になっている" {
  # AC: grep -nE '^_(run_launch|get_tmux_cmd|tmux_cmd_contains)\(\)' autopilot-launch-*.bats | wc -l が 2 件以下
  # RED: 実装前は 10 件あるため FAIL する
  local scripts_dir
  scripts_dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  local count
  count=$(grep -nE '^_(run_launch|get_tmux_cmd|tmux_cmd_contains)\(\)' \
    "${scripts_dir}"/autopilot-launch-*.bats | wc -l)
  [ "$count" -le 2 ]
}

# ---------------------------------------------------------------------------
# AC5: common.bash に追加した関数群に出自コメントが付与されていること
# ---------------------------------------------------------------------------

@test "ac5: common.bash の _get_tmux_cmd に extracted from コメントが付与されている" {
  # AC: _get_tmux_cmd 定義の直上に "# extracted from: autopilot-launch-" 形式のコメントが存在する
  # RED: 実装前は _get_tmux_cmd 自体が存在しないため FAIL する
  local common_file
  common_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../helpers" && pwd)/common.bash"
  grep -B1 '^_get_tmux_cmd()' "$common_file" | grep -qF '# extracted from: autopilot-launch-'
}

@test "ac5: common.bash の _tmux_cmd_contains に extracted from コメントが付与されている" {
  # AC: _tmux_cmd_contains 定義の直上に "# extracted from: autopilot-launch-" 形式のコメントが存在する
  # RED: 実装前は _tmux_cmd_contains 自体が存在しないため FAIL する
  local common_file
  common_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../helpers" && pwd)/common.bash"
  grep -B1 '^_tmux_cmd_contains()' "$common_file" | grep -qF '# extracted from: autopilot-launch-'
}

@test "ac5: common.bash の _run_launch に extracted from コメントが付与されている" {
  # AC: _run_launch 定義の直上に "# extracted from: autopilot-launch-" 形式のコメントが存在する
  # RED: 実装前は common.bash に _run_launch 自体が存在しないため FAIL する
  local common_file
  common_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../helpers" && pwd)/common.bash"
  grep -B1 '^_run_launch()' "$common_file" | grep -qF '# extracted from: autopilot-launch-'
}
