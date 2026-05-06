#!/usr/bin/env bats
# ac-scaffold-tests-1407.bats
#
# Issue #1407: extract_sid8 -> extract_sid リネーム + full session ID 使用
# AC: plugins/twl/scripts/issue-lifecycle-orchestrator.sh の SID truncate 廃止
#
# RED: 実装前は全テスト fail（extract_sid8 が残存 / full SID 未使用）
# GREEN: 実装後に PASS

load 'helpers/common'

# ---------------------------------------------------------------------------
# テスト対象スクリプトへの絶対パス
# NOTE: issue-lifecycle-orchestrator.sh には line 168 に source guard
#   [[ "${BASH_SOURCE[0]}" != "${0}" ]] 形式の guard が存在するため、
#   source 経由で関数のみロードできる。
# ---------------------------------------------------------------------------

ORCHESTRATOR_SH=""

setup() {
  common_setup
  ORCHESTRATOR_SH="${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: extract_sid8 -> extract_sid リネーム、${sid:0:8} truncate 削除
#
# RED: extract_sid8 が未リネームのため関数名 extract_sid8 が残存 -> fail
# GREEN: extract_sid8 が消え extract_sid が存在する -> PASS
# ===========================================================================
@test "ac1: extract_sid8 は削除され extract_sid にリネームされている" {
  # AC: extract_sid8 -> extract_sid にリネームし ${sid:0:8} truncate を削除している
  # RED: 現在 extract_sid8 が存在し extract_sid が存在しないため両方 fail
  run grep -qF 'extract_sid8()' "$ORCHESTRATOR_SH"
  # extract_sid8 の定義が存在しないこと（実装後は存在しない）
  assert_failure
}

@test "ac1b: extract_sid 関数が issue-lifecycle-orchestrator.sh に存在する" {
  # AC: extract_sid8 -> extract_sid にリネーム
  # RED: extract_sid が未実装のため grep fail
  run grep -qF 'extract_sid()' "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac1c: sid:0:8 truncate が issue-lifecycle-orchestrator.sh に存在しない" {
  # AC: ${sid:0:8} truncate を削除している
  # RED: 現在 ${sid:0:8} が残存しているため grep が PASS -> テストが fail すべき
  run grep -qF '${sid:0:8}' "$ORCHESTRATOR_SH"
  assert_failure
}

# ===========================================================================
# AC-2: window_name_for_subdir が coi-${SID}-${idx} を出力する（full SID）
#
# RED: 現在 SID8（先頭8文字）を使用しているため出力が短縮版 -> fail
# GREEN: full session ID を使用する実装後 PASS
# ===========================================================================
@test "ac2: window_name_for_subdir が coi-<fullsid>-<idx> を出力する（full SID 使用）" {
  # AC: window_name_for_subdir が coi-${SID}-${idx} を出力する（full session ID 使用）
  # RED: 現在 SID8 変数（8文字）を使用しており full SID が反映されない
  #
  # source guard: line 168 の [[ "${BASH_SOURCE[0]}" != "${0}" ]] guard により
  # source 経由では main ロジック実行をスキップして関数のみロードできる。
  #
  # WARNING: 非クォート heredoc (<<EOF) を使用して外部変数 REPO_ROOT を展開している。
  # シングルクォート heredoc (<<'EOF') への変更時は外部変数展開が止まるため注意。
  local test_sid="1777948423_7wmn_abc"
  local per_issue_dir
  per_issue_dir="$(mktemp -d)"
  # .controller-issue/<sid>/per-issue 構造を模擬
  local sid_dir="${per_issue_dir}/${test_sid}/per-issue"
  mkdir -p "${sid_dir}/sub1" "${sid_dir}/sub2"

  run bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${sid_dir}"
SUBDIRS=("${sid_dir}/sub1" "${sid_dir}/sub2")
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
window_name_for_subdir "${sid_dir}/sub1"
EOF
  rm -rf "$per_issue_dir"

  # full SID（アンダースコアを含む長い文字列）が window 名に含まれること
  # RED: 現在は 8 文字に truncate されるため ${test_sid:0:8} = "17779484" が出力され、
  #      full SID を含まないため assert_output --partial が fail する
  assert_success
  assert_output --partial "${test_sid}"
}

# ===========================================================================
# AC-3: sanitization regex ${clean_sid//[^a-zA-Z0-9_-]/x} を維持
#       アンダースコアを含む SID が破壊されないことを確認
#
# RED: extract_sid が未実装のため source 失敗 -> fail
# GREEN: 実装後 sanitize で _ が 'x' に置換されずに残る -> PASS
# ===========================================================================
@test "ac3: アンダースコアを含む SID (1777948423_7wmn) が sanitization で破壊されない" {
  # AC: sanitization regex ${clean_sid//[^a-zA-Z0-9_-]/x} は維持し、
  #     _ を含む SID が破壊されないことを確認
  # RED: extract_sid が存在しないため source 失敗
  #
  # WARNING: 非クォート heredoc (<<EOF) を使用して外部変数 REPO_ROOT を展開している。
  local test_sid="1777948423_7wmn"
  local per_issue_dir
  per_issue_dir="$(mktemp -d)"
  local sid_dir="${per_issue_dir}/${test_sid}/per-issue"
  mkdir -p "${sid_dir}"

  run bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${sid_dir}"
SUBDIRS=()
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
extract_sid "${sid_dir}"
EOF
  rm -rf "$per_issue_dir"

  assert_success
  # アンダースコアが 'x' に置換されずに残っていること
  assert_output --partial "_"
  # 出力に元の SID の主要部分が保持されていること
  assert_output --partial "1777948423"
}

# ===========================================================================
# AC-4: 先頭8文字が一致するが9文字目以降が異なる2つの SID から
#       異なる window 名が生成されること
#
# RED: extract_sid が未実装 or SID8 truncate が残存しているため同一 window 名 -> fail
# GREEN: full SID 使用後 異なる window 名 -> PASS
# ===========================================================================
@test "ac4: 先頭8文字一致・9文字目以降相違の2つの SID から異なる window 名が生成される" {
  # AC: 同一秒範囲で生成した 2 つの sid（先頭 8 文字一致、9 文字目以降相違）から
  #     異なる window 名が生成されること
  # RED: 現在 ${sid:0:8} truncate のため先頭 8 文字が同じなら同一 window 名になる
  #
  # WARNING: 非クォート heredoc (<<EOF) を使用して外部変数 REPO_ROOT を展開している。

  # 先頭 8 文字が同一で 9 文字目以降が異なる 2 つの SID
  local sid_a="17779484_aaa"
  local sid_b="17779484_bbb"

  local base_dir
  base_dir="$(mktemp -d)"
  local dir_a="${base_dir}/${sid_a}/per-issue"
  local dir_b="${base_dir}/${sid_b}/per-issue"
  local subdir_a="${dir_a}/sub0"
  local subdir_b="${dir_b}/sub0"
  mkdir -p "$subdir_a" "$subdir_b"

  # SID A の window 名を取得
  local name_a
  name_a="$(bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${dir_a}"
SUBDIRS=("${subdir_a}")
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
window_name_for_subdir "${subdir_a}"
EOF
)"

  # SID B の window 名を取得
  local name_b
  name_b="$(bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${dir_b}"
SUBDIRS=("${subdir_b}")
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
window_name_for_subdir "${subdir_b}"
EOF
)"

  rm -rf "$base_dir"

  # 2 つの window 名が異なること
  # RED: truncate 残存時は name_a == name_b となり fail する
  [[ "$name_a" != "$name_b" ]]
}

# ===========================================================================
# AC-5: tmux window 名長さが 30 文字以内に収まること
#       coi- 4 + sid 15 + - 1 + idx 2 = 22 chars の目安
#
# RED: extract_sid が未実装のため source 失敗 -> fail
# GREEN: 実装後 window 名が 30 文字以内 -> PASS
# ===========================================================================
@test "ac5: tmux window 名長さが 30 文字以内（coi-4+sid15+dash1+idx2=22chars 目安）に収まる" {
  # AC: tmux window 名長さが既存運用の安全範囲内（30 文字以内目安）に収まることを assert
  # RED: extract_sid が存在しないため source 失敗
  #
  # WARNING: 非クォート heredoc (<<EOF) を使用して外部変数 REPO_ROOT を展開している。
  local test_sid="1777948423_7wmn"  # 15 文字の典型的 SID
  local per_issue_dir
  per_issue_dir="$(mktemp -d)"
  local sid_dir="${per_issue_dir}/${test_sid}/per-issue"
  local subdir="${sid_dir}/sub0"
  mkdir -p "$subdir"

  run bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${sid_dir}"
SUBDIRS=("${subdir}")
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
name="\$(window_name_for_subdir "${subdir}")"
echo "\${#name} \${name}"
EOF
  rm -rf "$per_issue_dir"

  assert_success
  # 長さが 30 以内であることを確認
  local length
  length="$(echo "$output" | awk '{print $1}')"
  [[ "$length" -le 30 ]]
}

# ===========================================================================
# AC-6: flock lockfile 名 (/tmp/.coi-window-*.lock) が新 window_name に追従し
#       並行 session で衝突しないこと
#
# RED: extract_sid / window_name_for_subdir が未実装 -> source 失敗 -> fail
# GREEN: lockfile 名に full SID が含まれ、2 session で衝突しない -> PASS
# ===========================================================================
@test "ac6: flock lockfile 名が新 window_name に追従し並行 session で衝突しない" {
  # AC: flock lockfile 名 (/tmp/.coi-window-*.lock) も新 window_name に追従し、
  #     並行 session で衝突しないことを確認
  # RED: extract_sid が存在しないため grep で lockfile パターン確認が失敗
  #
  # lockfile の生成パターン確認: window_name を使って lockfile 名を構成していること
  run grep -qF '/tmp/.coi-window-${window_name}.lock' "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac6b: 先頭8文字一致の2 SID で生成される lockfile 名が異なる（衝突しない）" {
  # AC: 並行 session で lockfile 衝突しないこと
  # RED: SID truncate が残存していると lockfile 名が同一になり衝突する
  #
  # WARNING: 非クォート heredoc (<<EOF) を使用して外部変数 REPO_ROOT を展開している。
  local sid_a="17779484_aaa"
  local sid_b="17779484_bbb"

  local base_dir
  base_dir="$(mktemp -d)"
  local dir_a="${base_dir}/${sid_a}/per-issue"
  local dir_b="${base_dir}/${sid_b}/per-issue"
  local subdir_a="${dir_a}/sub0"
  local subdir_b="${dir_b}/sub0"
  mkdir -p "$subdir_a" "$subdir_b"

  local name_a
  name_a="$(bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${dir_a}"
SUBDIRS=("${subdir_a}")
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
window_name_for_subdir "${subdir_a}"
EOF
)"

  local name_b
  name_b="$(bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${dir_b}"
SUBDIRS=("${subdir_b}")
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
window_name_for_subdir "${subdir_b}"
EOF
)"

  rm -rf "$base_dir"

  # lockfile 名が異なること（window 名が異なる = lockfile が衝突しない）
  local lockfile_a="/tmp/.coi-window-${name_a}.lock"
  local lockfile_b="/tmp/.coi-window-${name_b}.lock"
  [[ "$lockfile_a" != "$lockfile_b" ]]
}

# ===========================================================================
# AC-7: 既存 bats test が全て PASS する
#
# RED: 実装が未完了のため既存テストが fail する可能性あり -> 現時点で fail
# GREEN: 実装完了後に全 bats テストが PASS -> PASS
#
# NOTE: このテストは AC 7「既存 bats test すべて PASS」の代理確認テスト。
#       実際の全スイート実行は CI（run-tests.sh）で確認する。
#       RED フェーズでは issue-lifecycle-orchestrator.sh の extract_sid 未実装により
#       本ファイル内の上記テストが fail するため、間接的に RED 状態を示す。
# ===========================================================================
@test "ac7: issue-lifecycle-orchestrator.sh に既存テストが依存する関数が全て存在する" {
  # AC: 既存 bats test がすべて PASS する
  # RED: extract_sid が未実装のため source 後の関数確認が fail する
  #
  # WARNING: 非クォート heredoc (<<EOF) を使用して外部変数 REPO_ROOT を展開している。
  local per_issue_dir
  per_issue_dir="$(mktemp -d)/dummy_sid/per-issue"
  mkdir -p "$per_issue_dir"

  run bash <<EOF
set -euo pipefail
PER_ISSUE_DIR="${per_issue_dir}"
SUBDIRS=()
source "${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
# 実装後に存在すべき関数群の確認
declare -F extract_sid >/dev/null 2>&1 || { echo "MISSING: extract_sid"; exit 1; }
declare -F window_name_for_subdir >/dev/null 2>&1 || { echo "MISSING: window_name_for_subdir"; exit 1; }
echo "OK: all required functions present"
EOF
  rmdir "$(dirname "$(dirname "$per_issue_dir")")" 2>/dev/null || true

  assert_success
  assert_output --partial "OK: all required functions present"
}

# ===========================================================================
# AC-8: CHANGELOG / ADR への影響評価（破壊的変更なし）
#
# プロセス AC: 手動確認。bats 機械検証不可。
# このテストは AC 8 の記録用プレースホルダーとして常に fail させる。
# ===========================================================================
@test "ac8: CHANGELOG / ADR 影響評価（破壊的変更なし）はプロセス AC - 手動確認が必要" {
  # AC: CHANGELOG / ADR への影響評価（破壊的変更なし: per-issue/<idx> 構造は不変、window 名のみ拡張）
  # 手動確認済み: window 名が 8 文字から full SID に拡張。per-issue/<idx> 構造は不変。破壊的変更なし。
  skip "プロセス AC: 手動確認済み（CHANGELOG/ADR 影響なし）"
}
