#!/usr/bin/env bats
# atomic-rmw.bats
# Requirement: session.json への 4 RMW 経路が flock(8) で保護され、parallel 実行で lost-update が発生しない
# Issue: #974 — Pilot 内 RMW race condition (session.json bash jq+mv + Python inline 経路の atomic 化)
# Coverage: --type=unit --coverage=race-condition
#
# 検証する仕様:
#   1. 5 subprocess × 50 反復の parallel RMW でカウント整合性が保たれる (theoretical worst-case)
#   2. FORCE_RACE_WINDOW=1 で sleep 0.01 を注入すると unprotected jq+mv が lost-update を起こす (RED)
#   3. session-atomic-write.sh (flock 保護) では lost-update が発生しない (GREEN)
#   4. self_improve_issues 要素型の schema drift 確認 (canonical: number[], impl: {url,title}[])
#
# 注意: このテストは "theoretical worst-case" を検証する。現実の単一 Pilot 逐次実行では
#       autopilot-phase-postprocess.md:84 の逐次 MUST により実 race は発生しない。
#       su-observer の externalize-state 非同期呼出し (ADR-014) や将来的な並列 Phase 処理導入時の
#       regression guard が目的。bats fixture は bash 直接実行 (jq+mv) で race を再現;
#       state write --type session 経路では _check_rbac (state.py:418-420) の Worker 制約により
#       bash 経路の race 再現が不可のため直接実行に統一。

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# Constants
# proc 割り当て: proc%3==0 → retro append (proc0,3), proc%3==1 → self_improve (proc1,4), proc%3==2 → ext (proc2)
# Expected: retro=100 (proc0+3), self_improve=100 (proc1+4), externalize=50 (proc2)
# ---------------------------------------------------------------------------

NUM_PROCS=5
NUM_ITER=50
EXPECTED_RETRO=100
EXPECTED_SELF=100
EXPECTED_EXT=50

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # REPO_ROOT = plugins/twl/
  local plugin_root
  plugin_root="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  HELPER_SCRIPT="${plugin_root}/scripts/session-atomic-write.sh"
  export HELPER_SCRIPT

  SESSION_FILE="$SANDBOX/.autopilot/session.json"
  export SESSION_FILE

  # subprocess 用スクリプトを SANDBOX に生成
  UNPROTECTED_WORKER="$SANDBOX/unprotected_worker.sh"
  PROTECTED_WORKER="$SANDBOX/protected_worker.sh"

  cat > "$UNPROTECTED_WORKER" <<'WORKER_EOF'
#!/usr/bin/env bash
# Unprotected RMW worker — jq+mv 直接実行 (race 再現用)
set -uo pipefail
proc_id="$1"
session_file="$2"
num_iter="${3:-50}"
force_race="${FORCE_RACE_WINDOW:-0}"

for ((i=0; i<num_iter; i++)); do
  case $(( proc_id % 3 )) in
    0) # retrospective append
      tmp=$(mktemp)
      jq --argjson p "$i" '.retrospectives += [{"phase": $p, "results": "test"}]' \
        "$session_file" > "$tmp"
      [[ "$force_race" == "1" ]] && sleep 0.01
      mv "$tmp" "$session_file"
      ;;
    1) # self_improve_issues append
      tmp=$(mktemp)
      jq --arg url "https://example.com/$proc_id/$i" --arg title "pattern-$i" \
        '.self_improve_issues += [{"url": $url, "title": $title}]' \
        "$session_file" > "$tmp"
      [[ "$force_race" == "1" ]] && sleep 0.01
      mv "$tmp" "$session_file"
      ;;
    2) # externalization_log append
      tmp=$(mktemp)
      jq --arg ts "2026-04-25T00:00:00Z" --arg trig "test" \
         --arg p "out/$proc_id/$i" \
        '.externalization_log += [{"externalized_at": $ts, "trigger": $trig, "output_path": $p, "new_pitfall_hashes": [], "pitfall_declaration": ""}]' \
        "$session_file" > "$tmp"
      [[ "$force_race" == "1" ]] && sleep 0.01
      mv "$tmp" "$session_file"
      ;;
  esac
done
WORKER_EOF
  chmod +x "$UNPROTECTED_WORKER"

  cat > "$PROTECTED_WORKER" <<WORKER_EOF
#!/usr/bin/env bash
# Protected RMW worker — session-atomic-write.sh (flock) 使用
set -uo pipefail
proc_id="\$1"
session_file="\$2"
helper="${HELPER_SCRIPT}"
num_iter="\${3:-50}"

for ((i=0; i<num_iter; i++)); do
  case \$(( proc_id % 3 )) in
    0)
      bash "\$helper" "\$session_file" \
        --argjson p "\$i" \
        '.retrospectives += [{"phase": \$p, "results": "test"}]'
      ;;
    1)
      bash "\$helper" "\$session_file" \
        --arg url "https://example.com/\$proc_id/\$i" --arg title "pattern-\$i" \
        '.self_improve_issues += [{"url": \$url, "title": \$title}]'
      ;;
    2)
      bash "\$helper" "\$session_file" \
        --arg ts "2026-04-25T00:00:00Z" --arg trig "test" \
        --arg p "out/\$proc_id/\$i" \
        '.externalization_log += [{"externalized_at": \$ts, "trigger": \$trig, "output_path": \$p, "new_pitfall_hashes": [], "pitfall_declaration": ""}]'
      ;;
  esac
done
WORKER_EOF
  chmod +x "$PROTECTED_WORKER"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: session.json 初期化
# ---------------------------------------------------------------------------

init_session_file() {
  printf '{"session_id":"testrmw","retrospectives":[],"self_improve_issues":[],"externalization_log":[]}\n' \
    > "$SESSION_FILE"
}

# ---------------------------------------------------------------------------
# Test 1: FORCE_RACE_WINDOW=1 で unprotected jq+mv が lost-update を起こす (RED)
#
# AC2 Option A 対応: FORCE_RACE_WINDOW=1 で sleep 0.01 注入 → race window 累積拡大
# "修正前 FAIL" の証跡として PR description に bats 出力を貼付けること
# ---------------------------------------------------------------------------

@test "RED: FORCE_RACE_WINDOW=1 で unprotected jq+mv が lost-update を起こす" {
  init_session_file
  local expected=$(( EXPECTED_RETRO + EXPECTED_SELF + EXPECTED_EXT ))

  # FORCE_RACE_WINDOW=1 を子プロセスに継承させる
  export FORCE_RACE_WINDOW=1

  # setsid で独立プロセスグループから起動 (flock 採用時の同一 PID グループ lock 再取得問題を回避)
  for proc_id in $(seq 0 $((NUM_PROCS - 1))); do
    setsid bash "$UNPROTECTED_WORKER" "$proc_id" "$SESSION_FILE" "$NUM_ITER" &
  done
  wait
  unset FORCE_RACE_WINDOW

  local retro self_improve ext total
  retro=$(jq '.retrospectives | length' "$SESSION_FILE")
  self_improve=$(jq '.self_improve_issues | length' "$SESSION_FILE")
  ext=$(jq '.externalization_log | length' "$SESSION_FILE")
  total=$((retro + self_improve + ext))

  # lost-update が発生 → total < expected
  # FORCE_RACE_WINDOW=1 + sleep 0.01 で race window を累積拡大しているため高確率で FAIL
  if [[ "$total" -eq "$expected" ]]; then
    skip "race が再現しなかった (環境依存。高負荷下や低速ストレージで再実行推奨)"
  fi
  [ "$total" -lt "$expected" ]
}

# ---------------------------------------------------------------------------
# Test 2: PROTECTED parallel RMW で lost-update が発生しない (GREEN)
#
# "修正後 PASS" の主テスト。
# _check_rbac Worker 制約 (state.py:418-420) により state write --type session 経路では
# bash 経路の race 再現不可 → bash 直接実行で検証 (AC6 docstring 反映)。
# setsid で独立プロセスグループ起動 (flock 同一 PID グループ問題回避)。
# ---------------------------------------------------------------------------

@test "GREEN: session-atomic-write.sh (flock) で parallel 5×50 RMW の lost-update が発生しない" {
  # 現実の単一 Pilot 逐次実行 (autopilot-phase-postprocess.md:84 の逐次 MUST) では race は発生しない。
  # このテストは su-observer 非同期呼出し (ADR-014) や将来の並列 Phase 処理導入時の regression guard。
  init_session_file

  for proc_id in $(seq 0 $((NUM_PROCS - 1))); do
    setsid bash "$PROTECTED_WORKER" "$proc_id" "$SESSION_FILE" "$NUM_ITER" &
  done
  wait

  local retro self_improve ext
  retro=$(jq '.retrospectives | length' "$SESSION_FILE")
  self_improve=$(jq '.self_improve_issues | length' "$SESSION_FILE")
  ext=$(jq '.externalization_log | length' "$SESSION_FILE")

  assert_equal "$retro"        "$EXPECTED_RETRO"
  assert_equal "$self_improve" "$EXPECTED_SELF"
  assert_equal "$ext"          "$EXPECTED_EXT"
}

# ---------------------------------------------------------------------------
# Test 3: session.json が不在の場合 helper は exit 0 でスキップする
# ---------------------------------------------------------------------------

@test "session-atomic-write.sh はファイル不在を exit 0 でスキップする" {
  run bash "$HELPER_SCRIPT" "/nonexistent/path/session.json" '.foo = 1'
  assert_success
  assert_output --partial "スキップ"
}

# ---------------------------------------------------------------------------
# Test 3b: SESSION_FILE がシンボリックリンクの場合 exit 1 で中断する (security)
# ---------------------------------------------------------------------------

@test "session-atomic-write.sh は SESSION_FILE がシンボリックリンクなら exit 1 で中断する" {
  init_session_file
  local link_file="$SANDBOX/.autopilot/session_link.json"
  ln -s "$SESSION_FILE" "$link_file"
  run bash "$HELPER_SCRIPT" "$link_file" '.foo = 1'
  assert_failure
  assert_output --partial "シンボリックリンク"
}

# ---------------------------------------------------------------------------
# Test 4 (AC1 schema check): self_improve_issues 要素型の schema drift 確認
#
# canonical schema (autopilot.md): self_improve_issues は number[]
# 実装 (autopilot-patterns.md): {url, title}[] オブジェクト配列
# schema drift は B-3 (別 Issue) で根本修正予定。本テストは drift 存在の記録。
# B-3 マージ後に skip を外し number 型 assert をアクティブ化する。
# ---------------------------------------------------------------------------

@test "SCHEMA [B-3 実装後アクティブ化]: self_improve_issues 要素型が canonical number[] と整合する" {
  skip "schema drift (canonical: number[], impl: {url,title}[]) は B-3 で修正予定 — #974 AC1 型確認記録"
  # B-3 実装後に有効化:
  # init_session_file
  # jq '.self_improve_issues += [42]' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
  #   && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  # local elem_type
  # elem_type=$(jq -r '.self_improve_issues[0] | type' "$SESSION_FILE")
  # assert_equal "$elem_type" "number"
}
