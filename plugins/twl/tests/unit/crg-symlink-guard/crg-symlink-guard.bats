#!/usr/bin/env bats
# crg-symlink-guard.bats
# Requirement: CRG symlink 自己参照バグ再発防止（issue-674）
# Spec: deltaspec/changes/issue-674/specs/crg-symlink-guard.md
# Coverage: --type=unit --coverage=edge-cases
#
# 検証する仕様:
#   1. crg-auto-build.md の MUST NOT セクションに ln コマンド禁止ルールが存在する
#   2. LLM が .code-review-graph の symlink を検出した場合は何もせず終了する
#   3. orchestrator が main/.code-review-graph が symlink の場合に削除・警告ログを出す
#   4. orchestrator が main/.code-review-graph が正常ディレクトリの場合に何もしない
#   5. su-observer が Wave 開始時に main CRG が symlink なら ⚠️ [CRG health] 警告を出す
#   6. su-observer が Wave 開始時に main CRG が正常ディレクトリなら何も出力しない
#
# test double: crg-main-symlink-check.sh
#   orchestrator の main CRG symlink チェックロジックを抽出した test double
#   Env:
#     TWILL_REPO_ROOT  - twill モノリポルート
#     CALLS_LOG        - 呼び出し記録ファイル
#
# test double: su-observer-crg-health.sh
#   su-observer の Wave 開始 CRG ヘルスチェックを抽出した test double
#   Env:
#     TWILL_REPO_ROOT  - twill モノリポルート

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: フィクスチャと test double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG

  FAKE_REPO_ROOT="$SANDBOX/twill"
  mkdir -p "$FAKE_REPO_ROOT/main"
  mkdir -p "$FAKE_REPO_ROOT/main/.code-review-graph"
  export FAKE_REPO_ROOT

  # ---------------------------------------------------------------------------
  # test double: orchestrator の main CRG symlink チェックロジック（Decision 2）
  #
  # orchestrator は CRG セクション冒頭（outer if の前）に、worktree_dir == main の
  # 場合のみ: main/.code-review-graph が symlink なら削除してログを出すガードを追加する。
  # このスクリプトはその追加ガード部分のみを抽出した test double。
  # ---------------------------------------------------------------------------
  cat > "$SANDBOX/scripts/crg-main-symlink-check.sh" << 'CHECK_EOF'
#!/usr/bin/env bash
# crg-main-symlink-check.sh
# orchestrator の「main CRG symlink ガード」test double（issue-674 Decision 2）
# Env:
#   TWILL_REPO_ROOT  - twill モノリポルート
#   CALLS_LOG        - 呼び出し記録ファイル
set -euo pipefail

TWILL_REPO_ROOT="${TWILL_REPO_ROOT:-}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"

_crg_main="${TWILL_REPO_ROOT%/}/main/.code-review-graph"
echo "check_started" >> "$CALLS_LOG"

# main/.code-review-graph が symlink になっていた場合は削除してログを出す
if [[ -L "$_crg_main" ]]; then
  rm -f "$_crg_main" 2>/dev/null || true
  echo "main_crg_symlink_removed=${_crg_main}" >> "$CALLS_LOG"
  echo "[orchestrator] CRG: main の .code-review-graph が symlink になっています。削除します: $_crg_main" >&2
else
  echo "main_crg_check_ok=no_symlink" >> "$CALLS_LOG"
fi

exit 0
CHECK_EOF
  chmod +x "$SANDBOX/scripts/crg-main-symlink-check.sh"

  # ---------------------------------------------------------------------------
  # test double: su-observer の Wave 開始 CRG ヘルスチェック（Decision 3）
  #
  # su-observer は Wave 開始処理の中で main/.code-review-graph が symlink か
  # チェックし、symlink なら ⚠️ [CRG health] プレフィックスの警告を出力する。
  # このスクリプトはそのチェック部分のみを抽出した test double。
  # ---------------------------------------------------------------------------
  cat > "$SANDBOX/scripts/su-observer-crg-health.sh" << 'HEALTH_EOF'
#!/usr/bin/env bash
# su-observer-crg-health.sh
# su-observer の「Wave 開始 CRG ヘルスチェック」test double（issue-674 Decision 3）
# Env:
#   TWILL_REPO_ROOT  - twill モノリポルート
set -euo pipefail

TWILL_REPO_ROOT="${TWILL_REPO_ROOT:-}"

_crg_path="${TWILL_REPO_ROOT}/main/.code-review-graph"

if [[ -L "$_crg_path" ]]; then
  echo "⚠️ [CRG health] main/.code-review-graph がシンボリックリンクです。自己参照の可能性があります。"
fi

exit 0
HEALTH_EOF
  chmod +x "$SANDBOX/scripts/su-observer-crg-health.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: crg-auto-build LLM symlink 操作禁止
# Spec: deltaspec/changes/issue-674/specs/crg-symlink-guard.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: LLM ステップで symlink 禁止ルールが明記されている
# WHEN crg-auto-build.md の「禁止事項（MUST NOT）」セクションを読む
# THEN ln コマンドの実行を禁止するルールが存在する
#
# NOTE: この Scenario は FUTURE state を検証する（implementation step で追加予定）。
#       現時点では crg-auto-build.md に ln 禁止ルールが存在しないため SKIP。
#       実装後にアクティブ化する。
# ---------------------------------------------------------------------------

@test "crg-auto-build[must-not]: MUST NOT セクションに ln コマンド禁止ルールが存在する" {
  local crg_auto_build="$REPO_ROOT/commands/crg-auto-build.md"
  [[ -f "$crg_auto_build" ]] || skip "crg-auto-build.md が見つからない"

  # implementation step で crg-auto-build.md に ln 禁止ルールを追加するまで SKIP
  # 追加後: 禁止事項セクションに "ln" または "symlink 作成禁止" の記述が存在するはず
  local must_not_section
  must_not_section=$(awk '/禁止事項（MUST NOT）/,/^## /' "$crg_auto_build")
  if ! echo "$must_not_section" | grep -qE 'ln|symlink.*(禁止|作成.*禁止|してはならない)'; then
    skip "ln 禁止ルールがまだ crg-auto-build.md に追加されていない（implementation step で追加予定）"
  fi

  echo "$must_not_section" | grep -qE 'ln|symlink.*(禁止|作成.*禁止|してはならない)'
}

@test "crg-auto-build[must-not]: .code-review-graph の手動操作禁止ルールが存在する" {
  local crg_auto_build="$REPO_ROOT/commands/crg-auto-build.md"
  [[ -f "$crg_auto_build" ]] || skip "crg-auto-build.md が見つからない"

  # implementation step で crg-auto-build.md に .code-review-graph 手動操作禁止を追加するまで SKIP
  local must_not_section
  must_not_section=$(awk '/禁止事項（MUST NOT）/,/^## /' "$crg_auto_build")
  if ! echo "$must_not_section" | grep -q '\.code-review-graph'; then
    skip ".code-review-graph 手動操作禁止ルールがまだ追加されていない（implementation step で追加予定）"
  fi

  echo "$must_not_section" | grep -q '\.code-review-graph'
}

# ---------------------------------------------------------------------------
# Scenario: LLM が壊れた symlink を検出した場合
# WHEN crg-auto-build の実行時に .code-review-graph が symlink である
# THEN 何も操作せず正常終了する（symlink の作成・削除・修正を行わない）
#
# NOTE: この Scenario も FUTURE state を検証する（crg-auto-build.md への
#       MUST NOT 追加が前提）。静的解析テストで代替。
# ---------------------------------------------------------------------------

@test "crg-auto-build[symlink-skip]: Step 1 に .code-review-graph symlink 検出時スキップの記述がある" {
  local crg_auto_build="$REPO_ROOT/commands/crg-auto-build.md"
  [[ -f "$crg_auto_build" ]] || skip "crg-auto-build.md が見つからない"

  # 既存コンテンツ: "シンボリックリンク → 何も出力せず正常終了" は既に記述済み
  grep -q 'シンボリックリンク' "$crg_auto_build"
}

@test "crg-auto-build[symlink-skip]: symlink 検出時の終了理由が worktree 参照のため" {
  local crg_auto_build="$REPO_ROOT/commands/crg-auto-build.md"
  [[ -f "$crg_auto_build" ]] || skip "crg-auto-build.md が見つからない"

  # #532 の参照コメントが存在する（worktree は main の DB を参照する設計であることを示す）
  grep -qE '#532|worktree.*main.*DB|main.*DB.*参照' "$crg_auto_build"
}

# ===========================================================================
# Requirement: orchestrator main worktree CRG 自己参照防止チェック
# Spec: deltaspec/changes/issue-674/specs/crg-symlink-guard.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: main worktree の .code-review-graph が symlink の場合
# WHEN orchestrator が worktree を処理する際、${TWILL_REPO_ROOT}/main/.code-review-graph
#      が symlink である
# THEN 当該 symlink を削除し、警告ログを出力する
# ---------------------------------------------------------------------------

@test "crg-main-guard[symlink]: main CRG が symlink の場合に削除される" {
  # main/.code-review-graph を symlink に差し替える（自己参照シナリオ）
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/main" "$FAKE_REPO_ROOT/main/.code-review-graph"

  # symlink であることを前提確認
  [[ -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  # symlink が削除されている
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

@test "crg-main-guard[symlink]: main CRG symlink 削除が CALLS_LOG に記録される" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/main" "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  grep -q "main_crg_symlink_removed=" "$CALLS_LOG"
}

@test "crg-main-guard[symlink]: main CRG symlink 削除時に警告ログが stderr に出力される" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/main" "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  # bats の $output は stdout のみ。stderr は run で $output に含まれないため
  # CALLS_LOG で間接的に確認
  grep -q "main_crg_symlink_removed=" "$CALLS_LOG"
}

@test "crg-main-guard[symlink]: broken symlink（参照先なし）の場合も削除される" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  # 存在しないパスへの broken symlink
  ln -s "$FAKE_REPO_ROOT/main/nonexistent-target" "$FAKE_REPO_ROOT/main/.code-review-graph"

  [[ -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

@test "crg-main-guard[symlink]: worktree 参照 symlink の場合も削除される" {
  # feature worktree の .code-review-graph が main を参照している逆パターン
  mkdir -p "$FAKE_REPO_ROOT/worktrees/feat/674-test"
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/worktrees/feat/674-test" "$FAKE_REPO_ROOT/main/.code-review-graph"

  [[ -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  [[ ! -e "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

# ---------------------------------------------------------------------------
# Scenario: main worktree の .code-review-graph が正常ディレクトリの場合
# WHEN orchestrator が worktree を処理する際、${TWILL_REPO_ROOT}/main/.code-review-graph
#      が通常ディレクトリである
# THEN 何もせず既存処理を継続する
# ---------------------------------------------------------------------------

@test "crg-main-guard[dir]: main CRG が正常ディレクトリの場合に削除されない" {
  # setup で mkdir -p で作成された正常ディレクトリ状態
  [[ -d "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  # ディレクトリがそのまま残っている
  [[ -d "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

@test "crg-main-guard[dir]: 正常ディレクトリの場合に main_crg_check_ok が記録される" {
  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  grep -q "main_crg_check_ok=no_symlink" "$CALLS_LOG"
}

@test "crg-main-guard[dir]: 正常ディレクトリの場合に main_crg_symlink_removed は記録されない" {
  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  ! grep -q "main_crg_symlink_removed=" "$CALLS_LOG"
}

# Edge case: main/.code-review-graph が存在しない場合は何もしない（エラーなし）
@test "crg-main-guard[edge]: main CRG が存在しない場合にエラーなく終了する" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  [[ ! -e "$FAKE_REPO_ROOT/main/.code-review-graph" ]]

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
}

# Edge case: TWILL_REPO_ROOT が末尾スラッシュ付きでも正しく動作する
@test "crg-main-guard[edge]: TWILL_REPO_ROOT 末尾スラッシュ付きでも symlink が削除される" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/main" "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="${FAKE_REPO_ROOT}/" \
    run bash "$SANDBOX/scripts/crg-main-symlink-check.sh"

  assert_success
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

# ===========================================================================
# Static analysis: autopilot-orchestrator.sh に main CRG ガードが追加されている
# Spec: deltaspec/changes/issue-674/specs/crg-symlink-guard.md
#
# NOTE: これらのテストは FUTURE state を検証する。implementation step で
#       autopilot-orchestrator.sh を修正した後に PASS する。
# ===========================================================================

@test "crg-main-guard[static]: orchestrator.sh に main CRG symlink チェックコードが存在する" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # main/.code-review-graph が symlink かチェックし削除するコードが存在する
  # 実装後: -L "$_crg_main" パターンと rm -f のペアが存在するはず
  if ! grep -qE '\-L.*_crg_main|_crg_main.*\-L' "$orchestrator"; then
    skip "main CRG symlink チェックがまだ実装されていない（implementation step で追加予定）"
  fi

  # ガードが CRG セクション内に存在する
  grep -q '_crg_main' "$orchestrator"
}

@test "crg-main-guard[static]: orchestrator.sh の main CRG ガードは CRG セクション冒頭にある" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # _crg_main 定義行から20行以内に -L チェックが存在する
  local crg_line
  crg_line=$(grep -n '_crg_main=' "$orchestrator" | head -1 | cut -d: -f1)
  [[ -n "$crg_line" ]] || skip "CRG セクションが見つからない"

  local end_line=$(( crg_line + 20 ))
  if ! sed -n "${crg_line},${end_line}p" "$orchestrator" | grep -qE '\-L.*_crg_main|_crg_main.*\-L'; then
    skip "main CRG symlink チェックがまだ実装されていない（implementation step で追加予定）"
  fi

  # 削除コード（rm -f）もセクション内に存在する
  sed -n "${crg_line},${end_line}p" "$orchestrator" | grep -q 'rm -f'
}

# ===========================================================================
# Requirement: su-observer Wave 開始時 CRG ヘルスチェック
# Spec: deltaspec/changes/issue-674/specs/crg-symlink-guard.md
#
# NOTE: Scenarios 5 & 6 は FUTURE behavior を検証するスケルトンテスト。
#       su-observer SKILL.md への実装後にアクティブ化する。
#       test double を使って期待する振る舞いを定義しておく。
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: Wave 開始時に main CRG が symlink の場合
# WHEN su-observer が Wave 開始処理を実行する
# AND ${TWILL_REPO_ROOT}/main/.code-review-graph が symlink である
# THEN ⚠️ [CRG health] プレフィックスを付けた警告メッセージを出力する
# ---------------------------------------------------------------------------

@test "su-observer-crg-health[symlink]: main CRG が symlink の場合に警告を出力する" {
  # main/.code-review-graph を symlink に差し替える
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/worktrees" "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/su-observer-crg-health.sh"

  assert_success
  # ⚠️ [CRG health] プレフィックスの警告が stdout に出力される
  [[ "$output" == *"⚠️ [CRG health]"* ]]
}

@test "su-observer-crg-health[symlink]: 警告メッセージに main/.code-review-graph の言及がある" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/worktrees" "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/su-observer-crg-health.sh"

  assert_success
  [[ "$output" == *"main/.code-review-graph"* ]]
}

@test "su-observer-crg-health[symlink]: broken symlink でも警告が出力される" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/main/nonexistent" "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/su-observer-crg-health.sh"

  assert_success
  [[ "$output" == *"⚠️ [CRG health]"* ]]
}

# ---------------------------------------------------------------------------
# Scenario: Wave 開始時に main CRG が正常ディレクトリの場合
# WHEN su-observer が Wave 開始処理を実行する
# AND ${TWILL_REPO_ROOT}/main/.code-review-graph が通常ディレクトリである
# THEN 何も出力しない（サイレント正常終了）
# ---------------------------------------------------------------------------

@test "su-observer-crg-health[dir]: main CRG が正常ディレクトリの場合に警告を出力しない" {
  # setup で mkdir -p で作成された正常ディレクトリ
  [[ -d "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/su-observer-crg-health.sh"

  assert_success
  # stdout が空（警告なし = サイレント正常終了）
  [[ -z "$output" ]]
}

@test "su-observer-crg-health[dir]: main CRG 未存在の場合も警告を出力しない" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="$FAKE_REPO_ROOT" \
    run bash "$SANDBOX/scripts/su-observer-crg-health.sh"

  assert_success
  [[ -z "$output" ]]
}

@test "su-observer-crg-health[edge]: TWILL_REPO_ROOT 末尾スラッシュ付きでも symlink を検出できる" {
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"
  ln -s "$FAKE_REPO_ROOT/worktrees" "$FAKE_REPO_ROOT/main/.code-review-graph"

  TWILL_REPO_ROOT="${FAKE_REPO_ROOT}/" \
    run bash "$SANDBOX/scripts/su-observer-crg-health.sh"

  assert_success
  [[ "$output" == *"⚠️ [CRG health]"* ]]
}

# ===========================================================================
# Static analysis: su-observer SKILL.md に CRG ヘルスチェックが追加されている
# NOTE: FUTURE state。implementation step で SKILL.md を修正した後に PASS する。
# ===========================================================================

@test "su-observer-crg-health[static]: SKILL.md に CRG health チェックコードが存在する" {
  local skill_md="$REPO_ROOT/skills/su-observer/SKILL.md"
  [[ -f "$skill_md" ]] || skip "su-observer/SKILL.md が REPO_ROOT/skills に見つからない"

  if ! grep -qE 'CRG health|CRG.*health|check.*CRG|crg.*check' "$skill_md"; then
    skip "CRG ヘルスチェックがまだ実装されていない（implementation step で追加予定）"
  fi

  grep -q 'CRG health' "$skill_md"
}

@test "su-observer-crg-health[static]: SKILL.md の CRG チェックが ⚠️ [CRG health] プレフィックスを使用する" {
  local skill_md="$REPO_ROOT/skills/su-observer/SKILL.md"
  [[ -f "$skill_md" ]] || skip "su-observer/SKILL.md が REPO_ROOT/skills に見つからない"

  if ! grep -q 'CRG health' "$skill_md"; then
    skip "CRG ヘルスチェックがまだ実装されていない（implementation step で追加予定）"
  fi

  grep -q '⚠️.*CRG health\|CRG health.*⚠️' "$skill_md"
}

@test "su-observer-crg-health[static]: SKILL.md の CRG チェックが TWILL_REPO_ROOT を参照する" {
  local skill_md="$REPO_ROOT/skills/su-observer/SKILL.md"
  [[ -f "$skill_md" ]] || skip "su-observer/SKILL.md が REPO_ROOT/skills に見つからない"

  if ! grep -q 'CRG health' "$skill_md"; then
    skip "CRG ヘルスチェックがまだ実装されていない（implementation step で追加予定）"
  fi

  grep -q 'TWILL_REPO_ROOT' "$skill_md"
}
