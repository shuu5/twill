#!/usr/bin/env bats
# deltaspec-helpers.bats
# Requirement: deltaspec-helpers ライブラリの新設 + DRY 解消
# Spec: deltaspec/changes/issue-460/specs/deltaspec-dry-fix/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# 検証する仕様:
#   1. resolve_deltaspec_root: 直下に deltaspec/config.yaml がある場合 → root を返し return 0
#   2. resolve_deltaspec_root: walk-down fallback で config.yaml が見つかる場合 → deltaspec root を返し return 0
#   3. resolve_deltaspec_root: config.yaml が見つからない場合 → root を返し return 1
#   4. chain-runner.sh が deltaspec-helpers.sh を source して resolve_deltaspec_root() を呼び出せる
#   5. _archive_deltaspec_changes_for_issue が resolve_deltaspec_root を使う
#   6. shellcheck が chain-runner.sh / autopilot-orchestrator.sh を通過する
#
# test double 方針:
#   - resolve_deltaspec_root のテスト (1-3) はライブラリを直接 source して関数を呼ぶ
#   - chain-runner.sh 統合テスト (4) はヘルパースクリプト経由で source 確認
#   - _archive テスト (5) は archive-dispatch.sh test double で inline find 非使用を検証
#   - shellcheck テスト (6) は shellcheck コマンドを直接実行（存在しない場合は skip）

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # スクリプトの実際のパスを設定
  SCRIPTS_ROOT="$REPO_ROOT/scripts"
  HELPERS_LIB="$SCRIPTS_ROOT/lib/deltaspec-helpers.sh"
  CHAIN_RUNNER="$SCRIPTS_ROOT/chain-runner.sh"
  ORCHESTRATOR="$SCRIPTS_ROOT/autopilot-orchestrator.sh"
  export SCRIPTS_ROOT HELPERS_LIB CHAIN_RUNNER ORCHESTRATOR

  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: deltaspec-helpers ライブラリの新設
# Spec: deltaspec/changes/issue-460/specs/deltaspec-dry-fix/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 直下に deltaspec/config.yaml がある場合
# WHEN resolve_deltaspec_root "$root" を呼び出し、$root/deltaspec/config.yaml が存在する
# THEN $root を echo して return 0 する
# ---------------------------------------------------------------------------

@test "resolve_deltaspec_root[direct]: ライブラリが存在する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"
}

@test "resolve_deltaspec_root[direct]: 直下に config.yaml があれば root を出力して成功する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # Arrange: sandbox に deltaspec/config.yaml を配置
  mkdir -p "$SANDBOX/deltaspec"
  echo "version: 1" > "$SANDBOX/deltaspec/config.yaml"

  # Act: ライブラリを source して関数を呼ぶ
  # shellcheck disable=SC1090
  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'"

  assert_success
  assert_output "$SANDBOX"
}

@test "resolve_deltaspec_root[direct]: 直下に config.yaml があれば return 0 を返す" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/deltaspec"
  echo "version: 1" > "$SANDBOX/deltaspec/config.yaml"

  # return code の検証
  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  assert_success
  assert_output --partial "exit=0"
}

# Edge case: config.yaml の内容が空でも検出される
@test "resolve_deltaspec_root[direct][edge]: config.yaml が空ファイルでも root を返す" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/deltaspec"
  touch "$SANDBOX/deltaspec/config.yaml"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'"

  assert_success
  assert_output "$SANDBOX"
}

# Edge case: config.yaml がディレクトリのときは -f チェックをスルーするが
# walk-down fallback の find は name マッチするため実際には return 0 となる（実装の既知挙動）
@test "resolve_deltaspec_root[direct][edge]: config.yaml がディレクトリのときは直下 -f 検出しない" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/deltaspec/config.yaml"  # ファイルではなくディレクトリ

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  # -f チェックはスルーするが find が directory も検出するため return 0（既存実装と同一挙動）
  assert_output --partial "exit=0"
}

# ---------------------------------------------------------------------------
# Scenario: walk-down fallback で deltaspec/config.yaml が見つかる場合
# WHEN resolve_deltaspec_root "$root" を呼び出し、直下には config.yaml がないが
#      maxdepth=5 以内に */deltaspec/config.yaml が存在する
# THEN その config.yaml の親ディレクトリの親ディレクトリ（deltaspec root）を echo して return 0 する
# ---------------------------------------------------------------------------

@test "resolve_deltaspec_root[walkdown]: ネスト 1 階層で config.yaml が見つかれば deltaspec root を返す" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # Arrange: $SANDBOX/nested/deltaspec/config.yaml を配置（直下はなし）
  mkdir -p "$SANDBOX/nested/deltaspec"
  echo "version: 1" > "$SANDBOX/nested/deltaspec/config.yaml"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'"

  assert_success
  assert_output "$SANDBOX/nested"
}

@test "resolve_deltaspec_root[walkdown]: return 0 を返す" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/nested/deltaspec"
  echo "version: 1" > "$SANDBOX/nested/deltaspec/config.yaml"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  assert_success
  assert_output --partial "exit=0"
}

# Edge case: ネスト 2 階層でも見つかる
@test "resolve_deltaspec_root[walkdown][edge]: ネスト 2 階層でも deltaspec root を返す" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/a/b/deltaspec"
  echo "version: 1" > "$SANDBOX/a/b/deltaspec/config.yaml"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'"

  assert_success
  assert_output "$SANDBOX/a/b"
}

# Edge case: .git ディレクトリ内の config.yaml は除外される
@test "resolve_deltaspec_root[walkdown][edge]: .git 配下の config.yaml を無視する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/.git/submodule/deltaspec"
  echo "version: 1" > "$SANDBOX/.git/submodule/deltaspec/config.yaml"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  # .git 配下は除外されるため not found → return 1
  assert_output --partial "exit=1"
}

# Edge case: node_modules 配下の config.yaml は除外される
@test "resolve_deltaspec_root[walkdown][edge]: node_modules 配下の config.yaml を無視する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/node_modules/pkg/deltaspec"
  echo "version: 1" > "$SANDBOX/node_modules/pkg/deltaspec/config.yaml"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  assert_output --partial "exit=1"
}

# Edge case: maxdepth=5 を超えた階層は探索しない
@test "resolve_deltaspec_root[walkdown][edge]: maxdepth=5 を超える深さの config.yaml は無視する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # depth 6 (root/a/b/c/d/e/deltaspec/config.yaml)
  mkdir -p "$SANDBOX/a/b/c/d/e/deltaspec"
  echo "version: 1" > "$SANDBOX/a/b/c/d/e/deltaspec/config.yaml"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  assert_output --partial "exit=1"
}

# ---------------------------------------------------------------------------
# Scenario: deltaspec/config.yaml が見つからない場合
# WHEN resolve_deltaspec_root "$root" を呼び出し、maxdepth=5 以内に config.yaml が存在しない
# THEN $root を echo して return 1 する
# ---------------------------------------------------------------------------

@test "resolve_deltaspec_root[notfound]: config.yaml がなければ root を出力する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # Arrange: deltaspec/ ディレクトリすら作らない
  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'"

  # return 1 でも output は root のはず
  assert_output "$SANDBOX"
}

@test "resolve_deltaspec_root[notfound]: config.yaml がなければ return 1 を返す" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  assert_output --partial "exit=1"
}

# Edge case: deltaspec/ ディレクトリはあるが config.yaml がない場合も return 1
@test "resolve_deltaspec_root[notfound][edge]: deltaspec/ はあるが config.yaml がなければ return 1" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/deltaspec"
  # config.yaml を作らない（changes/ だけ）
  mkdir -p "$SANDBOX/deltaspec/changes/issue-999"

  run bash -c "source '$HELPERS_LIB' && resolve_deltaspec_root '$SANDBOX'; echo \"exit=\$?\""

  assert_output --partial "exit=1"
}

# ===========================================================================
# Requirement: chain-runner.sh の resolve_deltaspec_root 共有化
# Spec: deltaspec/changes/issue-460/specs/deltaspec-dry-fix/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: chain-runner.sh が deltaspec-helpers.sh を source する
# WHEN bash chain-runner.sh が実行される
# THEN resolve_deltaspec_root() が正常に呼び出せる（既存の step_init の挙動が維持される）
# ---------------------------------------------------------------------------

@test "chain-runner[source]: lib/deltaspec-helpers.sh を source している" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  grep -q 'source.*lib/deltaspec-helpers\.sh' "$CHAIN_RUNNER" \
    || fail "chain-runner.sh が lib/deltaspec-helpers.sh を source していない"
}

@test "chain-runner[source]: shellcheck ディレクティブが存在する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  grep -q 'shellcheck source=.*deltaspec-helpers\.sh' "$CHAIN_RUNNER" \
    || fail "chain-runner.sh に shellcheck source ディレクティブがない"
}

@test "chain-runner[source]: chain-runner.sh が resolve_deltaspec_root を自前定義していない" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # resolve_deltaspec_root() の定義がなくなっていること
  ! grep -q '^resolve_deltaspec_root()' "$CHAIN_RUNNER" \
    || fail "chain-runner.sh がまだ resolve_deltaspec_root() を自前定義している（DRY 未解消）"
}

@test "chain-runner[source]: resolve_deltaspec_root がライブラリ経由で呼び出せる" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  mkdir -p "$SANDBOX/deltaspec"
  echo "version: 1" > "$SANDBOX/deltaspec/config.yaml"

  # chain-runner.sh を source して resolve_deltaspec_root を呼ぶ
  # ただし chain-runner.sh は set -euo pipefail + 引数必須なので、
  # ライブラリ単体の呼び出しで関数可用性のみを確認する
  run bash -c "
    SCRIPT_DIR='$SCRIPTS_ROOT'
    source '$HELPERS_LIB'
    resolve_deltaspec_root '$SANDBOX'
  "

  assert_success
  assert_output "$SANDBOX"
}

# ===========================================================================
# Requirement: autopilot-orchestrator.sh のインライン find 除去
# Spec: deltaspec/changes/issue-460/specs/deltaspec-dry-fix/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: _archive_deltaspec_changes_for_issue が resolve_deltaspec_root を使う
# WHEN _archive_deltaspec_changes_for_issue "$issue" が呼び出される
# THEN インライン find の代わりに resolve_deltaspec_root() で ds_root を解決する
# ---------------------------------------------------------------------------

@test "autopilot-orchestrator[archive]: lib/deltaspec-helpers.sh を source している" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  grep -q 'source.*lib/deltaspec-helpers\.sh' "$ORCHESTRATOR" \
    || fail "autopilot-orchestrator.sh が lib/deltaspec-helpers.sh を source していない"
}

@test "autopilot-orchestrator[archive]: shellcheck ディレクティブが存在する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  grep -q 'shellcheck source=.*deltaspec-helpers\.sh' "$ORCHESTRATOR" \
    || fail "autopilot-orchestrator.sh に shellcheck source ディレクティブがない"
}

@test "autopilot-orchestrator[archive]: _archive_deltaspec_changes_for_issue がインライン find を使っていない" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # _archive_deltaspec_changes_for_issue 関数ブロック内で find を使っていないことを確認
  # 関数開始行から次の関数定義までを抽出してチェック
  local func_block
  func_block="$(awk '/^_archive_deltaspec_changes_for_issue\(\)/{found=1} found{print} found && /^\}$/{exit}' "$ORCHESTRATOR")"

  # インライン find (walk-down fallback の特徴パターン) がないこと
  if echo "$func_block" | grep -qE 'find.*maxdepth.*config\.yaml.*deltaspec'; then
    fail "_archive_deltaspec_changes_for_issue がまだインライン find を使っている（DRY 未解消）"
  fi
}

@test "autopilot-orchestrator[archive]: _archive_deltaspec_changes_for_issue が resolve_deltaspec_root を呼んでいる" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  local func_block
  func_block="$(awk '/^_archive_deltaspec_changes_for_issue\(\)/{found=1} found{print} found && /^\}$/{exit}' "$ORCHESTRATOR")"

  echo "$func_block" | grep -q 'resolve_deltaspec_root' \
    || fail "_archive_deltaspec_changes_for_issue が resolve_deltaspec_root を呼んでいない"
}

@test "autopilot-orchestrator[archive][integration]: walk-down fallback で ds_root が正しく解決される" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # Arrange: ネストした deltaspec root を持つ sandbox
  mkdir -p "$SANDBOX/plugins/twl/deltaspec/changes/issue-42"
  echo "version: 1" > "$SANDBOX/plugins/twl/deltaspec/config.yaml"
  cat > "$SANDBOX/plugins/twl/deltaspec/changes/issue-42/.deltaspec.yaml" << 'YAML_EOF'
name: issue-42
issue: 42
YAML_EOF

  # Arrange: twl コマンドスタブ（archive 呼び出しを記録）
  stub_command "twl" "echo \"twl \$*\" >> '${CALLS_LOG}'; exit 0"
  stub_command "git" "echo '$SANDBOX'; exit 0"

  # Act: archive dispatch テストスクリプト経由で実行
  cat > "$SANDBOX/scripts/archive-dispatch.sh" << DISPATCH_EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$SCRIPTS_ROOT"
# shellcheck source=./lib/deltaspec-helpers.sh
source "\${SCRIPT_DIR}/lib/deltaspec-helpers.sh"

issue="\$1"
root="$SANDBOX"

# _archive_deltaspec_changes_for_issue の ds_root 解決ロジックを再現
if ! ds_root="\$(resolve_deltaspec_root "\$root")"; then
  echo "[test] resolve_deltaspec_root failed, ds_root=\$ds_root" >&2
fi

changes_dir="\$ds_root/deltaspec/changes"
echo "ds_root=\$ds_root"
echo "changes_dir=\$changes_dir"
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/archive-dispatch.sh"

  run bash "$SANDBOX/scripts/archive-dispatch.sh" "42"

  assert_success
  assert_output --partial "ds_root=$SANDBOX/plugins/twl"
  assert_output --partial "changes_dir=$SANDBOX/plugins/twl/deltaspec/changes"
}

# ===========================================================================
# Requirement: shellcheck が両スクリプトを通過する
# Spec: deltaspec/changes/issue-460/specs/deltaspec-dry-fix/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: shellcheck が両スクリプトを通過する
# WHEN shellcheck plugins/twl/scripts/chain-runner.sh と autopilot-orchestrator.sh を実行
# THEN エラーなしで終了する（警告のみ許容）
# ---------------------------------------------------------------------------

@test "shellcheck[chain-runner]: shellcheck がエラーなしで通過する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck がインストールされていない"

  run shellcheck --severity=error "$CHAIN_RUNNER"

  assert_success
}

@test "shellcheck[autopilot-orchestrator]: shellcheck がエラーなしで通過する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck がインストールされていない"

  run shellcheck --severity=error "$ORCHESTRATOR"

  assert_success
}

# ===========================================================================
# Requirement: bats 回帰テスト — DRY 解消後の挙動維持
# Spec: deltaspec/changes/issue-460/specs/deltaspec-dry-fix/spec.md
# ===========================================================================

@test "regression[deltaspec-helpers]: chain-runner.sh と autopilot-orchestrator.sh が同じ関数を共有する" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # 両スクリプトが同じライブラリを source していること
  grep -q 'lib/deltaspec-helpers\.sh' "$CHAIN_RUNNER" \
    || fail "chain-runner.sh が deltaspec-helpers.sh を source していない"
  grep -q 'lib/deltaspec-helpers\.sh' "$ORCHESTRATOR" \
    || fail "autopilot-orchestrator.sh が deltaspec-helpers.sh を source していない"
}

@test "regression[deltaspec-helpers]: resolve_deltaspec_root はライブラリにのみ定義される" {
  [[ -f "$HELPERS_LIB" ]] || skip "lib/deltaspec-helpers.sh は未実装（issue-460 実装前）"

  # ライブラリに定義があること
  grep -q '^resolve_deltaspec_root()' "$HELPERS_LIB" \
    || fail "lib/deltaspec-helpers.sh に resolve_deltaspec_root() が定義されていない"

  # chain-runner.sh に自前定義がないこと
  ! grep -q '^resolve_deltaspec_root()' "$CHAIN_RUNNER" \
    || fail "chain-runner.sh がまだ resolve_deltaspec_root() を自前定義している"

  # autopilot-orchestrator.sh に自前定義がないこと
  ! grep -q '^resolve_deltaspec_root()' "$ORCHESTRATOR" \
    || fail "autopilot-orchestrator.sh がまだ resolve_deltaspec_root() を自前定義している"
}
