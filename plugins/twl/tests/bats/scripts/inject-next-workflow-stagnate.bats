#!/usr/bin/env bats
# inject-next-workflow-stagnate.bats
# TDD RED フェーズテスト: Issue #1177
# - state file mtime を progress signal として stagnate 検知に組み込む（AC-1〜AC-11）
# - WARN rate limit（AC-5、AC-8）
#
# 実装前（RED）状態で AC-1/2/5/6/7/8/9/16/17 が fail することを意図している。
# 実装完了後（GREEN）は全テストが PASS すること。

export LC_ALL=C.UTF-8

load '../helpers/common'

INJECT_LIB=""

setup() {
  common_setup

  # AC-14: AUTOPILOT_DIR をプロセス固有一時パスに設定（main worktree の .autopilot を汚染しない）
  export AUTOPILOT_DIR="/tmp/test-autopilot-$$"
  mkdir -p "${AUTOPILOT_DIR}/issues"
  mkdir -p "${AUTOPILOT_DIR}/trace"

  INJECT_LIB="$REPO_ROOT/scripts/lib/inject-next-workflow.sh"

  # python3 stub: resolve_next_workflow → exit 1（NOT_READY）を常に返す
  stub_command "python3" "exit 1"

  # tmux stub: send-keys は成功、capture-pane はプロンプト行を返す
  stub_command "tmux" "
case \"\$1\" in
  send-keys) exit 0 ;;
  capture-pane) printf 'user@host:~\$ \\n'; exit 0 ;;
  *) exit 0 ;;
esac
"
}

teardown() {
  rm -rf "${AUTOPILOT_DIR:-/tmp/test-autopilot-NONEXISTENT-$$}"
  common_teardown
}

# ===========================================================================
# AC-2: LAST_STATE_MTIME declare -gA がスクリプトに 2 箇所存在する
# ===========================================================================
# RED 理由: 現実装には LAST_STATE_MTIME の宣言が存在しない

@test "ac2-a: LAST_STATE_MTIME の declare -gA が inject-next-workflow.sh に存在する" {
  # AC: 新規連想配列 LAST_STATE_MTIME を 2 箇所に追加（既存 RESOLVE_FAIL_COUNT と同パターン）
  # RED: 実装前は宣言が存在しないため fail する
  grep -qE 'declare[[:space:]].*LAST_STATE_MTIME' "$INJECT_LIB" \
    || fail "LAST_STATE_MTIME の declare が inject-next-workflow.sh に存在しない（RED: AC-2 未実装）"
}

@test "ac2-b: LAST_STATE_MTIME の declare -gA が 2 箇所に存在する（RESOLVE_FAIL_COUNT と同パターン）" {
  # AC: declare -gA を 2 箇所に追加（二重宣言パターン）
  # RED: 現実装には宣言が 0 箇所
  local count=0
  count=$(grep -cE 'declare[[:space:]].*LAST_STATE_MTIME' "$INJECT_LIB" 2>/dev/null) || true
  [[ "$count" -ge 2 ]] \
    || fail "LAST_STATE_MTIME の declare が ${count} 箇所のみ（2 箇所必要）（RED: AC-2 未実装）"
}

# ===========================================================================
# AC-6: LAST_STAGNATE_WARN_TS declare -gA がスクリプトに 2 箇所存在する
# ===========================================================================
# RED 理由: 現実装には LAST_STAGNATE_WARN_TS の宣言が存在しない

@test "ac6-a: LAST_STAGNATE_WARN_TS の declare -gA が inject-next-workflow.sh に存在する" {
  # AC: 新規連想配列 LAST_STAGNATE_WARN_TS を 2 箇所に追加（AC-1 と同一パターン）
  # RED: 実装前は宣言が存在しないため fail する
  grep -qE 'declare[[:space:]].*LAST_STAGNATE_WARN_TS' "$INJECT_LIB" \
    || fail "LAST_STAGNATE_WARN_TS の declare が inject-next-workflow.sh に存在しない（RED: AC-6 未実装）"
}

@test "ac6-b: LAST_STAGNATE_WARN_TS の declare -gA が 2 箇所に存在する" {
  # RED: 現実装には宣言が 0 箇所
  local count=0
  count=$(grep -cE 'declare[[:space:]].*LAST_STAGNATE_WARN_TS' "$INJECT_LIB" 2>/dev/null) || true
  [[ "$count" -ge 2 ]] \
    || fail "LAST_STAGNATE_WARN_TS の declare が ${count} 箇所のみ（2 箇所必要）（RED: AC-6 未実装）"
}

# ===========================================================================
# AC-5/9: AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC のデフォルト値がスクリプトに存在する
# ===========================================================================
# RED 理由: 現実装には AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC が存在しない

@test "ac5-env-var: AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC がスクリプト内で参照されている" {
  # AC: 新規環境変数 AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC（既定 60s）
  # RED: 実装前は存在しないため fail する
  grep -q 'AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC' "$INJECT_LIB" \
    || fail "AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC が inject-next-workflow.sh に存在しない（RED: AC-5 未実装）"
}

@test "ac9-naming: AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC は AUTOPILOT_*_SEC 命名規則に準拠している" {
  # AC: 環境変数命名は既存 AUTOPILOT_STAGNATE_SEC の規則（AUTOPILOT_*_SEC）に揃える
  # 命名検証: スクリプト内に AUTOPILOT_ prefix かつ _SEC suffix の変数として存在
  grep -qE 'AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC' "$INJECT_LIB" \
    || fail "AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC が AUTOPILOT_*_SEC 規則に沿って存在しない（RED: AC-9 未実装）"
}

# ===========================================================================
# AC-1/3: state file mtime が進んだ場合、RESOLVE_FAIL_COUNT がリセットされる
# ===========================================================================
# RED 理由: 現実装は mtime を参照しないため count が累積し続ける

@test "ac1-mtime-reset: state file mtime 進行で RESOLVE_FAIL_COUNT がリセットされる" {
  # AC: inject-next-workflow.sh stagnate 検知ブロックで mtime チェックを FAIL_COUNT インクリメント前に実施
  # - mtime が進んだ → RESOLVE_FAIL_COUNT リセット（0 → インクリメントで 1）
  # RED: 現実装では mtime を見ないため 2 回目呼び出し後 count=2 になる

  local state_file="${AUTOPILOT_DIR}/issues/issue-999.json"
  local result_file="${SANDBOX}/fail-count.txt"

  echo '{"status":"in_progress","current_step":"test-scaffold"}' > "$state_file"

  # ヘルパースクリプト: inject_next_workflow を 2 回呼び出し、間で mtime を進める
  local helper="${SANDBOX}/run-inject-mtime.sh"
  cat > "$helper" <<HELPER
#!/usr/bin/env bash
export PATH="${STUB_BIN}:\$PATH"
export AUTOPILOT_DIR="${AUTOPILOT_DIR}"
export AUTOPILOT_STAGNATE_SEC=9999
export USE_SESSION_STATE=false

cleanup_worker() { true; }

# shellcheck source=/dev/null
source "${INJECT_LIB}"

# 1 回目: RESOLVE_FAIL_COUNT が 1 になる
inject_next_workflow 999 test-window "_default:999" 2>/dev/null || true

# mtime を進める（新しいタイムスタンプで touch）
sleep 1
touch "${state_file}"

# 2 回目: mtime 進行を検知して RESOLVE_FAIL_COUNT リセット → 1 になるはず（RED: 現実装では 2）
inject_next_workflow 999 test-window "_default:999" 2>/dev/null || true

echo "\${RESOLVE_FAIL_COUNT[_default:999]:-0}" > "${result_file}"
HELPER
  chmod +x "$helper"

  run bash "$helper"

  local count
  count=$(cat "$result_file" 2>/dev/null || echo "ERR")

  # mtime 進行後は RESOLVE_FAIL_COUNT がリセットされ、再インクリメントで 1 になるはず
  # RED: 現実装では 2 になる（リセットなし）
  [[ "$count" -eq 1 ]] \
    || fail "mtime 進行後に RESOLVE_FAIL_COUNT=1 を期待したが ${count} だった（RED: mtime リセット未実装 — AC-1）"
}

# ===========================================================================
# AC-4: state file 不在時は mtime=0 フォールバック、カウントアップ継続（後方互換）
# ===========================================================================
# この AC は現実装でも PASS する（後方互換性の回帰テスト）

@test "ac4-absent-state-file: state file 不在時は RESOLVE_FAIL_COUNT が正常にカウントアップされる" {
  # AC: state file 不在 → stat 失敗 → _current_mtime=0。LAST_STATE_MTIME 初期値 0 のため
  #     current(0) > last(0) が偽 → リセット非発火、現行のカウントアップを維持
  # 後方互換テスト（GREEN before and after impl）

  local result_file="${SANDBOX}/fail-count-absent.txt"

  # state file は作成しない（不在を意図）

  local helper="${SANDBOX}/run-inject-absent.sh"
  cat > "$helper" <<HELPER
#!/usr/bin/env bash
export PATH="${STUB_BIN}:\$PATH"
export AUTOPILOT_DIR="${AUTOPILOT_DIR}"
export AUTOPILOT_STAGNATE_SEC=9999
export USE_SESSION_STATE=false

cleanup_worker() { true; }

# shellcheck source=/dev/null
source "${INJECT_LIB}"

inject_next_workflow 998 test-window "_default:998" 2>/dev/null || true
inject_next_workflow 998 test-window "_default:998" 2>/dev/null || true

echo "\${RESOLVE_FAIL_COUNT[_default:998]:-0}" > "${result_file}"
HELPER
  chmod +x "$helper"

  run bash "$helper"

  local count
  count=$(cat "$result_file" 2>/dev/null || echo "ERR")

  # state file 不在時は reset されず 2 になるはず（後方互換）
  [[ "$count" -eq 2 ]] \
    || fail "state file 不在時は RESOLVE_FAIL_COUNT=2 を期待したが ${count} だった（後方互換テスト — AC-4）"
}

# ===========================================================================
# AC-5/8: WARN は rate limit 内で suppress される
# ===========================================================================
# RED 理由: 現実装は WARN を無制限に emit する

@test "ac5-warn-rate-limit: stagnate WARN は AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC 内で suppress される" {
  # AC: _now - LAST_STAGNATE_WARN_TS[$entry] >= AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC を満たさない場合は
  #     WARN を suppress（trace log は継続記録）
  # RED: 現実装は毎回 WARN を emit するため、2 回呼び出しで 2 つの WARN が出る

  local state_file="${AUTOPILOT_DIR}/issues/issue-997.json"
  local stderr_file="${SANDBOX}/inject-stderr.txt"

  echo '{"status":"in_progress"}' > "$state_file"

  local helper="${SANDBOX}/run-inject-warn.sh"
  cat > "$helper" <<HELPER
#!/usr/bin/env bash
export PATH="${STUB_BIN}:\$PATH"
export AUTOPILOT_DIR="${AUTOPILOT_DIR}"
# stagnate 検知を即座に発火（elapsed >= 0 で常に true）
export AUTOPILOT_STAGNATE_SEC=0
# WARN rate limit を非常に長く設定（rate limit が機能するなら suppress される）
export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC=3600
export USE_SESSION_STATE=false

cleanup_worker() { true; }

# shellcheck source=/dev/null
source "${INJECT_LIB}"

# 1 回目: WARN が emit される
inject_next_workflow 997 test-window "_default:997" 2>>"${stderr_file}" || true

# 2 回目: WARN_INTERVAL_SEC 内なので suppress されるはず（RED: 現実装では emit される）
inject_next_workflow 997 test-window "_default:997" 2>>"${stderr_file}" || true
HELPER
  chmod +x "$helper"

  run bash "$helper"

  local warn_count=0
  warn_count=$(grep -c '\[orchestrator\] WARN:.*stagnate' "${stderr_file}" 2>/dev/null) || true

  # 最初の WARN は必ず emit される（rate limit 起点の確立）
  [[ "$warn_count" -ge 1 ]] \
    || fail "stagnate WARN が 1 回も emit されなかった（最初の WARN は必ず発出される必要がある — AC-5 scenario B）"

  # rate limit が機能すれば 2 回目は suppress → warn_count=1
  # RED: 現実装では warn_count=2（suppress なし）
  [[ "$warn_count" -le 1 ]] \
    || fail "stagnate WARN が ${warn_count} 回 emit された（rate limit で 1 回以下を期待）（RED: AC-5 未実装）"
}

# ===========================================================================
# AC-8: WARN suppress 時も trace log には stagnate エントリが記録される
# ===========================================================================
# RED 理由: 現実装には rate limit 自体がないため、suppress 状態の trace log 記録ロジックも存在しない

@test "ac8-trace-log-on-suppress: WARN suppress 時も trace log はより多く記録される（trace > warn）" {
  # AC: WARN を suppress する場合も trace log（stagnate エントリ）は連続記録を維持
  # RED: 実装前は WARN も trace も 2 件記録される（rate limit なし）→ trace(2) > warn(2) が偽 → FAIL
  # GREEN: 実装後は WARN=1（2 回目 suppress）、trace=2 → trace(2) > warn(1) が真 → PASS

  local state_file="${AUTOPILOT_DIR}/issues/issue-996.json"
  local trace_dir="${AUTOPILOT_DIR}/trace"
  local stderr_file="${SANDBOX}/inject-stderr-trace.txt"

  echo '{"status":"in_progress"}' > "$state_file"

  local helper="${SANDBOX}/run-inject-trace.sh"
  cat > "$helper" <<HELPER
#!/usr/bin/env bash
export PATH="${STUB_BIN}:\$PATH"
export AUTOPILOT_DIR="${AUTOPILOT_DIR}"
export AUTOPILOT_STAGNATE_SEC=0
export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC=3600
export USE_SESSION_STATE=false

cleanup_worker() { true; }

# shellcheck source=/dev/null
source "${INJECT_LIB}"

inject_next_workflow 996 test-window "_default:996" 2>>"${stderr_file}" || true
inject_next_workflow 996 test-window "_default:996" 2>>"${stderr_file}" || true
HELPER
  chmod +x "$helper"

  run bash "$helper"

  # trace ログファイルを検索
  local trace_file
  trace_file=$(find "${trace_dir}" -name "inject-*.log" 2>/dev/null | head -1)

  [[ -n "$trace_file" ]] \
    || fail "trace ログファイルが存在しない（AUTOPILOT_DIR=${AUTOPILOT_DIR}）"

  local stagnate_trace_count=0
  stagnate_trace_count=$(grep -c 'result=stagnate' "${trace_file}" 2>/dev/null) || true

  local warn_count=0
  warn_count=$(grep -c '\[orchestrator\] WARN:.*stagnate' "${stderr_file}" 2>/dev/null) || true

  # suppress 後: trace > warn（trace は 2 件、warn は 1 件 suppress された）
  # RED: 実装前は trace=2, warn=2 → 2 > 2 = false → FAIL
  # GREEN: 実装後は trace=2, warn=1 → 2 > 1 = true → PASS
  [[ "$stagnate_trace_count" -gt "$warn_count" ]] \
    || fail "trace log(${stagnate_trace_count} 件) > WARN(${warn_count} 件) を期待（suppress 時は WARN < trace — RED: AC-8 未実装）"
}

# ===========================================================================
# AC-7: LAST_STAGNATE_WARN_TS は mtime リセット時にリセットされる
# ===========================================================================
# RED 理由: LAST_STAGNATE_WARN_TS 自体が未実装

@test "ac7-warn-ts-inject-reset: inject 成功時に LAST_STAGNATE_WARN_TS がリセットされる（mtime リセット時はリセットしない）" {
  # AC-7: LAST_STAGNATE_WARN_TS のリセット条件:
  #   - inject 成功時（既存 L57-58 の RESOLVE_FAIL_COUNT[$entry]=0 と同箇所）: LAST_STAGNATE_WARN_TS[$entry]="" でリセット
  #   - AC-1 の mtime 変化リセット時: リセットしない（rate limit を mtime fluctuation で消費しないため）
  # RED: 実装前は LAST_STAGNATE_WARN_TS 自体が存在しないため fail

  grep -q 'LAST_STAGNATE_WARN_TS' "$INJECT_LIB" \
    || fail "LAST_STAGNATE_WARN_TS がスクリプトに存在しない（RED: AC-7 未実装）"

  # inject 成功時のリセット処理が存在することを確認（空文字 or 0 への代入）
  grep -qE 'LAST_STAGNATE_WARN_TS\[.*\]=(0|""|"0"|"")' "$INJECT_LIB" \
    || fail "LAST_STAGNATE_WARN_TS の inject-success リセット処理がスクリプトに存在しない（RED: AC-7 リセット条件未実装）"
}

# ===========================================================================
# AC-10: 既存の exit code 振り分けロジック（L31-37）が変更されていない
# ===========================================================================
# 後方互換テスト（GREEN before and after impl）

@test "ac10-exit-code-unchanged: exit==1 → RESOLVE_NOT_READY ロジックが維持されている" {
  # AC: 既存ロジック L31-37（exit==1 → RESOLVE_NOT_READY、exit!=0&&!=1 → RESOLVE_ERROR）は変更しない
  # mtime 判定は exit code に関わらず先に実施（独立）

  # RESOLVE_NOT_READY の処理（exit==1 時の trace ログ記録）が存在することを確認
  grep -q 'RESOLVE_NOT_READY\|category=RESOLVE_NOT_READY' "$INJECT_LIB" \
    || fail "RESOLVE_NOT_READY カテゴリが inject-next-workflow.sh に存在しない（AC-10 回帰テスト失敗）"
}

@test "ac10-exit-code-unchanged: exit!=0&&!=1 → RESOLVE_ERROR ロジックが維持されている" {
  grep -q 'RESOLVE_ERROR\|category=RESOLVE_ERROR' "$INJECT_LIB" \
    || fail "RESOLVE_ERROR カテゴリが inject-next-workflow.sh に存在しない（AC-10 回帰テスト失敗）"
}

# ===========================================================================
# AC-16: pitfalls-catalog.md §4.10 に orchestrator-side mtime AND 判定の例が追記される
# ===========================================================================
# RED 理由: 現 §4.10 には mtime AND 判定の記述が存在しない

@test "ac16-pitfalls-catalog: pitfalls-catalog §4.10 に mtime AND 判定の適用例が存在する" {
  # AC: su-observer/refs/pitfalls-catalog.md §4.10 に orchestrator-side mtime AND 判定を追記
  local catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  # orchestrator-side の mtime AND 判定の「適用例」として inject-next-workflow.sh への追記を確認
  # 既存の mtime 言及（observer 関連）とは区別するため、orchestrator-side と明記された記述を確認
  # RED: 実装前は orchestrator-side mtime AND 判定の適用例が存在しないため fail する
  grep -qiE 'orchestrator.*mtime|mtime.*orchestrator|inject-next-workflow.*mtime|mtime.*inject-next-workflow' "$catalog" \
    || fail "pitfalls-catalog.md §4.10 に orchestrator-side mtime AND 判定の適用例が存在しない（RED: AC-16 未追記）"
}

@test "ac16-pitfalls-catalog: pitfalls-catalog §4.10 に inject-next-workflow.sh への言及がある" {
  local catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] || skip "pitfalls-catalog.md が存在しない"

  # inject-next-workflow.sh への具体的な参照を確認
  # RED: 実装前は存在しない
  grep -q 'inject-next-workflow' "$catalog" \
    || fail "pitfalls-catalog.md に inject-next-workflow.sh への参照が存在しない（RED: AC-16 未追記）"
}

# ===========================================================================
# AC-17: autopilot.md に AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC が追加される
# ===========================================================================
# RED 理由: 現 autopilot.md には AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC が存在しない

@test "ac17-autopilot-doc: AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC が autopilot.md に記載されている" {
  # AC: plugins/twl/architecture/domain/contexts/autopilot.md の env-var セクション（L289-295 周辺）に追加
  local autopilot_doc="$REPO_ROOT/architecture/domain/contexts/autopilot.md"

  [[ -f "$autopilot_doc" ]] \
    || fail "autopilot.md が存在しない: $autopilot_doc"

  # RED: 実装前は存在しないため fail する
  grep -q 'AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC' "$autopilot_doc" \
    || fail "autopilot.md に AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC が存在しない（RED: AC-17 未追記）"
}

# ===========================================================================
# AC-15: 既存テストへの干渉なし確認（deps-integrity）
# ===========================================================================

@test "ac15-no-interference: twl check --deps-integrity が PASS する" {
  # AC: 既存テスト干渉なし確認
  # deps-integrity は chain.py, chain-steps.sh, deps.yaml の整合性を確認する
  # plugins/twl ディレクトリ内で実行が必要
  local twl_bin
  twl_bin=$(command -v twl 2>/dev/null || echo "")

  if [[ -z "$twl_bin" ]]; then
    skip "twl コマンドが見つからない（CI 環境では skip）"
  fi

  # deps.yaml が REPO_ROOT にあることを確認（REPO_ROOT = plugins/twl）
  if [[ ! -f "$REPO_ROOT/deps.yaml" ]]; then
    skip "deps.yaml が REPO_ROOT に存在しない（REPO_ROOT=$REPO_ROOT）"
  fi

  # PATH を一時的に元に戻して実行（STUB_BIN の python3 stub が干渉しないよう）
  run bash -c "export PATH='$_ORIGINAL_PATH'; cd '$REPO_ROOT' && twl check --deps-integrity"
  assert_success
}
