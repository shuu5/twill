#!/usr/bin/env bats
# chain-runner-trace-event-traversal.bats
#
# Issue #1067: trace_event の case '*..*' は相対パス traversal 拒否のみに適用すべき
#
# Coverage:
#   AC1: 相対パスに '..' が含まれる場合は case check でブロックされる（regression guard）
#   AC2: 絶対パスに literal '..' が含まれる場合は case check でブロック**せず**、
#        _resolve_path に委譲して正規化後に whitelist チェックを行う（RED: 現在 FAIL）

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/1067-tech-debt-chain-runnersh-traceevent-c" ;;
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
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "1 PVT_id shuu5 twill shuu5/twill"
}
RESOLVE_PROJECT

  create_issue_json 1067 "running"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: 相対パスの '..' は case check でブロックされること（regression guard）
# ---------------------------------------------------------------------------

@test "#1067 AC1: relative path with '..' is blocked by case check (traversal protection)" {
  # 相対パス: foo/../etc/trace.jsonl は case '*..*' でブロックされるべき
  local trace_path="foo/../trace_1067_ac1.jsonl"

  run env \
    TWL_CHAIN_TRACE="$trace_path" \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    bash "$SANDBOX/scripts/chain-runner.sh" init 1067

  # trace file が相対パスとして存在しないこと（traversal はブロック済み）
  [ ! -f "$trace_path" ]
  [ ! -f "$SANDBOX/$trace_path" ]
}

# ---------------------------------------------------------------------------
# AC2: 絶対パスに literal '..' が含まれる場合は case check でブロックしないこと
#       _resolve_path が正規化し、/tmp/* whitelist を通過してトレースが書き込まれる
#
# RED: 現在の実装では case '*..*' が絶対パスにも適用されるため FAIL する
# GREEN: Option B 修正後（絶対パスに対する case check スキップ）で PASS する
# ---------------------------------------------------------------------------

@test "#1067 AC2: absolute path with literal '..' is NOT blocked by case check (RED)" {
  # SANDBOX は mktemp -d で /tmp 配下に作成される
  # SANDBOX/.autopilot/../trace_1067_ac2.jsonl は絶対パスに '..' を含む
  # _resolve_path で SANDBOX/trace_1067_ac2.jsonl に正規化 → /tmp/* whitelist 通過
  local trace_path="$SANDBOX/.autopilot/../trace_1067_ac2.jsonl"
  local resolved_path="$SANDBOX/trace_1067_ac2.jsonl"

  run env \
    TWL_CHAIN_TRACE="$trace_path" \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    bash "$SANDBOX/scripts/chain-runner.sh" init 1067

  # trace ファイルが resolved_path に書き込まれていることを確認
  # 現在: case '*..*' が絶対パスをブロック → ファイル未生成 → FAIL (RED)
  # 修正後: case check スキップ → _resolve_path → ファイル生成 → PASS
  [ -f "$resolved_path" ] || {
    echo "FAIL: trace file not written at $resolved_path" >&2
    echo "  TWL_CHAIN_TRACE was: $trace_path" >&2
    echo "  Expected: case '*..*' should NOT block absolute paths" >&2
    echo "  Actual: current code blocks all paths containing '..' (including absolute)" >&2
    return 1
  }
}
