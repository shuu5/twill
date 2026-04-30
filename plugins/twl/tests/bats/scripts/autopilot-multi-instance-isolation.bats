#!/usr/bin/env bats
# autopilot-multi-instance-isolation.bats
#
# Issue #1169: autopilot マルチインスタンス分離
#
# Coverage:
#   C1: 2 AUTOPILOT_DIR 独立初期化
#   C2: .autopilot-wave10 → .gitignore に .autopilot-*/ 追加（RED: 未実装）
#   C3: chain-runner.sh .autopilot-wave10 basename で trace 書き込み許可（RED: 未実装）
#   C4: H2 セキュリティ保持 — evil パターンは拒否
#   C5: $HOME/.autopilot-evil は許可（RED: 未実装）

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/1169-autopilot-multi-inst" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/main\n" "$SANDBOX" ;;
      *)
        exit 0 ;;
    esac
  '

  stub_command "gh" 'exit 0'
  stub_command "python3" 'exit 0'

  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE'
#!/usr/bin/env bash
resolve_project() { echo "1 PVT_id shuu5 twill shuu5/twill"; }
RESOLVE

  # check ステップが Tests: PASS になるためにテストファイルを作成
  mkdir -p "$SANDBOX/tests"
  touch "$SANDBOX/tests/dummy.bats"

  # CI/CD 警告を抑制
  mkdir -p "$SANDBOX/.github/workflows"
  touch "$SANDBOX/.github/workflows/ci.yml"

  # deltaspec の確認ファイル
  mkdir -p "$SANDBOX/deltaspec/changes/dummy"
  touch "$SANDBOX/deltaspec/changes/dummy/proposal.md"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# C1: 2 AUTOPILOT_DIR 独立初期化
# ---------------------------------------------------------------------------

@test "#1169 C1: 2 つの AUTOPILOT_DIR が独立して初期化され issues/ が各自作成される" {
  local dir_a
  local dir_b
  dir_a="$(mktemp -d)"
  dir_b="$(mktemp -d)"

  # dir_a を初期化
  AUTOPILOT_DIR="$dir_a" run bash "$SANDBOX/scripts/autopilot-init.sh"
  assert_success
  [ -d "$dir_a/issues" ]

  # dir_b を初期化
  AUTOPILOT_DIR="$dir_b" run bash "$SANDBOX/scripts/autopilot-init.sh"
  assert_success
  [ -d "$dir_b/issues" ]

  # 手動で session.json を作成し、session_id が異なることを確認
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"session_id\": \"session-a-1169\", \"started_at\": \"$now\"}" > "$dir_a/session.json"
  echo "{\"session_id\": \"session-b-1169\", \"started_at\": \"$now\"}" > "$dir_b/session.json"

  local sid_a sid_b
  sid_a=$(jq -r '.session_id' "$dir_a/session.json")
  sid_b=$(jq -r '.session_id' "$dir_b/session.json")

  [ "$sid_a" != "$sid_b" ]

  rm -rf "$dir_a" "$dir_b"
}

# ---------------------------------------------------------------------------
# C2: .autopilot-wave10 → .gitignore に .autopilot-*/ 追加（RED）
# ---------------------------------------------------------------------------

@test "#1169 C2: autopilot-init.sh が .autopilot-wave10 を AUTOPILOT_DIR として .gitignore に .autopilot-*/ を追加する（RED）" {
  # GIVEN
  local wave_dir="$SANDBOX/.autopilot-wave10"
  rm -rf "$AUTOPILOT_DIR"  # common_setup の .autopilot を除去

  # WHEN
  AUTOPILOT_DIR="$wave_dir" run bash "$SANDBOX/scripts/autopilot-init.sh"
  assert_success

  # THEN: issues/ が作成される
  [ -d "$wave_dir/issues" ]

  # THEN: .gitignore に .autopilot-*/ が含まれる
  # RED: 現在の実装は .autopilot/ のみ追加するため、この assert は FAIL する
  grep -qxF '.autopilot-*/' "$SANDBOX/.gitignore" || {
    echo "FAIL: .gitignore に .autopilot-*/ が追加されていない（現在は .autopilot/ のみ）" >&2
    echo "  Expected: .gitignore contains '.autopilot-*/'" >&2
    echo "  Actual .gitignore contents:" >&2
    cat "$SANDBOX/.gitignore" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# C3: chain-runner.sh .autopilot-wave10 basename で trace 書き込み許可（RED）
# ---------------------------------------------------------------------------

@test "#1169 C3: chain-runner.sh が AUTOPILOT_DIR=.autopilot-wave10 のとき trace ファイルを書き込む（RED）" {
  # GIVEN: HOME 配下に配置することで /tmp/* whitelist をバイパスし、
  #        basename 検証が唯一の通過条件となる
  #        (/tmp 配下だと /tmp/* whitelist が先に適用され basename 検証に到達しないため)
  local wave_dir="${HOME}/.autopilot-wave10-1169-bats${BATS_TEST_NUMBER}"
  local trace_file="$wave_dir/trace/test-c3.jsonl"
  mkdir -p "$wave_dir/trace" "$wave_dir/issues"

  # WHEN
  run env \
    AUTOPILOT_DIR="$wave_dir" \
    TWL_CHAIN_TRACE="$trace_file" \
    bash "$SANDBOX/scripts/chain-runner.sh" check

  # THEN: trace ファイルが作成される（HOME trust + basename .autopilot-wave10 → regex 通過）
  # RED: 現在の basename 検証は .autopilot のみ許可するため FAIL する
  [ -f "$trace_file" ] || {
    echo "FAIL: trace file not written — basename .autopilot-wave10 should be allowed after fix" >&2
    echo "  AUTOPILOT_DIR: $wave_dir" >&2
    echo "  Expected: basename .autopilot-wave10 matches .autopilot-* pattern → trusted" >&2
    echo "  Actual: current code only trusts basename .autopilot" >&2
    rm -rf "$wave_dir"
    return 1
  }

  rm -rf "$wave_dir"
}

# ---------------------------------------------------------------------------
# C4: H2 セキュリティ保持 — evil パターンは拒否
# ---------------------------------------------------------------------------

@test "#1169 C4: chain-runner.sh が AUTOPILOT_DIR=evil-attempt のとき trace ファイルを書き込まない（セキュリティ保持）" {
  # GIVEN: HOME 配下の evil-attempt ディレクトリ（basename が .autopilot-* に非該当）
  #        HOME 配下に置くことで /tmp/* whitelist をバイパスし、
  #        basename 検証でセキュリティが正しく機能することを確認する
  local evil_dir="${HOME}/evil-attempt-1169-bats${BATS_TEST_NUMBER}"
  local trace_file="$evil_dir/trace/test-c4.jsonl"
  mkdir -p "$evil_dir/trace" "$evil_dir/issues"

  # WHEN
  run env \
    AUTOPILOT_DIR="$evil_dir" \
    TWL_CHAIN_TRACE="$trace_file" \
    bash "$SANDBOX/scripts/chain-runner.sh" check

  # THEN: trace ファイルが作成されない（セキュリティ意図保持）
  # basename が evil-attempt であり .autopilot-* パターンに非該当のため拒否されるべき
  [ ! -f "$trace_file" ] || {
    echo "FAIL: trace file was written for untrusted AUTOPILOT_DIR" >&2
    echo "  AUTOPILOT_DIR: $evil_dir" >&2
    echo "  Basename: evil-attempt (does not match .autopilot-* pattern)" >&2
    echo "  Expected: trace file NOT created (security gate)" >&2
    rm -rf "$evil_dir"
    return 1
  }

  rm -rf "$evil_dir"
}

# ---------------------------------------------------------------------------
# C5: $HOME/.autopilot-evil は許可（RED）
# ---------------------------------------------------------------------------

@test "#1169 C5: chain-runner.sh が AUTOPILOT_DIR=\$HOME/.autopilot-evil のとき trace ファイルを書き込む（RED）" {
  # GIVEN: HOME 配下の .autopilot-* パターンに合致するディレクトリ
  local home_evil_dir="${HOME}/.autopilot-evil-1169-bats${BATS_TEST_NUMBER}"
  local trace_file="$home_evil_dir/trace/test-c5.jsonl"
  mkdir -p "$home_evil_dir/trace" "$home_evil_dir/issues"

  # WHEN
  run env \
    AUTOPILOT_DIR="$home_evil_dir" \
    TWL_CHAIN_TRACE="$trace_file" \
    bash "$SANDBOX/scripts/chain-runner.sh" check

  # THEN: trace ファイルが作成される（HOME trust + basename regex 通過）
  # RED: 現在の basename 検証は .autopilot のみ許可するため FAIL する
  [ -f "$trace_file" ] || {
    echo "FAIL: trace file not written — HOME/.autopilot-evil should be allowed after fix" >&2
    echo "  AUTOPILOT_DIR: $home_evil_dir" >&2
    echo "  Expected: basename .autopilot-evil matches .autopilot-* pattern → trusted" >&2
    echo "  Actual: current code only trusts basename .autopilot" >&2
    rm -rf "$home_evil_dir"
    return 1
  }

  rm -rf "$home_evil_dir"
}
