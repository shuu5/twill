#!/usr/bin/env bats
# chain-runner-ac-extract-namespace.bats - TDD RED tests for Issue #938
#
# Spec: Issue #938 — .dev-session を per-issue namespace に変更
#
# AC1/AC3: step_ac_extract が issue ごとのサブディレクトリ
#   .dev-session/issue-{N}/ に出力する
# AC2: step_init が SNAPSHOT_DIR=".dev-session/issue-{N}" を export する
#
# 全テストは実装前に FAIL（RED）する。
# 実装（AC1/AC2/AC3）完了後に GREEN になること。

load '../helpers/common'

setup() {
  common_setup

  # git stub: ブランチ名 feat/938-test から issue_num=938 が解決される
  # WORKER_ISSUE_NUM を使う場合はブランチ番号は使われないが
  # resolve_project_root は git rev-parse --show-toplevel を使う
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/938-test" ;;
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

  # python3 stub: extract-ac は AC 内容を返す。state write/read は no-op
  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *"extract-ac"*)
    # issue_num は引数の最後の数値
    issue_num="${@: -1}"
    echo "- [ ] テスト AC 項目 for issue-${issue_num}"
    exit 0 ;;
  *"twl.autopilot.state"*|*"twl.autopilot.github"*)
    exit 0 ;;
  *"-c"*"import twl"*)
    exit 0 ;;
  *)
    exit 0 ;;
esac
PYSTUB
  chmod +x "$STUB_BIN/python3"

  # resolve-project.sh stub（chain-runner.sh が source する場合に備えて）
  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "3 PVT_project_id shuu5 twill shuu5/twill"
}
RESOLVE_PROJECT
  chmod +x "$SANDBOX/scripts/lib/resolve-project.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1/AC3 テスト 1: WORKER_ISSUE_NUM=100 で step_ac_extract を実行すると
# .dev-session/issue-100/01.5-ac-checklist.md が生成される
#
# 現状: .dev-session/01.5-ac-checklist.md が生成される（per-issue dir なし）
# → このテストは RED
# ---------------------------------------------------------------------------

@test "#938-AC1: WORKER_ISSUE_NUM=100 で ac-extract 実行 → .dev-session/issue-100/01.5-ac-checklist.md が生成される" {
  WORKER_ISSUE_NUM=100 run bash "$SANDBOX/scripts/chain-runner.sh" ac-extract
  assert_success

  # per-issue サブディレクトリにファイルが生成されること（RED: 現状は issue-100/ が存在しない）
  local expected_file="$SANDBOX/.dev-session/issue-100/01.5-ac-checklist.md"
  [ -f "$expected_file" ] || {
    echo "FAIL: $expected_file が存在しない"
    echo "実際のファイル一覧:"
    find "$SANDBOX/.dev-session" -type f 2>/dev/null || echo "(none)"
    false
  }
}

# ---------------------------------------------------------------------------
# AC3 テスト 2: WORKER_ISSUE_NUM=200 で実行すると
# .dev-session/issue-200/01.5-ac-checklist.md が生成され、
# .dev-session/issue-100/ と共存する（別 issue の内容が独立している）
#
# 現状: .dev-session/01.5-ac-checklist.md が上書きされるだけで共存しない
# → このテストは RED
# ---------------------------------------------------------------------------

@test "#938-AC3: WORKER_ISSUE_NUM=100 と 200 で実行した場合、両ディレクトリが共存し内容が独立する" {
  # issue-100 で先に実行
  WORKER_ISSUE_NUM=100 run bash "$SANDBOX/scripts/chain-runner.sh" ac-extract
  assert_success

  # issue-200 で実行
  WORKER_ISSUE_NUM=200 run bash "$SANDBOX/scripts/chain-runner.sh" ac-extract
  assert_success

  local file_100="$SANDBOX/.dev-session/issue-100/01.5-ac-checklist.md"
  local file_200="$SANDBOX/.dev-session/issue-200/01.5-ac-checklist.md"

  # 両ファイルが存在すること（RED: 現状は共存ディレクトリが存在しない）
  [ -f "$file_100" ] || {
    echo "FAIL: $file_100 が存在しない"
    find "$SANDBOX/.dev-session" -type f 2>/dev/null || echo "(none)"
    false
  }
  [ -f "$file_200" ] || {
    echo "FAIL: $file_200 が存在しない"
    find "$SANDBOX/.dev-session" -type f 2>/dev/null || echo "(none)"
    false
  }

  # 内容が独立していること: issue-100 ファイルには "issue-100" が含まれ
  # issue-200 ファイルには "issue-200" が含まれる
  grep -q "100" "$file_100" || {
    echo "FAIL: $file_100 の内容に 100 が含まれない"
    cat "$file_100"
    false
  }
  grep -q "200" "$file_200" || {
    echo "FAIL: $file_200 の内容に 200 が含まれない"
    cat "$file_200"
    false
  }
}

# ---------------------------------------------------------------------------
# AC3 テスト 3: issue_num が "unknown"（WORKER_ISSUE_NUM=unknown）のとき
# .dev-session/issue-unknown/ ディレクトリが作られない
#
# 現状: issue_num 未解決時の処理は「空の場合 skip」のみ実装。
#   "unknown" 文字列の場合のガードは未実装 → このテストは RED
# ---------------------------------------------------------------------------

@test "#938-AC3: WORKER_ISSUE_NUM=unknown のとき .dev-session/issue-unknown/ が作られない" {
  # WORKER_ISSUE_NUM が "unknown" の場合、数値バリデーションに失敗するため
  # resolve_issue_num は空を返すか、あるいは "unknown" をそのまま返す可能性がある。
  # いずれの場合も .dev-session/issue-unknown/ ディレクトリが作成されてはならない。
  WORKER_ISSUE_NUM=unknown run bash "$SANDBOX/scripts/chain-runner.sh" ac-extract

  # exit 0（skip）であること
  assert_success

  # issue-unknown/ ディレクトリが存在しないこと（RED: 未実装の場合、unknown が通過する可能性あり）
  local forbidden_dir="$SANDBOX/.dev-session/issue-unknown"
  [ ! -d "$forbidden_dir" ] || {
    echo "FAIL: $forbidden_dir が存在してはならないが作成されている"
    false
  }
}

# ---------------------------------------------------------------------------
# AC3 テスト 4: issue_num が空（WORKER_ISSUE_NUM 未設定、ブランチ "main"）のとき
# .dev-session/issue-unknown/ ディレクトリが作られない（regression 防止）
#
# 現状: step_ac_extract は空の場合 skip するが、ディレクトリを作成してしまう
#   可能性があるため regression テストとして追加 → RED になることを確認
# ---------------------------------------------------------------------------

@test "#938-AC3: issue_num が空のとき .dev-session/issue-unknown/ が作られない（regression）" {
  # main ブランチを返す git stub（issue_num が解決されない）
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "main" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *)
        exit 0 ;;
    esac
  '
  # WORKER_ISSUE_NUM 未設定で実行
  unset WORKER_ISSUE_NUM 2>/dev/null || true

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-extract
  assert_success

  # issue-unknown/ ディレクトリが存在しないこと
  local forbidden_dir="$SANDBOX/.dev-session/issue-unknown"
  [ ! -d "$forbidden_dir" ] || {
    echo "FAIL: $forbidden_dir が存在してはならないが作成されている"
    false
  }
}

# ---------------------------------------------------------------------------
# AC2 テスト: chain-runner.sh の step_init に export SNAPSHOT_DIR が実装されている
#
# 実装前: chain-runner.sh に export SNAPSHOT_DIR= が存在しない → RED
# 実装後: export SNAPSHOT_DIR= が存在する → GREEN
# ---------------------------------------------------------------------------

@test "#938-AC2: chain-runner.sh step_init に export SNAPSHOT_DIR が実装されている" {
  # 静的コード検証: chain-runner.sh に export SNAPSHOT_DIR= が含まれること
  # 実装前は存在しないため RED、実装後は GREEN になる
  run grep -q 'export SNAPSHOT_DIR=' "$SANDBOX/scripts/chain-runner.sh"
  assert_success
}
