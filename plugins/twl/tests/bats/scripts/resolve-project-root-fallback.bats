#!/usr/bin/env bats
# resolve-project-root-fallback.bats - TDD RED tests for Issue #966
#
# Spec: Issue #966 — chain-runner.sh の resolve_project_root() が
#       || pwd フォールバックで誤 root を返す問題の修正
#
# 修正後の実装（3 段 fallback）:
#   tier 1: git rev-parse --show-toplevel（CWD が git repo 内）
#   tier 2: script dir から git rev-parse --show-toplevel（CWD 非 git でも script は worktree 内）
#   tier 3: 両方失敗 → stderr に FATAL msg 出力して exit 1
#
# テスト方法: bash chain-runner.sh resolve-project-root サブコマンドを呼び出す
#   - 実装前: dispatch が "resolve-project-root" を未知ステップとして ERROR → 全 7 テスト RED
#   - 実装後: resolve_project_root が正しく動作 → 全 7 テスト GREEN
#
# 全テストは実装前に FAIL（RED）する。
# 実装（AC1/AC2/AC3）完了後に GREEN になること。

load '../helpers/common'

setup() {
  common_setup

  # resolve-project.sh stub（chain-runner.sh が source する場合に備えて）
  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "6 PVT_project_id shuu5 twill-ecosystem shuu5/twill"
}
RESOLVE_PROJECT
  chmod +x "$SANDBOX/scripts/lib/resolve-project.sh"

  # python3 stub: chain-runner.sh 初期化時に import twl が呼ばれる可能性
  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *"-c"*"import twl"*)
    exit 0 ;;
  *"twl.autopilot.state"*|*"twl.autopilot.github"*)
    exit 0 ;;
  *)
    exit 0 ;;
esac
PYSTUB
  chmod +x "$STUB_BIN/python3"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# case 1 (normal: CWD が main worktree)
#
# 通常ケース: CWD が git worktree 内のとき tier 1 で解決される。
# 期待: stdout = $SANDBOX, exit 0
#
# 実装前 RED 理由: dispatch に "resolve-project-root" エントリが存在しないため
#   "ERROR: 未知のステップ: resolve-project-root" と出力して exit 1 する
# ---------------------------------------------------------------------------

@test "#966-AC3 case1: CWD が main worktree のとき resolve_project_root → stdout=worktree_root, exit 0" {
  # git stub: CWD=$SANDBOX で tier 1 成功
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        echo "'"$SANDBOX"'" ;;
      *"branch --show-current"*)
        echo "main" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/main\n" "'"$SANDBOX"'" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" resolve-project-root
  assert_success
  assert_output "$SANDBOX"
}

# ---------------------------------------------------------------------------
# case 2 (normal: CWD が feature worktree)
#
# feature worktree から呼び出した場合も tier 1 で正しく解決される。
# 各 worktree の git rev-parse --show-toplevel は その worktree root を返す。
# 期待: stdout = feature_worktree_root, exit 0
#
# 実装前 RED 理由: dispatch に "resolve-project-root" エントリが存在しない
# ---------------------------------------------------------------------------

@test "#966-AC3 case2: CWD が feature worktree のとき resolve_project_root → stdout=feature_worktree_root, exit 0" {
  local feature_wt="$SANDBOX/feature-worktree"
  mkdir -p "$feature_wt/scripts"
  # chain-runner.sh を feature_wt にコピー
  cp "$SANDBOX/scripts/chain-runner.sh" "$feature_wt/scripts/" 2>/dev/null || true
  cp -r "$SANDBOX/scripts/lib" "$feature_wt/scripts/" 2>/dev/null || true
  cp "$SANDBOX/scripts/chain-steps.sh" "$feature_wt/scripts/" 2>/dev/null || true
  cp "$SANDBOX/scripts/resolve-issue-num.sh" "$feature_wt/scripts/" 2>/dev/null || true

  # git stub: feature worktree から呼び出し → feature_wt を返す
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        echo "'"$feature_wt"'" ;;
      *"branch --show-current"*)
        echo "fix/966-feature-test" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/fix/966-feature-test\n" "'"$feature_wt"'" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$feature_wt/scripts/chain-runner.sh" resolve-project-root
  assert_success
  assert_output "$feature_wt"
}

# ---------------------------------------------------------------------------
# case 3 (script-path fallback: CWD 非 git、script は worktree 内)
#
# cd /tmp で chain-runner.sh を呼び出す。
# tier 1: CWD=/tmp → git rev-parse 失敗
# tier 2: script dir=$SANDBOX/scripts → git rev-parse 成功 → $SANDBOX を返す
# 期待: stdout = $SANDBOX, exit 0
#
# 実装前 RED 理由: dispatch に "resolve-project-root" エントリが存在しない
# ---------------------------------------------------------------------------

@test "#966-AC3 case3: CWD 非 git、script は worktree 内 → tier 2 発動、stdout=script_worktree_root, exit 0" {
  # git stub: CWD=/tmp では失敗、script dir では成功
  # BASH_SOURCE[0] のディレクトリ($SANDBOX/scripts)で git を実行するとき pwd=$SANDBOX/scripts
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        cwd="$(pwd)"
        if [[ "$cwd" == /tmp* || "$cwd" == /var/tmp* ]]; then
          exit 128
        fi
        echo "'"$SANDBOX"'"
        ;;
      *"branch --show-current"*)
        echo "fix/966-script-fallback" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/fix/966-script-fallback\n" "'"$SANDBOX"'" ;;
      *)
        exit 0 ;;
    esac
  '

  # CWD を /tmp にして実行（bash -c でサブシェルを使い絶対パスで chain-runner.sh を指定）
  run bash -c "cd /tmp && bash '$SANDBOX/scripts/chain-runner.sh' resolve-project-root"
  assert_success
  assert_output "$SANDBOX"
}

# ---------------------------------------------------------------------------
# case 4 (fail-fast: CWD 非 git、script も非 git)
#
# cd /tmp で呼び出し、かつ script dir も git 外。
# tier 1: CWD=/tmp → git rev-parse 失敗
# tier 2: script dir も非 git → git rev-parse 失敗
# tier 3: FATAL msg を stderr に出力し exit 1
# 期待: exit 1, stderr に "[chain-runner] FATAL: resolve_project_root failed", stdout は空
#
# 実装前 RED 理由: dispatch に "resolve-project-root" エントリが存在しない
# ---------------------------------------------------------------------------

@test "#966-AC3 case4: CWD 非 git、script も非 git → tier 3 発動、stderr に FATAL msg, exit 1, stdout 空" {
  # git stub: rev-parse --show-toplevel は全パスで失敗
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        exit 128 ;;
      *"branch --show-current"*)
        echo "fix/966-all-fail" ;;
      *"status --porcelain"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  local stderr_file
  stderr_file="$SANDBOX/case4_stderr.txt"

  # run の 3-arg 形式: run --separate-stderr bash -c "..." は bats 1.5+ で使える
  # ここでは手動で stdout/stderr を分離して捕捉する
  set +e
  actual_stdout="$(cd /tmp && bash "$SANDBOX/scripts/chain-runner.sh" resolve-project-root 2>"$stderr_file")"
  actual_exit=$?
  set -e

  actual_stderr="$(cat "$stderr_file" 2>/dev/null || echo "")"

  # exit 1 であること（実装前: dispatch エラーも exit 1）
  [[ "$actual_exit" -ne 0 ]] || {
    echo "FAIL: exit 0 が返った。exit 1 が期待される"
    false
  }

  # stdout に /tmp が含まれないこと（|| pwd 撤廃確認）
  [[ "$actual_stdout" != /tmp* && "$actual_stdout" != /var/tmp* ]] || {
    echo "FAIL: stdout に /tmp パスが含まれる（|| pwd fallback が残っている）: $actual_stdout"
    false
  }

  # 実装後: stderr に FATAL msg が含まれること
  # 実装前 RED 理由: dispatch エラーは "ERROR: 未知のステップ" を stderr に出すが
  #   "FATAL: resolve_project_root failed" というメッセージは出力しない
  #   → この assertion が fail して RED となる
  [[ "$actual_stderr" == *"FATAL: resolve_project_root failed"* ]] || {
    echo "FAIL: stderr に 'FATAL: resolve_project_root failed' が含まれない"
    echo "actual_stderr: $actual_stderr"
    false
  }
}

# ---------------------------------------------------------------------------
# case 5 (detached HEAD worktree)
#
# detached HEAD 状態の worktree から呼び出す。
# detached HEAD でも git rev-parse --show-toplevel は worktree root を返す。
# 期待: tier 1 で正常解決、stdout = $SANDBOX, exit 0
#
# 実装前 RED 理由: dispatch に "resolve-project-root" エントリが存在しない
# ---------------------------------------------------------------------------

@test "#966-AC3 case5: detached HEAD worktree から呼び出し → tier 1 で正常解決, exit 0" {
  # git stub: detached HEAD 状態（branch --show-current は空を返す）
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        echo "'"$SANDBOX"'" ;;
      *"branch --show-current"*)
        echo "" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nHEAD abc1234567890abcdef1234567890abcdef12345678\ndetached\n" "'"$SANDBOX"'" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" resolve-project-root
  assert_success
  assert_output "$SANDBOX"
}

# ---------------------------------------------------------------------------
# case 6 (multi-worktree)
#
# 複数 worktree が存在する場合、各 worktree から呼び出すと
# 各自の worktree root が正しく返る。
# 期待: worktree-A からは worktree-A root、worktree-B からは worktree-B root
#
# 実装前 RED 理由: dispatch に "resolve-project-root" エントリが存在しない
# ---------------------------------------------------------------------------

@test "#966-AC3 case6: 複数 worktree 存在時に各 worktree から呼び出すと各自の root が返る" {
  local wt_a="$SANDBOX/worktree-a"
  local wt_b="$SANDBOX/worktree-b"
  mkdir -p "$wt_a/scripts" "$wt_b/scripts"

  # worktree-a に chain-runner.sh をコピー
  cp "$SANDBOX/scripts/chain-runner.sh" "$wt_a/scripts/" 2>/dev/null || true
  cp -r "$SANDBOX/scripts/lib" "$wt_a/scripts/" 2>/dev/null || true
  cp "$SANDBOX/scripts/chain-steps.sh" "$wt_a/scripts/" 2>/dev/null || true
  cp "$SANDBOX/scripts/resolve-issue-num.sh" "$wt_a/scripts/" 2>/dev/null || true

  # worktree-b に chain-runner.sh をコピー
  cp "$SANDBOX/scripts/chain-runner.sh" "$wt_b/scripts/" 2>/dev/null || true
  cp -r "$SANDBOX/scripts/lib" "$wt_b/scripts/" 2>/dev/null || true
  cp "$SANDBOX/scripts/chain-steps.sh" "$wt_b/scripts/" 2>/dev/null || true
  cp "$SANDBOX/scripts/resolve-issue-num.sh" "$wt_b/scripts/" 2>/dev/null || true

  # worktree-a テスト用 git stub
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        echo "'"$wt_a"'" ;;
      *"branch --show-current"*)
        echo "fix/966-wt-a" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/fix/966-wt-a\n" "'"$wt_a"'" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$wt_a/scripts/chain-runner.sh" resolve-project-root
  assert_success
  assert_output "$wt_a"

  # worktree-b テスト用 git stub（$wt_b を返す）
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        echo "'"$wt_b"'" ;;
      *"branch --show-current"*)
        echo "fix/966-wt-b" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/fix/966-wt-b\n" "'"$wt_b"'" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$wt_b/scripts/chain-runner.sh" resolve-project-root
  assert_success
  assert_output "$wt_b"
}

# ---------------------------------------------------------------------------
# case 7 (pwd 非採用 assertion — || pwd 撤廃の regression guard)
#
# cd /tmp で chain-runner.sh を呼び出したとき、返値が /tmp または
# /var/tmp で始まらないことを explicit assert する。
# tier 3 発動（exit 1）または tier 2 発動（script root 返却）のいずれでも
# /tmp が stdout に出てはならない。
# 期待: stdout が /tmp* または /var/tmp* で始まらない
#
# 実装前 RED 理由: dispatch に "resolve-project-root" エントリが存在しない
#   実装直後で || pwd が残っている場合: stdout = /tmp で fail する（regression guard）
# ---------------------------------------------------------------------------

@test "#966-AC3 case7: cd /tmp で呼び出し → stdout が /tmp で始まらない（|| pwd 撤廃 regression guard）" {
  # git stub: CWD=/tmp では失敗、script dir ($SANDBOX/scripts) では成功
  # → tier 2 発動で $SANDBOX が返るはず
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        cwd="$(pwd)"
        if [[ "$cwd" == /tmp* || "$cwd" == /var/tmp* ]]; then
          exit 128
        fi
        echo "'"$SANDBOX"'"
        ;;
      *"branch --show-current"*)
        echo "fix/966-pwd-regression" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/fix/966-pwd-regression\n" "'"$SANDBOX"'" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash -c "cd /tmp && bash '$SANDBOX/scripts/chain-runner.sh' resolve-project-root"

  # tier 2 発動なら exit 0 で $SANDBOX が返ること（実装前は exit 1）
  # RED: dispatch に resolve-project-root が存在しないため exit 1 → assert_success が fail
  assert_success

  # stdout が /tmp または /var/tmp で始まらないこと（|| pwd 撤廃の explicit assert）
  if [[ "$output" == /tmp* || "$output" == /var/tmp* ]]; then
    fail "stdout が /tmp または /var/tmp で始まる: '$output' — || pwd が残っている可能性（regression）"
  fi
}
