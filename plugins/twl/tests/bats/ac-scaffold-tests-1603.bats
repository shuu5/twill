#!/usr/bin/env bats
# ac-scaffold-tests-1603.bats
#
# Issue #1603: .github/workflows/mcp-restart-smoke.yml の pip install uv をバージョン固定に修正
#
# AC1: .github/workflows/mcp-restart-smoke.yml の `pip install uv` (現 line 56) を
#      `pip install "uv==<X.Y.Z>"` 形式に置換する。
# AC2: 採用バージョンが PR description に記載されていること（プロセス AC、機械的検証不可）
# AC3: 修正後の workflow run で 1 回成功させ、PR description にその run URL を記載すること
#      （プロセス AC、機械的検証不可）
# AC4: grep -nE '^\s*pip install\s+"uv==[0-9]+\.[0-9]+(\.[0-9]+)?"' .github/workflows/mcp-restart-smoke.yml
#      が 1 行以上 match すること
# AC5: バージョン未指定の `pip install uv` が同ファイル内に残存しないこと
#
# RED: 全テストは実装前に fail する（現状 pip install uv が未固定のため）
# GREEN: pip install "uv==X.Y.Z" 形式に修正後に PASS する

load 'helpers/common'

WORKFLOW_FILE=""
REPO_GIT_ROOT=""

setup() {
  common_setup
  # REPO_ROOT は plugins/twl を指す。モノリポルートは git rev-parse で取得する。
  local bats_dir
  bats_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  local plugin_root
  plugin_root="$(cd "${tests_dir}/.." && pwd)"
  REPO_GIT_ROOT="$(cd "${plugin_root}" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  WORKFLOW_FILE="${REPO_GIT_ROOT}/.github/workflows/mcp-restart-smoke.yml"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: pip install uv を pip install "uv==<X.Y.Z>" 形式に置換する
#
# RED: 現状 `pip install uv`（バージョン未固定）であるため
#      バージョン固定形式の grep が fail する
# ===========================================================================

@test "ac1: mcp-restart-smoke.yml に pip install uv のバージョン固定形式が存在する" {
  # AC: pip install uv (現 line 56) を pip install "uv==<X.Y.Z>" 形式に置換する
  # RED: 現状はバージョン未固定のため grep が match しない → fail
  [ -f "$WORKFLOW_FILE" ]

  run grep -E '^\s*pip install\s+"uv==[0-9]+\.[0-9]+(\.[0-9]+)?"' "$WORKFLOW_FILE"
  assert_success
}

# ===========================================================================
# AC2: 採用バージョンが PR description に記載されていること（プロセス AC）
# ===========================================================================

@test "ac2: PR description にバージョン記載（プロセス AC）" {
  # AC: 採用バージョンが PR description に記載されていること
  # プロセス AC のため機械的検証不可
  skip "process AC: verified via PR description"
}

# ===========================================================================
# AC3: 修正後の workflow run で 1 回成功させ、PR description に run URL を記載（プロセス AC）
# ===========================================================================

@test "ac3: workflow run 成功と PR description への run URL 記載（プロセス AC）" {
  # AC: 修正後の workflow run で 1 回成功させ、PR description にその run URL を記載すること
  # プロセス AC のため機械的検証不可
  skip "process AC: verified via PR description (run URL)"
}

# ===========================================================================
# AC4: バージョン固定形式が 1 行以上 match すること
#
# grep -nE '^\s*pip install\s+"uv==[0-9]+\.[0-9]+(\.[0-9]+)?"' mcp-restart-smoke.yml
#
# RED: 現状 pip install uv（バージョン未固定）のため grep が 0 件 → fail
# ===========================================================================

@test "ac4: grep でバージョン固定形式の pip install uv が 1 行以上 match する" {
  # AC: grep -nE '^\s*pip install\s+"uv==[0-9]+\.[0-9]+(\.[0-9]+)?"' が 1 行以上 match すること
  # RED: 現状バージョン未固定のため grep が match しない → fail
  [ -f "$WORKFLOW_FILE" ]

  run grep -nE '^\s*pip install\s+"uv==[0-9]+\.[0-9]+(\.[0-9]+)?"' "$WORKFLOW_FILE"
  assert_success
  assert [ "${#lines[@]}" -ge 1 ]
}

# ===========================================================================
# AC5: バージョン未指定の `pip install uv` が残存しないこと
#
# ! grep -nE '^\s*pip install\s+uv\s*$' mcp-restart-smoke.yml
#
# RED: 現状 `pip install uv`（line 56）が残存しているため grep が match → fail
# ===========================================================================

@test "ac5: バージョン未指定の pip install uv が残存しない" {
  # AC: ! grep -nE '^\s*pip install\s+uv\s*$' .github/workflows/mcp-restart-smoke.yml
  # RED: 現状 pip install uv（バージョン未指定）が line 56 に残存しているため
  #      grep が match する → assert_failure が fail（= RED として意図通り fail）
  [ -f "$WORKFLOW_FILE" ]

  run grep -nE '^\s*pip install\s+uv\s*$' "$WORKFLOW_FILE"
  assert_failure
}
