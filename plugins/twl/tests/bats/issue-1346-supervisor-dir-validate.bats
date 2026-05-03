#!/usr/bin/env bats
# issue-1346-supervisor-dir-validate.bats
#
# Issue #1346: tech-debt: spawn-controller.sh の SUPERVISOR_DIR パス検証を共有 lib に統一する
#
# AC1: spawn-controller.sh の L57/L258/L337 で SUPERVISOR_DIR をスクリプト冒頭の単一 validate 呼び出しで保護する
# AC2: 共有検証ロジックを plugins/twl/scripts/lib/supervisor-dir-validate.sh に切り出す
# AC3: 既存の重複検証 (session-init.sh / step0-monitor-bootstrap.sh / record-detection-gap.sh) を共有 lib 経由に統一する
# AC4: 未検証だった残り (step0-memory-ambient.sh / heartbeat-watcher.sh / auto-next-spawn.sh) にも共有 lib を適用する
# AC5: 検証エラー時の exit code・メッセージ形式を統一する
# AC6: bats テストで (a)絶対パス (b)..を含む (c)禁止文字 (d)正常パス を lib 単体テストでカバーする
# AC7: 既存の source するスクリプトが 1 つも壊れないことを twl validate / 既存 bats で確認
# AC8: supervisor-dir-validate.sh を deps.yaml の lib エントリに追加する
#
# RED フェーズ: AC1〜AC8 は実装前に全て FAIL する

load 'helpers/common'

LIB_VALIDATE=""
SPAWN_SCRIPT=""
SESSION_INIT_SCRIPT=""
STEP0_MONITOR_SCRIPT=""
RECORD_DETECTION_SCRIPT=""
STEP0_MEMORY_SCRIPT=""
HEARTBEAT_SCRIPT=""
AUTO_NEXT_SPAWN_SCRIPT=""
DEPS_YAML=""

setup() {
  common_setup

  LIB_VALIDATE="$REPO_ROOT/scripts/lib/supervisor-dir-validate.sh"
  SPAWN_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  SESSION_INIT_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/session-init.sh"
  STEP0_MONITOR_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/step0-monitor-bootstrap.sh"
  RECORD_DETECTION_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/record-detection-gap.sh"
  STEP0_MEMORY_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/step0-memory-ambient.sh"
  HEARTBEAT_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/heartbeat-watcher.sh"
  AUTO_NEXT_SPAWN_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/auto-next-spawn.sh"
  DEPS_YAML="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)/plugins/twl/deps.yaml"

  # cld-spawn stub
  stub_command "cld-spawn" 'echo "stub-cld-spawn: $*"; exit 0'

  # tmux stub (spawn-controller.sh が tmux を呼ぶ場合に備える)
  stub_command "tmux" 'echo "tmux-stub: $*"; exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# ヘルパー: validate 関数を source して呼び出す
# ---------------------------------------------------------------------------
_source_lib_and_validate() {
  local dir="$1"
  bash -c "
    source '${LIB_VALIDATE}' 2>/dev/null || exit 127
    validate_supervisor_dir '${dir}'
  "
}

# ---------------------------------------------------------------------------
# ヘルパー: spawn-controller.sh を SUPERVISOR_DIR 付きで実行（最小引数）
# ---------------------------------------------------------------------------
_run_spawn_with_supervisor_dir() {
  local dir="$1"
  local prompt_file
  prompt_file="$SANDBOX/test-prompt.txt"
  echo "test prompt" > "$prompt_file"
  # SKIP_PARALLEL_CHECK=1 で内部チェックをバイパス（SUPERVISOR_DIR 検証のみを試験）
  SUPERVISOR_DIR="$dir" SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="test" \
    run bash "$SPAWN_SCRIPT" co-explore "$prompt_file"
}

# ===========================================================================
# AC1: spawn-controller.sh の SUPERVISOR_DIR 検証がスクリプト冒頭の単一呼び出しとなっている
#
# 現在の状態: L57 に `mkdir -p "$_supervisor_dir"` がありパス検証なし
# RED: 実装前は validate 呼び出しが存在しないため fail
# ===========================================================================

@test "ac1: spawn-controller.sh が絶対パスの SUPERVISOR_DIR を冒頭で拒否する" {
  # 実装前は validate_supervisor_dir が呼ばれず、SUPERVISOR_DIR 検証エラーメッセージが出力されない
  # RED: assert_output --partial "SUPERVISOR_DIR" が実装前に fail する
  _run_spawn_with_supervisor_dir "/tmp/evil-supervisor"
  assert_failure
  assert_output --partial "SUPERVISOR_DIR" || {
    echo "FAIL: AC #1 未実装 — spawn-controller.sh が SUPERVISOR_DIR 検証エラーを出力していない" >&2
    echo "  期待: スクリプト冒頭で validate_supervisor_dir を呼び出し、SUPERVISOR_DIR に言及したエラーを stderr に出力" >&2
    return 1
  }
}

@test "ac1: spawn-controller.sh が '..' を含む SUPERVISOR_DIR を冒頭で拒否する" {
  # RED: 実装前は '..' チェックの SUPERVISOR_DIR 検証エラーメッセージが出力されない
  _run_spawn_with_supervisor_dir "../../evil"
  assert_failure
  assert_output --partial "SUPERVISOR_DIR" || {
    echo "FAIL: AC #1 未実装 — spawn-controller.sh が '..' を含む SUPERVISOR_DIR 検証エラーを出力していない" >&2
    return 1
  }
}

@test "ac1: spawn-controller.sh が禁止文字を含む SUPERVISOR_DIR を冒頭で拒否する" {
  # RED: 実装前は禁止文字チェックの SUPERVISOR_DIR 検証エラーメッセージが出力されない
  local dangerous_dir
  dangerous_dir='.supervisor;rm -rf /'
  _run_spawn_with_supervisor_dir "$dangerous_dir"
  assert_failure
  assert_output --partial "SUPERVISOR_DIR" || {
    echo "FAIL: AC #1 未実装 — spawn-controller.sh が禁止文字を含む SUPERVISOR_DIR 検証エラーを出力していない" >&2
    return 1
  }
}

@test "ac1: spawn-controller.sh に validate_supervisor_dir 呼び出しが存在する" {
  # 実装確認: スクリプト冒頭に validate_supervisor_dir or source supervisor-dir-validate の記述が必要
  local has_validate=0
  if grep -qE 'validate_supervisor_dir|supervisor-dir-validate' "$SPAWN_SCRIPT" 2>/dev/null; then
    has_validate=1
  fi
  [[ "$has_validate" -gt 0 ]] || {
    echo "FAIL: AC #1 未実装 — spawn-controller.sh に validate_supervisor_dir 呼び出しが存在しない" >&2
    echo "  期待: source lib/supervisor-dir-validate.sh + validate_supervisor_dir 呼び出し" >&2
    return 1
  }
}

# ===========================================================================
# AC2: 共有検証ロジックが plugins/twl/scripts/lib/supervisor-dir-validate.sh に存在する
#
# 現在の状態: ファイル未存在
# RED: 実装前は fail
# ===========================================================================

@test "ac2: supervisor-dir-validate.sh ファイルが存在する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #2 未実装 — $LIB_VALIDATE が存在しない" >&2
    echo "  期待: plugins/twl/scripts/lib/supervisor-dir-validate.sh を新規作成すること" >&2
    return 1
  }
}

@test "ac2: supervisor-dir-validate.sh が validate_supervisor_dir 関数をエクスポートする" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #2 未実装 — $LIB_VALIDATE が存在しない（前提条件）" >&2
    return 1
  }
  bash -c "source '$LIB_VALIDATE' && declare -f validate_supervisor_dir" | grep -q "validate_supervisor_dir" || {
    echo "FAIL: AC #2 未実装 — validate_supervisor_dir 関数が定義されていない" >&2
    return 1
  }
}

# ===========================================================================
# AC3: 既存の重複検証が共有 lib 経由に統一されている
#
# 現在の状態: session-init.sh, step0-monitor-bootstrap.sh, record-detection-gap.sh が
#            それぞれ独自パターンでインラインバリデーション
# RED: 実装前は各スクリプトが共有 lib を source していない
# ===========================================================================

@test "ac3: session-init.sh が supervisor-dir-validate.sh を source している" {
  grep -qE 'supervisor-dir-validate|validate_supervisor_dir' "$SESSION_INIT_SCRIPT" 2>/dev/null || {
    echo "FAIL: AC #3 未実装 — session-init.sh が共有 lib を使用していない" >&2
    echo "  期待: source lib/supervisor-dir-validate.sh + validate_supervisor_dir 呼び出し" >&2
    return 1
  }
}

@test "ac3: step0-monitor-bootstrap.sh が supervisor-dir-validate.sh を source している" {
  grep -qE 'supervisor-dir-validate|validate_supervisor_dir' "$STEP0_MONITOR_SCRIPT" 2>/dev/null || {
    echo "FAIL: AC #3 未実装 — step0-monitor-bootstrap.sh が共有 lib を使用していない" >&2
    echo "  期待: source lib/supervisor-dir-validate.sh + validate_supervisor_dir 呼び出し" >&2
    return 1
  }
}

@test "ac3: record-detection-gap.sh が supervisor-dir-validate.sh を source している" {
  grep -qE 'supervisor-dir-validate|validate_supervisor_dir' "$RECORD_DETECTION_SCRIPT" 2>/dev/null || {
    echo "FAIL: AC #3 未実装 — record-detection-gap.sh が共有 lib を使用していない" >&2
    echo "  期待: source lib/supervisor-dir-validate.sh + validate_supervisor_dir 呼び出し" >&2
    return 1
  }
}

# ===========================================================================
# AC4: 未検証だったスクリプトにも共有 lib を適用する
#
# 現在の状態: step0-memory-ambient.sh, heartbeat-watcher.sh, auto-next-spawn.sh は
#            SUPERVISOR_DIR を validate なしで使用している
# RED: 実装前は各スクリプトが共有 lib を source していない
# ===========================================================================

@test "ac4: step0-memory-ambient.sh が supervisor-dir-validate.sh を source している" {
  grep -qE 'supervisor-dir-validate|validate_supervisor_dir' "$STEP0_MEMORY_SCRIPT" 2>/dev/null || {
    echo "FAIL: AC #4 未実装 — step0-memory-ambient.sh が共有 lib を使用していない" >&2
    echo "  現在: SUPERVISOR_DIR を validate なしで mkdir-p / ファイル参照している" >&2
    return 1
  }
}

@test "ac4: heartbeat-watcher.sh が supervisor-dir-validate.sh を source している" {
  grep -qE 'supervisor-dir-validate|validate_supervisor_dir' "$HEARTBEAT_SCRIPT" 2>/dev/null || {
    echo "FAIL: AC #4 未実装 — heartbeat-watcher.sh が共有 lib を使用していない" >&2
    echo "  現在: SUPERVISOR_DIR を validate なしで使用している" >&2
    return 1
  }
}

@test "ac4: auto-next-spawn.sh が supervisor-dir-validate.sh を source している" {
  grep -qE 'supervisor-dir-validate|validate_supervisor_dir' "$AUTO_NEXT_SPAWN_SCRIPT" 2>/dev/null || {
    echo "FAIL: AC #4 未実装 — auto-next-spawn.sh が共有 lib を使用していない" >&2
    echo "  現在: _SUPERVISOR_DIR を validate なしで使用している" >&2
    return 1
  }
}

# ===========================================================================
# AC5: 検証エラー時の exit code・メッセージ形式が統一されている
#
# 現在の状態:
#   session-init.sh: exit 1, "[session-init] ERROR: ..." 形式
#   step0-monitor-bootstrap.sh: exit 2, "ERROR: ..." 形式
#   record-detection-gap.sh: exit 1, "ERROR: ..." 形式
# RED: 統一前は各スクリプトの exit code が不一致
#
# また auto-next-spawn.sh は set -uo pipefail (-e なし) で動作するため
# validate_supervisor_dir || exit 1 パターンが正しく機能することを確認する
# ===========================================================================

@test "ac5: validate_supervisor_dir が不正パスで exit 1 を返す（exit code 統一）" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #5 未実装 — $LIB_VALIDATE が存在しない（前提条件）" >&2
    return 1
  }
  # validate 関数が exit 1 で統一されているか確認
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '/absolute/path'"
  [[ "$status" -eq 1 ]] || {
    echo "FAIL: AC #5 未実装 — validate_supervisor_dir の exit code が 1 でない (got: $status)" >&2
    echo "  期待: exit 1 (全スクリプトで統一)" >&2
    return 1
  }
}

@test "ac5: validate_supervisor_dir が '..' 含むパスで exit 1 を返す（exit code 統一）" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #5 未実装 — $LIB_VALIDATE が存在しない（前提条件）" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '../../etc/passwd'"
  [[ "$status" -eq 1 ]] || {
    echo "FAIL: AC #5 未実装 — validate_supervisor_dir が '..' で exit 1 を返さない (got: $status)" >&2
    return 1
  }
}

@test "ac5: auto-next-spawn.sh で validate_supervisor_dir || exit 1 パターンが機能する" {
  # auto-next-spawn.sh は set -uo pipefail (-e なし) で動作する
  # validate_supervisor_dir || exit 1 の明示パターンが必要
  grep -qE 'validate_supervisor_dir.*\|\|.*exit|validate_supervisor_dir' "$AUTO_NEXT_SPAWN_SCRIPT" 2>/dev/null || {
    echo "FAIL: AC #5 未実装 — auto-next-spawn.sh に validate_supervisor_dir 呼び出しが存在しない" >&2
    echo "  注意: set -uo pipefail (-e なし) 環境なので '|| exit 1' パターンが必要" >&2
    return 1
  }
  # set -e なし環境でも exit 1 が機能するか確認（手動 || exit 1 パターン）
  if [[ -f "$LIB_VALIDATE" ]]; then
    run bash -c "
      set -uo pipefail
      source '$LIB_VALIDATE'
      validate_supervisor_dir '/absolute/bad' || exit 1
      echo 'should not reach here'
    "
    assert_failure || {
      echo "FAIL: AC #5 — set -uo pipefail 環境で validate_supervisor_dir || exit 1 が機能しない" >&2
      return 1
    }
  else
    echo "FAIL: AC #5 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC6: supervisor-dir-validate.sh 単体テスト
#        (a) 絶対パス → 拒否
#        (b) '..' を含む → 拒否
#        (c) 禁止文字 ($ ; | \ & ( ) < >) → 拒否
#        (d) 正常パス → 受理
#
# RED: supervisor-dir-validate.sh が存在しないため全て fail
# ===========================================================================

@test "ac6a: lib 単体 — 絶対パス '/etc/supervisor' を拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6a 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '/etc/supervisor'"
  assert_failure || {
    echo "FAIL: AC #6a — 絶対パス '/etc/supervisor' が拒否されなかった" >&2
    return 1
  }
}

@test "ac6a: lib 単体 — 絶対パス '/tmp/s' のエラーメッセージが stderr に出力される" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6a 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '/tmp/s' 2>&1"
  assert_output --partial "absolute" || assert_output --partial "不正" || assert_output --partial "ERROR" || {
    echo "FAIL: AC #6a — 絶対パスエラーメッセージが出力されなかった (got: $output)" >&2
    return 1
  }
}

@test "ac6b: lib 単体 — '..' を含むパス '../../evil' を拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6b 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '../../evil'"
  assert_failure || {
    echo "FAIL: AC #6b — '..' を含むパス '../../evil' が拒否されなかった" >&2
    return 1
  }
}

@test "ac6b: lib 単体 — '..' を含むパス '.supervisor/../etc' を拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6b 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '.supervisor/../etc'"
  assert_failure || {
    echo "FAIL: AC #6b — '.supervisor/../etc' が拒否されなかった" >&2
    return 1
  }
}

@test "ac6c: lib 単体 — '\$' を含む変数展開文字パスを拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6c 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  local dangerous_path
  dangerous_path='$HOME/.supervisor'
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '${dangerous_path}'"
  assert_failure || {
    echo "FAIL: AC #6c — '\$HOME/.supervisor' が拒否されなかった" >&2
    return 1
  }
}

@test "ac6c: lib 単体 — ';' を含むパスを拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6c 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '.supervisor;rm -rf /'"
  assert_failure || {
    echo "FAIL: AC #6c — セミコロンを含むパスが拒否されなかった" >&2
    return 1
  }
}

@test "ac6c: lib 単体 — '|' を含むパスを拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6c 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '.supervisor|cat /etc/passwd'"
  assert_failure || {
    echo "FAIL: AC #6c — パイプ文字を含むパスが拒否されなかった" >&2
    return 1
  }
}

@test "ac6c: lib 単体 — '&' を含むパスを拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6c 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '.supervisor&evil'"
  assert_failure || {
    echo "FAIL: AC #6c — '&' を含むパスが拒否されなかった" >&2
    return 1
  }
}

@test "ac6c: lib 単体 — '(' ')' を含むパスを拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6c 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '.supervisor(evil)'"
  assert_failure || {
    echo "FAIL: AC #6c — '()' を含むパスが拒否されなかった" >&2
    return 1
  }
}

@test "ac6c: lib 単体 — '<' '>' を含むパスを拒否する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6c 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '.supervisor<>/evil'"
  assert_failure || {
    echo "FAIL: AC #6c — '<>' を含むパスが拒否されなかった" >&2
    return 1
  }
}

@test "ac6d: lib 単体 — 正常パス '.supervisor' を受理する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6d 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir '.supervisor'"
  assert_success || {
    echo "FAIL: AC #6d — 正常パス '.supervisor' が拒否された (status=$status, output=$output)" >&2
    return 1
  }
}

@test "ac6d: lib 単体 — 英数字・ハイフン・アンダースコアのパスを受理する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6d 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir 'my-supervisor_dir'"
  assert_success || {
    echo "FAIL: AC #6d — 正常パス 'my-supervisor_dir' が拒否された (status=$status, output=$output)" >&2
    return 1
  }
}

@test "ac6d: lib 単体 — スラッシュを含む相対パスを受理する" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #6d 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -c "source '$LIB_VALIDATE'; validate_supervisor_dir 'supervisor/data'"
  assert_success || {
    echo "FAIL: AC #6d — 正常パス 'supervisor/data' が拒否された (status=$status, output=$output)" >&2
    return 1
  }
}

# ===========================================================================
# AC7: 既存の source するスクリプトが 1 つも壊れない
#
# 現在の状態: 実装前は共有 lib が存在しないため、lib を source しようとすると破損する
# RED: 実装前は共有 lib が存在しないため検証不能 → fail
#
# NOTE: twl validate は本テストでは実行しない（CI 環境依存）。
#       session-init.sh / step0-monitor-bootstrap.sh / record-detection-gap.sh を
#       --help / 無引数で bash -n (syntax check) だけ確認する。
# ===========================================================================

@test "ac7: supervisor-dir-validate.sh が bash -n (syntax check) をパスする" {
  [[ -f "$LIB_VALIDATE" ]] || {
    echo "FAIL: AC #7 未実装 — $LIB_VALIDATE が存在しない" >&2
    return 1
  }
  run bash -n "$LIB_VALIDATE"
  assert_success || {
    echo "FAIL: AC #7 — supervisor-dir-validate.sh の syntax check 失敗" >&2
    return 1
  }
}

@test "ac7: session-init.sh が bash -n をパスする（lib 追加後も構文破損なし）" {
  run bash -n "$SESSION_INIT_SCRIPT"
  assert_success || {
    echo "FAIL: AC #7 — session-init.sh の syntax check 失敗（共有 lib 追加で壊れた可能性）" >&2
    return 1
  }
}

@test "ac7: step0-monitor-bootstrap.sh が bash -n をパスする（lib 追加後も構文破損なし）" {
  run bash -n "$STEP0_MONITOR_SCRIPT"
  assert_success || {
    echo "FAIL: AC #7 — step0-monitor-bootstrap.sh の syntax check 失敗" >&2
    return 1
  }
}

@test "ac7: record-detection-gap.sh が bash -n をパスする（lib 追加後も構文破損なし）" {
  run bash -n "$RECORD_DETECTION_SCRIPT"
  assert_success || {
    echo "FAIL: AC #7 — record-detection-gap.sh の syntax check 失敗" >&2
    return 1
  }
}

@test "ac7: step0-memory-ambient.sh が bash -n をパスする（lib 追加後も構文破損なし）" {
  run bash -n "$STEP0_MEMORY_SCRIPT"
  assert_success || {
    echo "FAIL: AC #7 — step0-memory-ambient.sh の syntax check 失敗" >&2
    return 1
  }
}

@test "ac7: heartbeat-watcher.sh が bash -n をパスする（lib 追加後も構文破損なし）" {
  run bash -n "$HEARTBEAT_SCRIPT"
  assert_success || {
    echo "FAIL: AC #7 — heartbeat-watcher.sh の syntax check 失敗" >&2
    return 1
  }
}

@test "ac7: auto-next-spawn.sh が bash -n をパスする（lib 追加後も構文破損なし）" {
  run bash -n "$AUTO_NEXT_SPAWN_SCRIPT"
  assert_success || {
    echo "FAIL: AC #7 — auto-next-spawn.sh の syntax check 失敗" >&2
    return 1
  }
}

@test "ac7: spawn-controller.sh が bash -n をパスする（lib 追加後も構文破損なし）" {
  run bash -n "$SPAWN_SCRIPT"
  assert_success || {
    echo "FAIL: AC #7 — spawn-controller.sh の syntax check 失敗" >&2
    return 1
  }
}

# ===========================================================================
# AC8: supervisor-dir-validate.sh が deps.yaml の lib エントリに追加されている
#
# 現在の状態: deps.yaml に supervisor-dir-validate.sh エントリなし
# RED: 実装前は fail
# ===========================================================================

@test "ac8: deps.yaml に supervisor-dir-validate.sh の lib エントリが存在する" {
  [[ -f "$DEPS_YAML" ]] || {
    echo "FAIL: AC #8 — deps.yaml が見つからない: $DEPS_YAML" >&2
    return 1
  }
  grep -q "supervisor-dir-validate" "$DEPS_YAML" || {
    echo "FAIL: AC #8 未実装 — deps.yaml に supervisor-dir-validate.sh エントリが存在しない" >&2
    echo "  期待: scripts/lib/supervisor-dir-validate.sh が lib エントリとして登録されていること" >&2
    return 1
  }
}
