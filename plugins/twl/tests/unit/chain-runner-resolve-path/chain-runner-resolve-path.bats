#!/usr/bin/env bats
# chain-runner-resolve-path.bats
# Requirement: chain-runner.sh の _resolve_path() ヘルパーが GNU/BSD/macOS で互換動作する
# Spec: Wave S Quality Review H1 follow-up (#1041/#1042)
# Coverage: --type=unit --coverage=portability
#
# 検証する仕様:
#   1. _resolve_path() ヘルパーが定義されている (structural)
#   2. GNU realpath / greadlink / python3 の 3 段 fallback が実装されている (structural)
#   3. trace_event() が _resolve_path を使用している (structural)
#   4. GNU realpath が利用不可でも python3 fallback で /tmp 配下の trace が作成される (functional)

load '../../bats/helpers/common.bash'

setup() {
  common_setup

  export WORKER_ISSUE_NUM=1041

  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1 (structural): _resolve_path() ヘルパー関数が定義されている
# ===========================================================================

@test "resolve-path[structural]: chain-runner.sh に _resolve_path() ヘルパー関数が定義されている" {
  grep -F '_resolve_path()' "$CR" || {
    echo "FAIL: _resolve_path() 関数定義が chain-runner.sh に含まれていない" >&2
    return 1
  }
}

# ===========================================================================
# AC2 (structural): _resolve_path() に GNU realpath / greadlink / python3 の 3 段 fallback が含まれる
# ===========================================================================

@test "resolve-path[structural]: _resolve_path() に GNU realpath fallback (Tier 1) が含まれる" {
  awk '/^_resolve_path\(\) \{/,/^\}$/' "$CR" | grep -F 'realpath --canonicalize-missing' || {
    echo "FAIL: _resolve_path() に GNU realpath --canonicalize-missing が含まれていない" >&2
    return 1
  }
}

@test "resolve-path[structural]: _resolve_path() に greadlink fallback (Tier 2, macOS coreutils) が含まれる" {
  awk '/^_resolve_path\(\) \{/,/^\}$/' "$CR" | grep -F 'greadlink -f' || {
    echo "FAIL: _resolve_path() に greadlink -f が含まれていない" >&2
    return 1
  }
}

@test "resolve-path[structural]: _resolve_path() に python3 os.path.realpath fallback (Tier 3, POSIX) が含まれる" {
  awk '/^_resolve_path\(\) \{/,/^\}$/' "$CR" | grep -F 'os.path.realpath' || {
    echo "FAIL: _resolve_path() に python3 os.path.realpath fallback が含まれていない" >&2
    return 1
  }
}

# ===========================================================================
# AC3 (structural): trace_event() が _resolve_path を使用している
# ===========================================================================

@test "resolve-path[structural]: trace_event() が _resolve_path を使用している" {
  awk '/^trace_event\(\) \{/,/^\}$/' "$CR" | grep -F '_resolve_path' || {
    echo "FAIL: trace_event() が _resolve_path を使用していない（直接 realpath 呼び出しが残っている可能性）" >&2
    return 1
  }
}

# ===========================================================================
# AC4 (functional): GNU realpath / greadlink が利用不可でも python3 fallback で動作する
# Linux 上で macOS 環境を simulate するため、stub bin で realpath/greadlink を exit 1 にする
# ===========================================================================

@test "resolve-path[functional]: realpath/greadlink 不在でも python3 fallback で /tmp 配下の trace が作成される" {
  # stub bin で realpath と greadlink を強制 fail
  cat > "$STUB_BIN/realpath" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  cat > "$STUB_BIN/greadlink" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$STUB_BIN/realpath" "$STUB_BIN/greadlink"

  local trace_path="/tmp/twl-test-h1-pyfallback-$$"
  rm -f "$trace_path" 2>/dev/null || true

  run bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -f "$trace_path" 2>/dev/null || true

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: realpath/greadlink fail 状態で python3 fallback が動作せず trace が作成されなかった: $trace_path" >&2
    return 1
  }
}

# ===========================================================================
# AC5 (functional): すべての fallback が利用不可なら書き込み拒否（安全側）
# ===========================================================================

@test "resolve-path[functional]: realpath/greadlink/python3 すべて利用不可なら書き込みを拒否する" {
  # stub で全部 fail
  cat > "$STUB_BIN/realpath" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  cat > "$STUB_BIN/greadlink" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  cat > "$STUB_BIN/python3" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$STUB_BIN/realpath" "$STUB_BIN/greadlink" "$STUB_BIN/python3"

  local trace_path="/tmp/twl-test-h1-allfail-$$"
  rm -f "$trace_path" 2>/dev/null || true

  # python3 が fail すると chain-runner.sh の他処理が壊れる可能性（resolve-issue-num など）
  # → 単に呼び出して trace_path に書き込まれないことを確認、exit code は問わない
  bash "$CR" --trace "$trace_path" resolve-issue-num 2>/dev/null || true

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -f "$trace_path" 2>/dev/null || true

  [[ "$file_created" -eq 0 ]] || {
    echo "FAIL: 全 fallback fail 状態で trace が作成された（安全側拒否されていない）: $trace_path" >&2
    return 1
  }
}
