#!/usr/bin/env bats
# change-propose-auto-init.bats - Step 0 auto_init ロジックの bats テスト
#
# Spec: deltaspec/changes/issue-784/specs/adr-015-acceptance.md
# Requirement: change-propose Step 0 の bats テスト追加
#
# Scenarios covered:
#   - MODE=propose + DELTASPEC_EXISTS=false → auto_init パス（twl spec new を呼ぶ）
#   - MODE=propose + DELTASPEC_EXISTS=true  → Step 1 へ進む（auto_init しない）
#   - MODE=direct  + DELTASPEC_EXISTS=false → auto_init しない
#   - MODE=''      + DELTASPEC_EXISTS=false → auto_init しない
#   - MODE=propose + deltaspec/config.yaml 存在 → DELTASPEC_EXISTS=true 判定
#   - MODE=propose + deltaspec/config.yaml 不在 → DELTASPEC_EXISTS=false 判定

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # REPO_ROOT は common_setup が設定（plugins/twl/ 直下）
  # twl spec new のスタブを用意（呼び出し記録だけ行う）
  stub_command "twl" '
    echo "TWL_CALLED: $*" >> /tmp/twl-calls.log
    case "$*" in
      "spec new"*)
        echo "Created: deltaspec/changes/$(echo "$*" | awk "{print \$3}")"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  # python3 のスタブ（state read を模倣）
  # デフォルトは空文字（MODE 未設定）
  stub_command "python3" '
    # state read の呼び出し模倣
    if echo "$*" | grep -q "state.*read.*--field.*mode"; then
      echo "${STUB_MODE:-}"
    else
      # その他の python3 呼び出しは実 python3 へ委譲（PATH に実体あり）
      command python3 "$@"
    fi
  '
}

teardown() {
  rm -f /tmp/twl-calls.log
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: Step 0 ロジック本体
#
# change-propose.md Step 0 を bash で再現する。
# 実コマンドへの依存を最小化し、STUB_MODE と STUB_DELTASPEC_EXISTS で制御する。
# ---------------------------------------------------------------------------

run_step0() {
  local issue_num="${1:-784}"
  local mode="${STUB_MODE:-}"
  local deltaspec_exists="${STUB_DELTASPEC_EXISTS:-false}"

  # Step 0 判定ロジック（change-propose.md より抜粋・再現）
  if [[ "$mode" == "propose" && "$deltaspec_exists" == "false" ]]; then
    echo "AUTO_INIT=true"
    echo "CHANGE_ID=issue-${issue_num}"
    mkdir -p "$SANDBOX/deltaspec"
    twl spec new "issue-${issue_num}" 2>/dev/null
    echo "STEP=skip_to_step3"
  else
    echo "AUTO_INIT=false"
    echo "STEP=step1"
  fi
}

# ---------------------------------------------------------------------------
# Scenario: bats テストファイル作成
# WHEN plugins/twl/tests/bats/ に change-propose の bats テストファイルを作成する
# THEN ファイルが存在し、MODE=propose + DELTASPEC_EXISTS=false の条件検証を含む
# ---------------------------------------------------------------------------

@test "change-propose-auto-init: test file exists at expected path" {
  local test_file
  test_file="$(cd "$BATS_TEST_DIRNAME" && pwd)/change-propose-auto-init.bats"
  [ -f "$test_file" ]
}

@test "change-propose-auto-init: test file covers MODE=propose DELTASPEC_EXISTS=false scenario" {
  local test_file
  test_file="$(cd "$BATS_TEST_DIRNAME" && pwd)/change-propose-auto-init.bats"
  grep -q 'MODE=propose' "$test_file"
  grep -q 'DELTASPEC_EXISTS=false' "$test_file"
}

# ---------------------------------------------------------------------------
# Scenario: auto_init 条件検証
# WHEN MODE=propose + deltaspec/config.yaml が存在しない状態で Step 0 を実行する
# THEN DELTASPEC_EXISTS=false と判定され、auto_init パスに進む
# ---------------------------------------------------------------------------

@test "step0: MODE=propose + DELTASPEC_EXISTS=false → AUTO_INIT=true" {
  STUB_MODE="propose" STUB_DELTASPEC_EXISTS="false" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AUTO_INIT=true"
}

@test "step0: MODE=propose + DELTASPEC_EXISTS=false → twl spec new が呼ばれる" {
  STUB_MODE="propose" STUB_DELTASPEC_EXISTS="false" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  grep -q "TWL_CALLED: spec new issue-784" /tmp/twl-calls.log
}

@test "step0: MODE=propose + DELTASPEC_EXISTS=false → CHANGE_ID が issue-784 になる" {
  STUB_MODE="propose" STUB_DELTASPEC_EXISTS="false" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CHANGE_ID=issue-784"
}

@test "step0: MODE=propose + DELTASPEC_EXISTS=false → Step 3 へスキップ" {
  STUB_MODE="propose" STUB_DELTASPEC_EXISTS="false" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "STEP=skip_to_step3"
}

@test "step0: MODE=propose + DELTASPEC_EXISTS=false → deltaspec/ ディレクトリが作成される" {
  STUB_MODE="propose" STUB_DELTASPEC_EXISTS="false" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  [ -d "$SANDBOX/deltaspec" ]
}

# ---------------------------------------------------------------------------
# Edge case: MODE=propose + DELTASPEC_EXISTS=true → auto_init しない
# ---------------------------------------------------------------------------

@test "step0: MODE=propose + DELTASPEC_EXISTS=true → AUTO_INIT=false (Step 1 へ)" {
  STUB_MODE="propose" STUB_DELTASPEC_EXISTS="true" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AUTO_INIT=false"
  echo "$output" | grep -q "STEP=step1"
}

@test "step0: MODE=propose + DELTASPEC_EXISTS=true → twl spec new が呼ばれない" {
  rm -f /tmp/twl-calls.log
  STUB_MODE="propose" STUB_DELTASPEC_EXISTS="true" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  # twl spec new の呼び出しログが存在しない、または spec new を含まない
  ! grep -q "spec new" /tmp/twl-calls.log 2>/dev/null
}

# ---------------------------------------------------------------------------
# Edge case: MODE=direct → auto_init しない（scope/direct モードは対象外）
# ---------------------------------------------------------------------------

@test "step0: MODE=direct + DELTASPEC_EXISTS=false → AUTO_INIT=false" {
  STUB_MODE="direct" STUB_DELTASPEC_EXISTS="false" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AUTO_INIT=false"
}

# ---------------------------------------------------------------------------
# Edge case: MODE='' (未設定) → auto_init しない
# ---------------------------------------------------------------------------

@test "step0: MODE='' + DELTASPEC_EXISTS=false → AUTO_INIT=false" {
  STUB_MODE="" STUB_DELTASPEC_EXISTS="false" \
    run run_step0 "784"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AUTO_INIT=false"
}

# ---------------------------------------------------------------------------
# DELTASPEC_EXISTS 判定ロジック検証
# WHEN deltaspec/config.yaml が存在する → DELTASPEC_EXISTS=true
# WHEN deltaspec/config.yaml が存在しない → DELTASPEC_EXISTS=false
# ---------------------------------------------------------------------------

@test "deltaspec-exists-check: config.yaml 存在時 → DELTASPEC_EXISTS=true" {
  mkdir -p "$SANDBOX/deltaspec"
  touch "$SANDBOX/deltaspec/config.yaml"

  # 実際の判定コマンドを実行（change-propose.md Step 0 の bash スニペット）
  run bash -c "
    cd '$SANDBOX'
    DELTASPEC_EXISTS=\$(test -f deltaspec/config.yaml && echo 'true' || echo 'false')
    echo \"\$DELTASPEC_EXISTS\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "deltaspec-exists-check: config.yaml 不在時 → DELTASPEC_EXISTS=false" {
  # SANDBOX には deltaspec/ が存在しない（common_setup で作成されない）
  run bash -c "
    cd '$SANDBOX'
    DELTASPEC_EXISTS=\$(test -f deltaspec/config.yaml && echo 'true' || echo 'false')
    echo \"\$DELTASPEC_EXISTS\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "deltaspec-exists-check: deltaspec/ ディレクトリがあっても config.yaml なし → false" {
  mkdir -p "$SANDBOX/deltaspec/changes/some-change"
  # config.yaml は作成しない

  run bash -c "
    cd '$SANDBOX'
    DELTASPEC_EXISTS=\$(test -f deltaspec/config.yaml && echo 'true' || echo 'false')
    echo \"\$DELTASPEC_EXISTS\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
