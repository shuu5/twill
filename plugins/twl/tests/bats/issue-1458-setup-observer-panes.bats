#!/usr/bin/env bats
# issue-1458-setup-observer-panes.bats
# RED tests for Issue #1458: _setup_observer_panes が can't find pane: 2 で
# watcher group auto 起動失敗
#
# AC coverage:
#   AC1 - 1-pane observer window で spawn-controller.sh 実行 → 4 pane に分割成功 +
#          heartbeat-watcher / budget-monitor / cld-observe-any 起動確認
#   AC2 - 既に 4 pane 状態で spawn → 既存 pane 維持 + watcher 再起動
#   AC3 - ipatho-1 host で 2 連続 spawn 検証 (Wave 50 + Wave 51 相当)
#   AC4 - bats test で _setup_observer_panes の pane 数遷移を検証
#          AC4a (sync-barrier): Step1 と Step2 の間に list-panes または
#                split-window -P が含まれないことを確認し、不在なら fail
#          AC4b (pane-transitions): stateful tmux mock で split と split の間に
#                list-panes が呼ばれていないなら fail (sync barrier 不在の RED 証明)
#
# テスト設計:
#   - spawn-controller.sh に BASH_SOURCE[0] guard がないため direct source は禁止
#   - awk で _setup_observer_panes 関数定義のみを抽出して eval する
#   - _resolve_window_target はスタブ関数で差し替える
#   - tmux は STUB_BIN に stateful mock を設置して pane 数遷移を記録する
#
# RED: 現在の実装では split-window 呼び出し間に sync barrier がないため、
#      tmux pane 生成を待たずに次の split-window が実行され
#      "can't find pane: 2" エラーが発生する。
#      sync barrier を追加することでこれらのテストが GREEN になる。
#
# WARN (bats baseline §10):
#   spawn-controller.sh に [[ "${BASH_SOURCE[0]}" == "${0}" ]] guard が存在しない。
#   set -euo pipefail 環境で source すると main block に到達し exec が走るため
#   本テストでは source を使わず awk 抽出 + eval 方式を採用する。
#   impl_files 参照: plugins/twl/skills/su-observer/scripts/spawn-controller.sh への
#   source guard 追加を検討すること（Issue #1458 実装時に対応推奨）。

load 'helpers/common'

SPAWN_CONTROLLER=""

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  SPAWN_CONTROLLER="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  # .supervisor ディレクトリと session.json を SANDBOX に作成
  mkdir -p "$SANDBOX/.supervisor"

  # pkill stub（実プロセスを kill しない）
  cat > "$STUB_BIN/pkill" <<'PKILLSTUB'
#!/usr/bin/env bash
echo "pkill $*" >> "${PKILL_LOG:-/dev/null}"
exit 0
PKILLSTUB
  chmod +x "$STUB_BIN/pkill"

  export PKILL_LOG="$SANDBOX/pkill.log"
  touch "$PKILL_LOG"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: _load_functions
# _resolve_window_target スタブと _setup_observer_panes を eval でロードする
# ---------------------------------------------------------------------------
_load_functions() {
  # Stub _resolve_window_target
  _resolve_window_target() {
    echo "test-session:0"
    return 0
  }

  # Extract _setup_observer_panes via awk (avoids main block execution)
  local func_def
  func_def=$(awk '
    /^_setup_observer_panes\(\)/ { in_func=1; depth=0 }
    in_func {
      print
      for (i=1; i<=length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") depth++
        if (c == "}") { depth--; if (depth == 0) { in_func=0; exit } }
      }
    }
  ' "$SPAWN_CONTROLLER")

  if [[ -z "$func_def" ]]; then
    echo "RED: _setup_observer_panes 関数が spawn-controller.sh に存在しない" >&2
    return 1
  fi

  eval "$func_def"
}

# ---------------------------------------------------------------------------
# Helper: _setup_tmux_mock <initial_pane_count>
# stateful tmux mock を設置し pane 数遷移を記録する
# split-window 呼び出しごとに pane count を +1 する
# list-panes 呼び出し時の pane count もログに記録する
# ---------------------------------------------------------------------------
_setup_tmux_mock() {
  local initial_panes="${1:-1}"
  local pane_count_file="$SANDBOX/pane-count"
  echo "$initial_panes" > "$pane_count_file"
  touch "$SANDBOX/tmux-calls.log"
  touch "$SANDBOX/pane-transitions.log"

  # SANDBOX と pane_count_file を非クォート heredoc で展開（§9 外部変数に対応）
  cat > "$STUB_BIN/tmux" <<TMUXEOF
#!/usr/bin/env bash
echo "tmux \$*" >> "${SANDBOX}/tmux-calls.log"
PANE_COUNT=\$(cat "${pane_count_file}" 2>/dev/null || echo 1)
case "\${1:-}" in
  show-options) echo "0" ;;
  split-window)
    NEW_COUNT=\$((PANE_COUNT + 1))
    echo "\$NEW_COUNT" > "${pane_count_file}"
    echo "split-pane-count:\$NEW_COUNT" >> "${SANDBOX}/pane-transitions.log"
    ;;
  list-panes)
    echo "list-panes-at:\$PANE_COUNT" >> "${SANDBOX}/pane-transitions.log"
    for i in \$(seq 1 \$PANE_COUNT); do echo "%\$i"; done
    ;;
  display-message) echo "" ;;
  *) exit 0 ;;
esac
TMUXEOF
  chmod +x "$STUB_BIN/tmux"
}

# ---------------------------------------------------------------------------
# Helper: _setup_strict_tmux_mock <initial_pane_count>
# strict tmux mock: split-window は pane の実在確認なしに呼ばれると失敗する
# split-window -t <target>.<pane_id> で pane_id が現在の pane 数を超えると exit 1
# これは sync barrier がない場合の "can't find pane: N" エラーを再現する
# ---------------------------------------------------------------------------
_setup_strict_tmux_mock() {
  local initial_panes="${1:-1}"
  local pane_count_file="$SANDBOX/pane-count"
  echo "$initial_panes" > "$pane_count_file"
  touch "$SANDBOX/tmux-calls.log"
  touch "$SANDBOX/pane-transitions.log"

  cat > "$STUB_BIN/tmux" <<TMUXEOF
#!/usr/bin/env bash
echo "tmux \$*" >> "${SANDBOX}/tmux-calls.log"
PANE_COUNT=\$(cat "${pane_count_file}" 2>/dev/null || echo 1)
case "\${1:-}" in
  show-options) echo "0" ;;
  split-window)
    # -t オプションから pane index を抽出して実在確認
    # 例: -t "test-session:0.1" → pane index = 1
    TARGET_ARG=""
    for arg in "\$@"; do
      if [[ "\$TARGET_ARG" == "NEXT" ]]; then
        TARGET_ARG="\$arg"
        break
      fi
      if [[ "\$arg" == "-t" ]]; then
        TARGET_ARG="NEXT"
      fi
    done

    if [[ "\$TARGET_ARG" != "NEXT" && -n "\$TARGET_ARG" ]]; then
      # target の末尾の pane index を抽出（例: "test-session:0.2" → "2"）
      PANE_IDX="\${TARGET_ARG##*.}"
      if [[ "\$PANE_IDX" =~ ^[0-9]+\$ ]] && [[ "\$PANE_IDX" -ge "\$PANE_COUNT" ]]; then
        echo "can't find pane: \${PANE_IDX}" >&2
        exit 1
      fi
    fi

    NEW_COUNT=\$((PANE_COUNT + 1))
    echo "\$NEW_COUNT" > "${pane_count_file}"
    echo "split-pane-count:\$NEW_COUNT" >> "${SANDBOX}/pane-transitions.log"
    ;;
  list-panes)
    echo "list-panes-at:\$PANE_COUNT" >> "${SANDBOX}/pane-transitions.log"
    for i in \$(seq 1 \$PANE_COUNT); do echo "%\$i"; done
    ;;
  display-message) echo "" ;;
  *) exit 0 ;;
esac
TMUXEOF
  chmod +x "$STUB_BIN/tmux"
}

# ---------------------------------------------------------------------------
# Helper: _run_setup_observer_panes_with_mock
# cooperative stateful mock と関数ロードを組み合わせて _setup_observer_panes を実行する
# ---------------------------------------------------------------------------
_run_setup_observer_panes_with_mock() {
  local initial_panes="${1:-1}"
  local observer_window="${2:-observer-test}"

  _setup_tmux_mock "$initial_panes"

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SUPERVISOR_DIR='${SANDBOX}/.supervisor'
export PKILL_LOG='${PKILL_LOG}'
export SCRIPT_DIR='${REPO_ROOT}/skills/su-observer/scripts'
export TWILL_ROOT='${REPO_ROOT}/../../../../..'

# _resolve_window_target スタブ（tmux-resolve.sh の source を回避）
_resolve_window_target() {
  echo 'test-session:0'
  return 0
}

# _setup_observer_panes 関数を spawn-controller.sh から awk で抽出
func_def=\$(awk '
  /^_setup_observer_panes\(\)/ { in_func=1; depth=0 }
  in_func {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == \"{\") depth++
      if (c == \"}\") { depth--; if (depth == 0) { in_func=0; exit } }
    }
  }
' '${SPAWN_CONTROLLER}')

if [[ -z \"\$func_def\" ]]; then
  echo 'RED: _setup_observer_panes 関数が見つからない' >&2
  exit 1
fi

eval \"\$func_def\"
_setup_observer_panes '${observer_window}' 0
"
}

# ---------------------------------------------------------------------------
# Helper: _run_setup_observer_panes_strict
# strict mock を使って _setup_observer_panes を実行する
# pane 実在チェック付き mock のため sync barrier がないと split が失敗する
# ---------------------------------------------------------------------------
_run_setup_observer_panes_strict() {
  local initial_panes="${1:-1}"
  local observer_window="${2:-observer-test}"

  _setup_strict_tmux_mock "$initial_panes"

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SUPERVISOR_DIR='${SANDBOX}/.supervisor'
export PKILL_LOG='${PKILL_LOG}'
export SCRIPT_DIR='${REPO_ROOT}/skills/su-observer/scripts'
export TWILL_ROOT='${REPO_ROOT}/../../../../..'

_resolve_window_target() {
  echo 'test-session:0'
  return 0
}

func_def=\$(awk '
  /^_setup_observer_panes\(\)/ { in_func=1; depth=0 }
  in_func {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == \"{\") depth++
      if (c == \"}\") { depth--; if (depth == 0) { in_func=0; exit } }
    }
  }
' '${SPAWN_CONTROLLER}')

if [[ -z \"\$func_def\" ]]; then
  echo 'RED: _setup_observer_panes 関数が見つからない' >&2
  exit 1
fi

eval \"\$func_def\"
_setup_observer_panes '${observer_window}' 0
"
}

# ===========================================================================
# AC1: 1-pane observer window で spawn-controller.sh 実行 → 4 pane に分割成功 +
#      heartbeat-watcher / budget-monitor / cld-observe-any 起動確認
#
# RED: 現在の実装では split-window 間に sync barrier がないため、
#      "can't find pane: 2" エラーが発生し 4 pane 分割が信頼性なく失敗する。
# PASS 条件（実装後）:
#   - split-window が 3 回呼ばれて 1 pane → 4 pane に遷移する
#   - heartbeat-watcher / budget-monitor / cld-observe-any が起動引数に含まれる
# ===========================================================================

@test "ac1: _setup_observer_panes が strict mock で 4 pane layout を作る（sync barrier なしだと失敗）" {
  # AC: 1-pane observer window で spawn-controller.sh 実行 → 4 pane に分割成功
  # RED: sync barrier 不在のため、Step 2 で pane 1 が存在しない状態の split が失敗する
  #      strict mock は pane 実在チェック付きのため、sync barrier なしでは exit 1 になる
  # PASS 条件（実装後）: sync barrier（split-window 後に list-panes で存在確認）追加で
  #      pane が実際に生成されてから次の split が呼ばれるため正常完了する
  _run_setup_observer_panes_strict 1 "observer-test"

  assert_success

  local split_count
  split_count=$(grep -c "^tmux split-window" "$SANDBOX/tmux-calls.log" 2>/dev/null || echo "0")
  [ "$split_count" -eq 3 ] || {
    echo "FAIL: split-window は 3 回呼ばれるべきだが ${split_count} 回だった"
    cat "$SANDBOX/tmux-calls.log"
    return 1
  }
}

@test "ac1: _setup_observer_panes が heartbeat-watcher.sh を起動引数に含む（strict mock）" {
  # AC: heartbeat-watcher 起動確認
  # RED: sync barrier 不在 → Step 2 の split で "can't find pane: 1" で失敗し
  #      tmux-calls.log に全 watcher コマンドが記録されない
  _run_setup_observer_panes_strict 1 "observer-test"

  assert_success

  run grep "heartbeat-watcher" "$SANDBOX/tmux-calls.log"
  assert_success
}

@test "ac1: _setup_observer_panes が budget-monitor-watcher.sh を起動引数に含む（strict mock）" {
  # AC: budget-monitor 起動確認
  # RED: sync barrier 不在 → Step 2 の split で失敗 → budget-monitor コマンドが記録されない
  _run_setup_observer_panes_strict 1 "observer-test"

  assert_success

  run grep "budget-monitor-watcher" "$SANDBOX/tmux-calls.log"
  assert_success
}

@test "ac1: _setup_observer_panes が cld-observe-any を起動引数に含む（strict mock）" {
  # AC: cld-observe-any 起動確認
  # RED: sync barrier 不在 → Step 2 または Step 3 の split で失敗 → cld-observe-any が記録されない
  _run_setup_observer_panes_strict 1 "observer-test"

  assert_success

  run grep "cld-observe-any" "$SANDBOX/tmux-calls.log"
  assert_success
}

@test "ac1: 実行後に tmux の pane count が 4 になる（strict stateful mock 検証）" {
  # AC: 1-pane → 4 pane への遷移確認
  # RED: sync barrier 不在のため Step 2 で失敗し pane count が 2 止まり
  _run_setup_observer_panes_strict 1 "observer-test"

  assert_success

  local final_pane_count
  final_pane_count=$(cat "$SANDBOX/pane-count" 2>/dev/null || echo "0")
  [ "$final_pane_count" -eq 4 ] || {
    echo "FAIL: 最終 pane 数は 4 であるべきだが ${final_pane_count} だった"
    cat "$SANDBOX/pane-transitions.log"
    return 1
  }
}

# ===========================================================================
# AC2: 既に 4 pane 状態で spawn → 既存 pane 維持 + watcher 再起動
#
# RED: 現在の実装では pane 数確認ロジックがないため、
#      既存 4 pane 状態で呼ぶと split-window がさらに 3 回走り 7 pane になる可能性
# PASS 条件（実装後）:
#   - 既存 4 pane 状態では split-window をスキップ（または pane 数を確認して分岐）
#   - watcher プロセスのみ再起動される
# ===========================================================================

@test "ac2: 既存 4 pane 状態で実行しても pane 数が 7 に増えない（pane 維持）" {
  # AC: 既に 4 pane 状態で spawn → 既存 pane 維持 + watcher 再起動
  # RED: 現在の実装では pane 数チェックがなく、さらに 3 pane 追加して 7 pane になる
  _run_setup_observer_panes_with_mock 4 "observer-test"

  assert_success

  local final_pane_count
  final_pane_count=$(cat "$SANDBOX/pane-count" 2>/dev/null || echo "0")
  [ "$final_pane_count" -le 4 ] || {
    echo "FAIL: 既存 4 pane 状態で pane 数が増えてはならないが ${final_pane_count} になった"
    cat "$SANDBOX/pane-transitions.log"
    return 1
  }
}

@test "ac2: 既存 4 pane 状態で watcher が再起動される（pkill + 再起動確認）" {
  # AC: 既存 pane 維持 + watcher 再起動
  # RED: pkill は実行されるが、watcher 再起動のコマンドは pane 状態次第で異なる
  _run_setup_observer_panes_with_mock 4 "observer-test"

  assert_success

  # orphan cleanup の pkill は呼ばれる（pkill はスタブ済み）
  run cat "$PKILL_LOG"
  assert_success
  assert_output --partial "pkill"
}

# ===========================================================================
# AC3: ipatho-1 host で 2 連続 spawn 検証 (Wave 50 + Wave 51 相当)
#      = _setup_observer_panes を連続 2 回呼ぶと 2 回目も正常完了する
#
# RED: 現在の実装では 1 回目の split が完了していない状態で 2 回目が走ると
#      pane 数が不整合になり失敗する
# PASS 条件（実装後）:
#   - 1 回目完了後に呼ばれる 2 回目も split-window が 3 回正常に実行される
# ===========================================================================

@test "ac3: 2 連続 _setup_observer_panes 呼び出しで 1 回目が正常完了する" {
  # AC: ipatho-1 host で 2 連続 spawn 検証 (Wave 50 + Wave 51 相当)
  # RED: sync barrier 不在のため 1 回目の split が不完全になりうる
  _run_setup_observer_panes_with_mock 1 "observer-test"
  assert_success
}

@test "ac3: 2 連続 _setup_observer_panes 呼び出しで 2 回目も正常完了する" {
  # AC: ipatho-1 host で 2 連続 spawn 検証 (Wave 50 + Wave 51 相当)
  # RED: 1 回目の split 状態が不整合のまま 2 回目が失敗する
  _setup_tmux_mock 1

  # 2 回連続呼び出しをシミュレート
  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SUPERVISOR_DIR='${SANDBOX}/.supervisor'
export PKILL_LOG='${PKILL_LOG}'
export SCRIPT_DIR='${REPO_ROOT}/skills/su-observer/scripts'
export TWILL_ROOT='${REPO_ROOT}/../../../../..'

_resolve_window_target() {
  echo 'test-session:0'
  return 0
}

func_def=\$(awk '
  /^_setup_observer_panes\(\)/ { in_func=1; depth=0 }
  in_func {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == \"{\") depth++
      if (c == \"}\") { depth--; if (depth == 0) { in_func=0; exit } }
    }
  }
' '${SPAWN_CONTROLLER}')

eval \"\$func_def\"

# Wave 50 相当: 1 回目の spawn
_setup_observer_panes 'observer-test' 0 || exit 1
echo '[test] Wave 50 spawn 完了'

# Wave 51 相当: 2 回目の spawn (pkill が再度走り watcher が再起動される)
# pane 数をリセットして 4 pane 状態（1 回目完了後）からシミュレート
_setup_observer_panes 'observer-test' 0 || exit 1
echo '[test] Wave 51 spawn 完了'
"
  assert_success
  assert_output --partial "[test] Wave 50 spawn 完了"
  assert_output --partial "[test] Wave 51 spawn 完了"
}

@test "ac3: 各 spawn が独立した 1-pane window で 3 split を実行する（wave50 + wave51 各々検証）" {
  # AC: ipatho-1 host で 2 連続 spawn 検証 (Wave 50 + Wave 51 相当)
  # Wave 50/51 は異なる window（独立した 1-pane）に spawn するため
  # 各 wave で pane_count_file をリセットして独立した window をシミュレートする
  local pane_count_file="$SANDBOX/pane-count"

  # Wave 50: 1-pane → 4-pane
  _setup_tmux_mock 1
  _run_setup_observer_panes_with_mock 1 "observer-wave50"
  assert_success
  local wave50_splits
  wave50_splits=$(grep -c "^tmux split-window" "$SANDBOX/tmux-calls.log" 2>/dev/null || echo "0")
  [ "$wave50_splits" -eq 3 ] || {
    echo "FAIL: Wave 50 で split-window は 3 回のはずだが ${wave50_splits} 回だった"
    cat "$SANDBOX/tmux-calls.log"
    return 1
  }

  # Wave 51: 独立した 1-pane window をシミュレート（pane_count_file リセット）
  rm -f "$SANDBOX/tmux-calls.log" "$SANDBOX/pane-transitions.log"
  echo "1" > "$pane_count_file"
  _run_setup_observer_panes_with_mock 1 "observer-wave51"
  assert_success
  local wave51_splits
  wave51_splits=$(grep -c "^tmux split-window" "$SANDBOX/tmux-calls.log" 2>/dev/null || echo "0")
  [ "$wave51_splits" -eq 3 ] || {
    echo "FAIL: Wave 51 で split-window は 3 回のはずだが ${wave51_splits} 回だった"
    cat "$SANDBOX/tmux-calls.log"
    return 1
  }
}

# ===========================================================================
# AC4a: bats test で _setup_observer_panes の pane 数遷移を検証
#       content-based RED test:
#       spawn-controller.sh の Step 1 コメント行から Step 2 コメント行の間に
#       list-panes または split-window -P が含まれないことを確認し、
#       不在なら fail（sync barrier 不在の証明）
#
# RED: 現在の実装には sync barrier がないため FAIL する
# PASS 条件（実装後）:
#   - Step 1 と Step 2 の間に list-panes または split-window -P が存在する
# ===========================================================================

@test "ac4a: spawn-controller.sh の Step1 と Step2 の間に sync barrier (list-panes または split-window -P) が存在する" {
  # AC: bats test で _setup_observer_panes の pane 数遷移を検証
  # RED: 現在の実装には sync barrier がないため fail する
  # PASS 条件: Step 1 後に list-panes または split-window -P が追加されると GREEN

  # Step 1 コメント行から Step 2 コメント行の間を抽出
  local between_step1_step2
  between_step1_step2=$(awk '
    /# Step 1:/ { in_section=1; next }
    /# Step 2:/ { if (in_section) { in_section=0; exit } }
    in_section { print }
  ' "$SPAWN_CONTROLLER")

  if [[ -z "$between_step1_step2" ]]; then
    echo "FAIL: Step 1 と Step 2 のコメントが spawn-controller.sh に見つからない"
    false
  fi

  # sync barrier の有無を確認
  if echo "$between_step1_step2" | grep -qE "(list-panes|split-window.*-P|_wait_pane_count)"; then
    # sync barrier が存在する → GREEN（実装完了）
    return 0
  else
    # sync barrier が存在しない → RED（未実装）
    echo "FAIL: Step 1 と Step 2 の間に sync barrier (list-panes または split-window -P) が存在しない"
    echo "--- Step 1 と Step 2 の間の内容 ---"
    echo "$between_step1_step2"
    false
  fi
}

@test "ac4a: spawn-controller.sh の Step2 と Step3 の間にも sync barrier が存在する" {
  # AC: bats test で _setup_observer_panes の pane 数遷移を検証
  # RED: 現在の実装には sync barrier がないため fail する
  # PASS 条件: Step 2 後にも sync barrier が追加されると GREEN

  local between_step2_step3
  between_step2_step3=$(awk '
    /# Step 2:/ { in_section=1; next }
    /# Step 3:/ { if (in_section) { in_section=0; exit } }
    in_section { print }
  ' "$SPAWN_CONTROLLER")

  if [[ -z "$between_step2_step3" ]]; then
    echo "FAIL: Step 2 と Step 3 のコメントが spawn-controller.sh に見つからない"
    false
  fi

  if echo "$between_step2_step3" | grep -qE "(list-panes|split-window.*-P|_wait_pane_count)"; then
    return 0
  else
    echo "FAIL: Step 2 と Step 3 の間に sync barrier (list-panes または split-window -P) が存在しない"
    echo "--- Step 2 と Step 3 の間の内容 ---"
    echo "$between_step2_step3"
    false
  fi
}

# ===========================================================================
# AC4b: stateful tmux mock で split と split の間に list-panes が呼ばれていないなら fail
#       (sync barrier 不在の RED 証明)
#
# RED: 現在の実装では split 間に list-panes が呼ばれていないため fail する
# PASS 条件（実装後）:
#   - split-window (step1) → list-panes → split-window (step2) の順になる
#   - pane-transitions.log に split-pane-count と list-panes-at が交互に記録される
# ===========================================================================

@test "ac4b: split-window (Step1) の直後に list-panes が呼ばれる（sync barrier 検証）" {
  # AC: bats test で _setup_observer_panes の pane 数遷移を検証
  # RED: 現在の実装では split-window 間に list-panes が呼ばれないため fail する
  _run_setup_observer_panes_with_mock 1 "observer-test"

  assert_success

  local transitions
  transitions=$(cat "$SANDBOX/pane-transitions.log" 2>/dev/null || echo "")

  if [[ -z "$transitions" ]]; then
    echo "FAIL: pane-transitions.log が空または存在しない"
    false
  fi

  # split-pane-count:2 (Step1) の直後に list-panes-at が来るべき
  local first_split_line
  local first_split_lineno
  first_split_lineno=$(grep -n "^split-pane-count:2$" "$SANDBOX/pane-transitions.log" | head -1 | cut -d: -f1)

  if [[ -z "$first_split_lineno" ]]; then
    echo "FAIL: Step 1 の split (pane-count=2) が記録されていない"
    echo "--- pane-transitions.log ---"
    cat "$SANDBOX/pane-transitions.log"
    false
  fi

  local next_event_lineno=$(( first_split_lineno + 1 ))
  local next_event
  next_event=$(sed -n "${next_event_lineno}p" "$SANDBOX/pane-transitions.log")

  if echo "$next_event" | grep -q "^list-panes-at:"; then
    # Step1 直後に list-panes が呼ばれている → sync barrier あり → GREEN
    return 0
  else
    echo "FAIL: Step 1 の split 直後に list-panes が呼ばれていない（sync barrier なし）"
    echo "  期待: list-panes-at:..."
    echo "  実際: ${next_event:-（空/次行なし）}"
    echo "--- pane-transitions.log ---"
    cat "$SANDBOX/pane-transitions.log"
    false
  fi
}

@test "ac4b: split-window (Step2) の直後にも list-panes が呼ばれる（sync barrier 検証）" {
  # AC: bats test で _setup_observer_panes の pane 数遷移を検証
  # RED: 現在の実装では split-window 間に list-panes が呼ばれないため fail する
  _run_setup_observer_panes_with_mock 1 "observer-test"

  assert_success

  local transitions
  transitions=$(cat "$SANDBOX/pane-transitions.log" 2>/dev/null || echo "")

  if [[ -z "$transitions" ]]; then
    echo "FAIL: pane-transitions.log が空または存在しない"
    false
  fi

  # split-pane-count:3 (Step2) の直後に list-panes-at が来るべき
  local step2_split_lineno
  step2_split_lineno=$(grep -n "^split-pane-count:3$" "$SANDBOX/pane-transitions.log" | head -1 | cut -d: -f1)

  if [[ -z "$step2_split_lineno" ]]; then
    echo "FAIL: Step 2 の split (pane-count=3) が記録されていない"
    echo "--- pane-transitions.log ---"
    cat "$SANDBOX/pane-transitions.log"
    false
  fi

  local next_event_lineno=$(( step2_split_lineno + 1 ))
  local next_event
  next_event=$(sed -n "${next_event_lineno}p" "$SANDBOX/pane-transitions.log")

  if echo "$next_event" | grep -q "^list-panes-at:"; then
    return 0
  else
    echo "FAIL: Step 2 の split 直後に list-panes が呼ばれていない（sync barrier なし）"
    echo "  期待: list-panes-at:..."
    echo "  実際: ${next_event:-（空/次行なし）}"
    echo "--- pane-transitions.log ---"
    cat "$SANDBOX/pane-transitions.log"
    false
  fi
}

@test "ac4b: pane-transitions.log に split → list-panes のペアが存在する（順序検証）" {
  # AC: bats test で _setup_observer_panes の pane 数遷移を検証
  # RED: sync barrier なしでは split の直後に別の split が続くため fail する
  _run_setup_observer_panes_with_mock 1 "observer-test"

  assert_success

  local split_count
  split_count=$(grep -c "^split-pane-count:" "$SANDBOX/pane-transitions.log" 2>/dev/null || echo "0")
  local listpanes_count
  listpanes_count=$(grep -c "^list-panes-at:" "$SANDBOX/pane-transitions.log" 2>/dev/null || echo "0")

  # sync barrier がある場合: 3 split + 2 list-panes (Step1後 + Step2後)
  # sync barrier がない場合: 3 split + 0 list-panes
  [ "$listpanes_count" -ge 2 ] || {
    echo "FAIL: split-window と split-window の間に list-panes が呼ばれていない"
    echo "  split 回数: ${split_count}"
    echo "  list-panes 回数: ${listpanes_count} (期待: ≥2)"
    echo "--- pane-transitions.log ---"
    cat "$SANDBOX/pane-transitions.log"
    false
  }
}
