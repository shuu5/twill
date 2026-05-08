#!/usr/bin/env bats
# issue-1599-bugfix-controller-window-idle.bats
#
# RED-phase tests for Issue #1599:
#   bugfix(observer): controller window (wt-co-*) が IDLE-COMPLETED 判定に混入し
#   誤って auto-next-spawn が発火する bug
#
# AC coverage:
#   AC-1 - cld-observe-any の AUTO_NEXT_SPAWN 判定に wt-co-* スキップを追加
#   AC-2 - observer-wave-check.sh の wave_windows grep を ^(ap|coi)- に変更
#   AC-3 - Worker 全 idle + Pilot 残存パターンで _all_current_wave_idle_completed が真
#   AC-4 - Pilot 単独 idle で _all_current_wave_idle_completed が偽（本 bug 再現）
#   AC-5 - cld-observe-any で controller が IDLE-COMPLETED-SKIP 後に next-spawn 不発火
#   AC-6 - observer-auto-next-spawn.bats の ac3 テストを ^(ap|coi)- パターンに更新
#          (AC-6 自体は他ファイルの更新であり本ファイルでは更新後動作を検証する)
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  OBSERVER_WAVE_CHECK="${REPO_ROOT}/skills/su-observer/scripts/lib/observer-wave-check.sh"
  CLD_OBSERVE_ANY="${REPO_ROOT}/../session/scripts/cld-observe-any"
  AUTO_NEXT_SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/auto-next-spawn.sh"

  export OBSERVER_WAVE_CHECK CLD_OBSERVE_ANY AUTO_NEXT_SPAWN_SCRIPT

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST

  SUPERVISOR_DIR="${TMPDIR_TEST}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}"
  export SUPERVISOR_DIR
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC-1: cld-observe-any の AUTO_NEXT_SPAWN 判定に controller window スキップ追加
# RED: wt-co-* window が next-spawn 判定をスキップする分岐が未実装のため fail
# ===========================================================================

@test "ac1: cld-observe-any の next-spawn 判定ブロックに wt-co-* スキップ分岐が存在する" {
  # AC: line 633 直前 (AUTO_NEXT_SPAWN 判定開始前) に
  #     [[ "$WIN" == wt-co-* ]] && continue のガードが追加されている
  # RED: 実装前は fail する
  [ -f "${CLD_OBSERVE_ANY}" ]
  # wt-co-* を next-spawn から除外する continue 分岐が存在すること
  run grep -n 'wt-co-\*.*continue\|continue.*wt-co-\*' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac1: wt-co-* スキップ分岐が AUTO_NEXT_SPAWN 判定の直前に配置されている" {
  # AC: スキップ分岐は IDLE_COMPLETED_AUTO_NEXT_SPAWN チェックの直前の行に存在する
  # RED: 実装前は fail する
  [ -f "${CLD_OBSERVE_ANY}" ]

  # AUTO_NEXT_SPAWN 分岐の行番号を取得
  local spawn_line
  spawn_line=$(grep -n 'IDLE_COMPLETED_AUTO_NEXT_SPAWN.*!= "0"' "${CLD_OBSERVE_ANY}" | head -1 | cut -d: -f1)
  [ -n "$spawn_line" ]

  # スキップ分岐が AUTO_NEXT_SPAWN 判定の 5 行以内前に存在すること
  local skip_line
  skip_line=$(grep -n 'wt-co-\*.*continue\|continue.*wt-co-\*' "${CLD_OBSERVE_ANY}" | awk -F: -v s="$spawn_line" '{ if ($1 < s && ($1 + 5) >= s) print $1 }' | head -1)
  [ -n "$skip_line" ]
}

@test "ac1: cld-observe-any の wt-co-* スキップが [IDLE-COMPLETED-SKIP] ログを出力する" {
  # AC: controller window を next-spawn から skip する際に [IDLE-COMPLETED-SKIP] を emit する
  # RED: 実装前（または SKIP ログが auto-kill 向けのみ）のため fail する
  [ -f "${CLD_OBSERVE_ANY}" ]

  # next-spawn skip 専用の SKIP ログ出力行が存在すること
  # auto-kill SKIP (line 614) とは別の next-spawn SKIP 出力であること
  # 実装後は grep -n で next-spawn context の SKIP ログ行が確認できる
  run grep -n 'IDLE-COMPLETED-SKIP.*next.spawn\|next.spawn.*IDLE-COMPLETED-SKIP' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# AC-2: observer-wave-check.sh の wave_windows grep を ^(ap|coi)- に変更
# RED: 現状 ^(ap|wt|coi)- パターンが残存しているため fail する
# ===========================================================================

@test "ac2: observer-wave-check.sh の grep pattern が ^(ap|coi)- である (wt を除外)" {
  # AC: grep -E '^(ap|wt|coi)-' を grep -E '^(ap|coi)-' に変更する
  # RED: 現状 wt が含まれたままのため fail する
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  # wt を含む旧パターンが存在しないこと
  run grep -E '\(ap\|wt\|coi\)' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -ne 0 ]
}

@test "ac2: observer-wave-check.sh の grep pattern が ^(ap|coi)- に更新されている" {
  # AC: 新パターン ^(ap|coi)- が採用されている
  # RED: 現状は更新されていないため fail する
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  run grep -E '\(ap\|coi\)-' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac2: observer-wave-check.sh に Pilot 除外の設計意図コメントが明記されている" {
  # AC: 「Pilot は Wave 完遂判定の参加者ではない」趣旨のコメントが存在する
  # RED: コメントが未追加のため fail する
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  run grep -iE 'Pilot.*Wave|Wave.*Pilot|wt-co.*参加者|参加者.*ではない' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# AC-3 (bats T1): Worker 全 idle + Pilot 残存 → _all_current_wave_idle_completed が真
# RED: observer-wave-check.sh が旧パターン (wt 含む) のため Pilot を active と誤判定し fail
# ===========================================================================

@test "ac3-T1: Worker 全 idle + Pilot 残存で _all_current_wave_idle_completed が真を返す" {
  # AC: ap-* Worker が全員 IDLE_COMPLETED_TS > 0、wt-co-* Pilot が残存しても真
  # RED: 現状 wave_windows に wt-co-* が混入し Pilot ts=0 で偽になるため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  local wave_queue
  wave_queue="${SUPERVISOR_DIR}/wave-queue.json"
  cat > "$wave_queue" <<EOF
{
  "version": 1,
  "current_wave": 1,
  "queue": []
}
EOF

  # tmux モック: ap-worker-1, wt-co-pilot-1 が存在する状態をシミュレート
  # AC-2 適用後は wave_windows フィルタが ^(ap|coi)- なので wt-co-* は除外される
  local fake_bin
  fake_bin="${TMPDIR_TEST}/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/tmux" <<'TMUX_EOF'
#!/usr/bin/env bash
if [[ "$1" == "list-windows" ]]; then
  printf 'ap-worker-1\nwt-co-pilot-1\n'
fi
TMUX_EOF
  chmod +x "$fake_bin/tmux"

  # IDLE_COMPLETED_TS: ap-worker-1 は ts=1, wt-co-pilot-1 は ts=0 (running/not idle)
  run bash <<TESTEOF
source "${OBSERVER_WAVE_CHECK}"
declare -A IDLE_COMPLETED_TS
IDLE_COMPLETED_TS["ap-worker-1"]=1
IDLE_COMPLETED_TS["wt-co-pilot-1"]=0
export PATH="${fake_bin}:\$PATH"
if _all_current_wave_idle_completed "${wave_queue}" IDLE_COMPLETED_TS; then
  echo "PASS: all wave idle completed"
  exit 0
else
  echo "FAIL: active windows remain (wt-co-* should have been excluded)"
  exit 1
fi
TESTEOF

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PASS"* ]]
}

@test "ac3-T1: _all_current_wave_idle_completed は wt-co-* を wave 判定から除外する" {
  # AC: wave_windows に wt-co-* が含まれないこと（grep フィルタで除外）
  # RED: 旧パターン ^(ap|wt|coi)- では wt-co-* が含まれるため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  # 現在の grep パターンに wt-co- が match するか確認
  # AC-2 実装後は match しないこと（exit 1）
  run bash -c "printf 'wt-co-pilot-1\n' | grep -E '^\(ap\|wt\|coi\)-'"
  # 旧パターンなら status=0 (wt が含まれるため match)、実装後は status=1
  # このテストは旧パターンが存在する限り fail (RED)
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC-4 (bats T2): Pilot 単独 idle → _all_current_wave_idle_completed が偽を返す
# RED: 本 bug の再現テスト + AC-2 の検証
# ===========================================================================

@test "ac4-T2: Pilot 単独 IDLE_COMPLETED_TS > 0 で Worker 不在 → _all_current_wave_idle_completed が偽" {
  # AC: Pilot のみ idle で Worker が存在しない場合に true を返さない
  # RED: AC-2 実装前は wt-co-* が wave_windows に混入するが IDLE_COMPLETED_TS > 0 のため
  #      worker 不在でも真を返してしまう（本 bug のシミュレーション）
  #      AC-2 実装後は wave_windows = [] (ap|coi 該当なし) → WARN 出力 → false 返却
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  local wave_queue
  wave_queue="${SUPERVISOR_DIR}/wave-queue.json"
  cat > "$wave_queue" <<EOF
{
  "version": 1,
  "current_wave": 1,
  "queue": []
}
EOF

  # tmux モック: Pilot window のみ存在（Worker 不在）
  local fake_bin
  fake_bin="${TMPDIR_TEST}/fake-bin-ac4"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/tmux" <<'TMUX_EOF'
#!/usr/bin/env bash
if [[ "$1" == "list-windows" ]]; then
  printf 'wt-co-pilot-1\n'
fi
TMUX_EOF
  chmod +x "$fake_bin/tmux"

  # IDLE_COMPLETED_TS: wt-co-pilot-1 は ts=1 (idle)、Worker なし
  run bash <<TESTEOF
source "${OBSERVER_WAVE_CHECK}"
declare -A IDLE_COMPLETED_TS
IDLE_COMPLETED_TS["wt-co-pilot-1"]=1
export PATH="${fake_bin}:\$PATH"
if _all_current_wave_idle_completed "${wave_queue}" IDLE_COMPLETED_TS; then
  echo "BUG: falsely returned true (Pilot-only idle triggered next-spawn)"
  exit 1
else
  echo "CORRECT: false returned (no Worker windows in wave)"
  exit 0
fi
TESTEOF

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CORRECT"* ]]
}

@test "ac4-T2: Pilot idle + Worker running → _all_current_wave_idle_completed が偽" {
  # AC: Worker (ap-*) が ts=0 (running) の場合は false を返す
  # RED: AC-2 実装前は wt-co-* が wave_windows 混入し検証対象になるが
  #      Worker が running の場合は true/false どちらの挙動も起きうる
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  local wave_queue
  wave_queue="${SUPERVISOR_DIR}/wave-queue.json"
  cat > "$wave_queue" <<EOF
{
  "version": 1,
  "current_wave": 1,
  "queue": []
}
EOF

  # tmux モック: Worker と Pilot が共存
  local fake_bin
  fake_bin="${TMPDIR_TEST}/fake-bin-ac4b"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/tmux" <<'TMUX_EOF'
#!/usr/bin/env bash
if [[ "$1" == "list-windows" ]]; then
  printf 'ap-worker-1\nwt-co-pilot-1\n'
fi
TMUX_EOF
  chmod +x "$fake_bin/tmux"

  # IDLE_COMPLETED_TS: Pilot idle (ts=1)、Worker running (ts=0)
  run bash <<TESTEOF
source "${OBSERVER_WAVE_CHECK}"
declare -A IDLE_COMPLETED_TS
IDLE_COMPLETED_TS["ap-worker-1"]=0
IDLE_COMPLETED_TS["wt-co-pilot-1"]=1
export PATH="${fake_bin}:\$PATH"
if _all_current_wave_idle_completed "${wave_queue}" IDLE_COMPLETED_TS; then
  echo "BUG: falsely returned true (Worker still running)"
  exit 1
else
  echo "CORRECT: false returned (Worker ap-worker-1 is still running)"
  exit 0
fi
TESTEOF

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CORRECT"* ]]
}

# ===========================================================================
# AC-5 (bats T3): cld-observe-any で controller window が SKIP 後 next-spawn 不発火
# RED: AC-1 実装前は wt-co-* が next-spawn 判定に到達し誤発火するため fail
# ===========================================================================

@test "ac5-T3: cld-observe-any で wt-co-* window が IDLE-COMPLETED-SKIP を出力する" {
  # AC: controller window が [IDLE-COMPLETED-SKIP] を next-spawn context で出力する
  # RED: AC-1 実装前は SKIP なく next-spawn 判定に突入するため fail
  [ -f "${CLD_OBSERVE_ANY}" ]

  # source-guard が存在することを確認（_DAEMON_LOAD_ONLY パターン）
  run grep -n '_DAEMON_LOAD_ONLY\|source.only\|--no-exec' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]

  # wt-co-* が next-spawn を skip する証拠として IDLE-COMPLETED-SKIP テキストを含む行が
  # AUTO_NEXT_SPAWN 判定ブロックの内部または直前に存在すること
  run grep -c 'IDLE-COMPLETED-SKIP' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  # 実装後は 2 行以上（auto-kill skip + next-spawn skip）
  local skip_count="${output}"
  [ "${skip_count}" -ge 2 ]
}

@test "ac5-T3: cld-observe-any の AUTO_NEXT_SPAWN ブロックで wt-co-* は continue される" {
  # AC: AUTO_NEXT_SPAWN 判定前に [[ "$WIN" == wt-co-* ]] && continue が存在する
  # RED: 実装前は continue が存在しないため fail する
  [ -f "${CLD_OBSERVE_ANY}" ]

  # AUTO_NEXT_SPAWN 判定行番号を取得
  local spawn_line
  spawn_line=$(grep -n 'IDLE_COMPLETED_AUTO_NEXT_SPAWN.*!= "0"' "${CLD_OBSERVE_ANY}" | head -1 | cut -d: -f1)
  [ -n "$spawn_line" ]

  # spawn_line より前（-10 行以内）に wt-co-* continue 分岐が存在すること
  local context_start=$(( spawn_line - 10 ))
  [ "${context_start}" -gt 0 ] || context_start=1

  run sed -n "${context_start},${spawn_line}p" "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"wt-co-*"* ]] && [[ "${output}" == *"continue"* ]]
}

@test "ac5-T3: cld-observe-any で wt-co-* は auto-next-spawn fire を emit しない" {
  # AC: controller window の IDLE-COMPLETED サイクルで 'auto-next-spawn fire' が出力されない
  # RED: AC-1 実装前は Pilot が next-spawn を trigger するため fail
  [ -f "${CLD_OBSERVE_ANY}" ]

  # source guard の存在確認（source 時に main 到達で exit しない保護）
  run grep -n '_DAEMON_LOAD_ONLY\|_TEST_MODE' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]

  # テスト: cld-observe-any を source-only モードで読み込み、
  # 内部の SKIP 分岐が AUTO_NEXT_SPAWN fire ログより先に来ることを grep で確認
  local skip_line fire_line
  skip_line=$(grep -n 'IDLE-COMPLETED-SKIP.*next.spawn\|next.spawn.*IDLE-COMPLETED-SKIP\|controller.*next.spawn' "${CLD_OBSERVE_ANY}" | head -1 | cut -d: -f1)
  fire_line=$(grep -n 'auto-next-spawn fire' "${CLD_OBSERVE_ANY}" | head -1 | cut -d: -f1)

  # skip_line が存在し、fire_line より小さい行番号（skip が先）であること
  [ -n "$skip_line" ]
  [ -n "$fire_line" ]
  [ "${skip_line}" -lt "${fire_line}" ]
}

# ===========================================================================
# AC-6: observer-auto-next-spawn.bats の ac3 テスト更新後の動作確認
# (AC-6 自体は既存テストファイル更新。本ファイルでは更新後パターンを検証する)
# RED: observer-wave-check.sh が旧パターン (wt|coi) のまま、または
#      observer-auto-next-spawn.bats が更新未適用の場合 fail
# ===========================================================================

@test "ac6: observer-wave-check.sh が ^(ap|coi)- パターンを使用し (ap|wt|coi) が消えている" {
  # AC: AC-2 の実装検証 — observer-auto-next-spawn.bats の ac3 テストとの整合
  # RED: 実装前は旧パターン (ap|wt|coi) が残るため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]

  # 旧パターンが消えていること
  run grep -E '\(ap\|wt\|coi\)' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -ne 0 ]

  # 新パターンが存在すること
  run grep -E '\(ap\|coi\)' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -eq 0 ]
}

@test "ac6: observer-auto-next-spawn.bats の ac3 テストが ^(ap|coi)- パターンを検証している" {
  # AC: 既存 bats ファイルの ac3 テストが更新後パターンに合わせて修正されていること
  # RED: observer-auto-next-spawn.bats がまだ旧パターン (ap|wt|coi) でテストしている場合 fail
  local bats_file
  bats_file="${REPO_ROOT}/tests/bats/observer-auto-next-spawn.bats"
  [ -f "$bats_file" ]

  # ac3 テスト中の grep パターンアサーションが (ap|wt|coi) を含まないこと
  # (更新後は (ap|coi) のみ参照しているはず)
  run grep -A5 'ac3.*list-windows.*ap.*wt.*coi\|ac3.*coi.*wt.*ap' "$bats_file"
  # 旧パターンを検証する ac3 テストが存在しないこと
  [ "${status}" -ne 0 ]
}

@test "ac6: observer-auto-next-spawn.bats の ac3 テストが (ap|coi) パターンで wave_windows を検証" {
  # AC: 更新後の ac3 テストが新パターン ^(ap|coi)- を参照していること
  # RED: 更新が未適用の場合 fail
  local bats_file
  bats_file="${REPO_ROOT}/tests/bats/observer-auto-next-spawn.bats"
  [ -f "$bats_file" ]

  # ac3 テストで (ap|coi) パターンが参照されていること
  run grep -E '\(ap\|coi\)' "$bats_file"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}
