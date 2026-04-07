#!/usr/bin/env bats
# orchestrator-merge-gate-exit-codes.bats
# Issue #137: run_merge_gate の exit code 0/1/2 ハンドリングを検証する
#
# run_merge_gate() は set -euo pipefail 配下の大規模スクリプト
# (autopilot-orchestrator.sh) に埋め込まれているため、関数定義のみを
# awk で抽出して評価し、python3 と state モジュールをスタブ化して動作検証する。

load '../helpers/common'

setup() {
  common_setup

  ORCHESTRATOR_SH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"
  [[ -f "$ORCHESTRATOR_SH" ]] || skip "autopilot-orchestrator.sh not found"

  # run_merge_gate 関数定義のみを抽出
  FUNC_FILE="$SANDBOX/run_merge_gate.sh"
  awk '
    /^run_merge_gate\(\) \{/ {inside=1}
    inside {print}
    inside && /^}/ {inside=0; exit}
  ' "$ORCHESTRATOR_SH" > "$FUNC_FILE"

  [[ -s "$FUNC_FILE" ]] || fail "run_merge_gate extraction failed"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: python3 スタブをインストール
#   第1引数: merge-gate 呼び出し時の exit code
# state read はダミー値を返す
# ---------------------------------------------------------------------------
install_python3_stub() {
  local rc="$1"
  cat >"$STUB_BIN/python3" <<EOF
#!/usr/bin/env bash
# mergegate 呼び出しは \${rc} を返す
# state read は --field 引数に応じた値を返す
case "\$*" in
  *"twl.autopilot.mergegate"*)
    exit ${rc}
    ;;
  *"twl.autopilot.state"*)
    # --field の次トークンを抽出
    field=""
    prev=""
    for arg in "\$@"; do
      [[ "\$prev" == "--field" ]] && field="\$arg" && break
      prev="\$arg"
    done
    case "\$field" in
      pr) echo "101" ;;
      branch) echo "feat/42-test" ;;
      *) echo "" ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$STUB_BIN/python3"
}

# ---------------------------------------------------------------------------
# ラッパースクリプト: run_merge_gate をロード・呼び出し
# ---------------------------------------------------------------------------
run_harness() {
  bash -c '
    set +e
    source "$1"
    run_merge_gate "_default:42"
    echo "__RC__=$?"
  ' _ "$FUNC_FILE" 2>&1
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "run_merge_gate: exit 0 → 'merge 成功' メッセージ" {
  install_python3_stub 0
  run run_harness
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge 成功"* ]]
  [[ "$output" == *"__RC__=0"* ]]
}

@test "run_merge_gate: exit 2 → 'Issue close 失敗で escalate' メッセージ + rc=2" {
  install_python3_stub 2
  run run_harness
  [[ "$output" == *"Issue close 失敗で escalate"* ]]
  [[ "$output" == *"status=failed"* ]]
  [[ "$output" == *"__RC__=2"* ]]
  # Done 遷移ではないため、merge 成功メッセージは出ない
  [[ "$output" != *"merge 成功"* ]]
}

@test "run_merge_gate: exit 1 → 'merge 失敗' メッセージ + rc=1" {
  install_python3_stub 1
  run run_harness
  [[ "$output" == *"merge 失敗"* ]]
  [[ "$output" == *"exit=1"* ]]
  [[ "$output" == *"__RC__=1"* ]]
}
