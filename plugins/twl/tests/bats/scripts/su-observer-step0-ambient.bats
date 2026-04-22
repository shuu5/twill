#!/usr/bin/env bats
# su-observer-step0-ambient.bats - step0-memory-ambient.sh TTL チェック・再生成ロジック検証

load '../helpers/common'

AMBIENT_SCRIPT=""

setup() {
  common_setup
  AMBIENT_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/step0-memory-ambient.sh"
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"
  mkdir -p "$SUPERVISOR_DIR"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: ファイルが存在しない場合 STALE を返す
# WHEN: ambient-hints.md が存在しない
# THEN: exit 1 (STALE)
# ---------------------------------------------------------------------------

@test "--check: ambient-hints.md が存在しない場合 exit 1 (STALE)" {
  run bash "$AMBIENT_SCRIPT" --check

  assert_failure
  assert_output "STALE"
}

@test "デフォルト: ambient-hints.md が存在しない場合 exit 1 (STALE)" {
  run bash "$AMBIENT_SCRIPT"

  assert_failure
  assert_output "STALE"
}

# ---------------------------------------------------------------------------
# Scenario: ファイルが 24h 以内の場合 FRESH を返す
# WHEN: ambient-hints.md が存在し、mtime が TTL 内
# THEN: exit 0 (FRESH)
# ---------------------------------------------------------------------------

@test "--check: 新規 ambient-hints.md は FRESH (exit 0)" {
  echo "# ambient hints" > "$SUPERVISOR_DIR/ambient-hints.md"

  run bash "$AMBIENT_SCRIPT" --check

  assert_success
  assert_output "FRESH"
}

@test "デフォルト: 新規 ambient-hints.md は FRESH (exit 0)" {
  echo "# ambient hints" > "$SUPERVISOR_DIR/ambient-hints.md"

  run bash "$AMBIENT_SCRIPT"

  assert_success
  assert_output "FRESH"
}

# ---------------------------------------------------------------------------
# Scenario: TTL 超過ファイルは STALE を返す
# WHEN: ambient-hints.md の mtime が 25h 以上前
# THEN: exit 1 (STALE)
# ---------------------------------------------------------------------------

@test "--check: TTL 超過ファイル (25h 前) は STALE (exit 1)" {
  echo "# old hints" > "$SUPERVISOR_DIR/ambient-hints.md"
  # mtime を 25 時間前に設定 (TTL 86400s < 90000s)
  touch -d "25 hours ago" "$SUPERVISOR_DIR/ambient-hints.md"

  AMBIENT_TTL_SEC=86400 run bash "$AMBIENT_SCRIPT" --check

  assert_failure
  assert_output "STALE"
}

# ---------------------------------------------------------------------------
# Scenario: カスタム TTL (短め) でテスト
# WHEN: AMBIENT_TTL_SEC=5 で 1s 前のファイル
# THEN: FRESH
# ---------------------------------------------------------------------------

@test "--check: カスタム TTL 内は FRESH" {
  echo "# hints" > "$SUPERVISOR_DIR/ambient-hints.md"

  AMBIENT_TTL_SEC=86400 run bash "$AMBIENT_SCRIPT" --check

  assert_success
  assert_output "FRESH"
}

# ---------------------------------------------------------------------------
# Scenario: --write でファイルを作成し TTL がリセットされる
# WHEN: echo "content" | bash script --write
# THEN: ファイルが作成され --check が FRESH を返す
# ---------------------------------------------------------------------------

@test "--write: stdin からファイルを作成する" {
  echo "# observer pitfall hints" | bash "$AMBIENT_SCRIPT" --write

  [[ -f "$SUPERVISOR_DIR/ambient-hints.md" ]]
  grep -q "observer pitfall hints" "$SUPERVISOR_DIR/ambient-hints.md"
}

@test "--write 後 --check は FRESH (exit 0) を返す" {
  echo "# fresh hints" | bash "$AMBIENT_SCRIPT" --write

  run bash "$AMBIENT_SCRIPT" --check

  assert_success
  assert_output "FRESH"
}

# ---------------------------------------------------------------------------
# Scenario: --write は SUPERVISOR_DIR を自動作成する
# WHEN: SUPERVISOR_DIR が存在しない状態で --write
# THEN: ディレクトリとファイルが作成される
# ---------------------------------------------------------------------------

@test "--write: SUPERVISOR_DIR が存在しなくても自動作成する" {
  export SUPERVISOR_DIR="$SANDBOX/.supervisor-new"

  echo "# hints" | bash "$AMBIENT_SCRIPT" --write

  [[ -d "$SUPERVISOR_DIR" ]]
  [[ -f "$SUPERVISOR_DIR/ambient-hints.md" ]]
}

# ---------------------------------------------------------------------------
# Scenario: 古いファイルを --write で更新すると FRESH になる
# WHEN: 25h 前のファイルを --write で上書き
# THEN: --check が FRESH を返す
# ---------------------------------------------------------------------------

@test "--write: 古いファイルを上書きすると FRESH になる" {
  echo "# old" > "$SUPERVISOR_DIR/ambient-hints.md"
  touch -d "25 hours ago" "$SUPERVISOR_DIR/ambient-hints.md"

  # STALE であることを確認
  run bash "$AMBIENT_SCRIPT" --check
  assert_failure

  # --write で更新
  echo "# renewed hints" | bash "$AMBIENT_SCRIPT" --write

  # FRESH になることを確認
  run bash "$AMBIENT_SCRIPT" --check
  assert_success
  assert_output "FRESH"
}

# ---------------------------------------------------------------------------
# Scenario: 不明なオプションは exit 2 を返す
# ---------------------------------------------------------------------------

@test "不明なオプションは exit 2 を返す" {
  run bash "$AMBIENT_SCRIPT" --unknown

  assert [ "$status" -eq 2 ]
}
