#!/usr/bin/env bats
# spawn-controller-monitor-reset.bats
# RED tests for Issue #1186: spawn-controller.sh に WINDOW_NAME 変数を導入し
# exec/cld-spawn 呼出直前に Monitor 再 arm emit を行う
#
# AC coverage:
#   AC3.0 - spawn-controller.sh 内に WINDOW_NAME 変数を導入
#   AC3.1 - emit は exec/cld-spawn 呼出の直前に行う（両分岐対応）
#   AC3.2 - emit pattern を monitor-channel-catalog.md に追加
#   AC3.3 - pitfalls-catalog.md に §11.7 または §11.8 として channel reset MUST エントリを追加（実際は §11.8）
#   AC3.4 - 完了判定: stdout 末尾に正しい emit が含まれる
#
# テスト設計:
#   - cld-spawn を stub して副作用を回避する
#   - autopilot-launch.sh も stub して --with-chain 分岐をテスト可能にする
#   - spawn-controller.sh の exec を回避するため DRY_RUN=1 または stub CLD_SPAWN を使用
#   - 実装前はすべて fail する（RED フェーズ）
#
# RED: WINDOW_NAME 変数未実装 / emit 未実装のため全テストが fail する
#
# WARN: source guard 確認結果:
#   spawn-controller.sh に [[ "${BASH_SOURCE[0]}" == "${0}" ]] guard が存在しない。
#   set -euo pipefail 環境で source すると main 到達前に exit に巻き込まれるリスクあり。
#   本テストでは source せず、bash サブシェルで直接実行する設計で回避済み。
#   実装者は spawn-controller.sh に source guard 追加を検討すること（impl_files メモ参照）。

load '../helpers/common'

SPAWN_SCRIPT=""

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"

  # cld-spawn stub: 引数と stdout を記録して正常終了
  cat > "$STUB_BIN/cld-spawn" <<'CLD_SPAWN_STUB'
#!/usr/bin/env bash
echo "cld-spawn-stub: $*" >> "${CLD_SPAWN_LOG:-/dev/null}"
exit 0
CLD_SPAWN_STUB
  chmod +x "$STUB_BIN/cld-spawn"

  export CLD_SPAWN_LOG="$SANDBOX/cld-spawn.log"
  touch "$CLD_SPAWN_LOG"

  # autopilot-launch.sh stub: --with-chain 分岐用
  cat > "$STUB_BIN/autopilot-launch-stub.sh" <<'AUTOPILOT_STUB'
#!/usr/bin/env bash
echo "autopilot-launch-stub: $*" >> "${AUTOPILOT_LOG:-/dev/null}"
exit 0
AUTOPILOT_STUB
  chmod +x "$STUB_BIN/autopilot-launch-stub.sh"

  export AUTOPILOT_LOG="$SANDBOX/autopilot.log"
  touch "$AUTOPILOT_LOG"

  # observer-parallel-check.sh stub: spawn 可否チェックをバイパス
  mkdir -p "$STUB_BIN/../lib"
  cat > "$SANDBOX/observer-parallel-check.sh" <<'PARALLEL_STUB'
#!/usr/bin/env bash
_check_parallel_spawn_eligibility() { return 0; }
PARALLEL_STUB
  export SKIP_PARALLEL_CHECK=1
  export SKIP_PARALLEL_REASON="bats test RED phase"

  # プロンプトファイルをサンドボックスに作成
  echo "test prompt content" > "$SANDBOX/test-prompt.txt"

  # tmux stub: 副作用を回避（_setup_observer_panes を呼び出さないよう設計）
  stub_command "tmux" 'echo "tmux-stub: $*" >> "${TMUX_LOG:-/dev/null}"; exit 0'
  export TMUX_LOG="$SANDBOX/tmux.log"
  touch "$TMUX_LOG"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: spawn-controller.sh を副作用なしで実行してその stdout を capture する
# CLD_SPAWN を STUB_BIN/cld-spawn に差し替えることで exec を回避する
# WARNING: exec は置換されたプロセスで実行されるため、stdout 末尾の emit は
#          exec 直前でなければキャプチャできない
# ---------------------------------------------------------------------------
_run_spawn_controller() {
  local skill="${1:-co-issue}"
  shift
  local prompt_file="${1:-$SANDBOX/test-prompt.txt}"
  shift
  local extra_args=("$@")

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SKIP_PARALLEL_CHECK=1
export SKIP_PARALLEL_REASON='bats test RED phase'
export CLD_SPAWN_LOG='${CLD_SPAWN_LOG}'
export AUTOPILOT_LOG='${AUTOPILOT_LOG}'
export TMUX_LOG='${TMUX_LOG}'

# CLD_SPAWN を stub に差し替えてTWILL_ROOT の解決をバイパスする
# spawn-controller.sh が TWILL_ROOT/plugins/session/scripts/cld-spawn を参照するため
# STUB_BIN に cld-spawn が存在するよう PATH を先頭追加済み
# ただし -x チェックをバイパスするため TWILL_ROOT も設定する
export TWILL_ROOT='${REPO_ROOT}/../../../..'

bash '${SPAWN_SCRIPT}' '${skill}' '${prompt_file}' ${extra_args[@]+${extra_args[@]}}
"
}

# ===========================================================================
# AC3.0: spawn-controller.sh 内に WINDOW_NAME 変数を導入
#
# 検証: WINDOW_NAME 変数が存在すること（現状は WINDOW_NAME_ARG 配列のみ）
# RED: 実装前は fail する（WINDOW_NAME 変数が未定義）
# PASS 条件（実装後）:
#   - --window-name 省略時: WINDOW_NAME="wt-co-issue-HHMMSS" が設定される
#   - --window-name test-spawn 指定時: WINDOW_NAME="test-spawn" が設定される
# ===========================================================================

@test "ac3.0: spawn-controller.sh が WINDOW_NAME 変数を内部で設定する（自動生成時）" {
  # AC: WINDOW_NAME 変数を導入（現状は WINDOW_NAME_ARG 配列のみ存在）
  # RED: 実装前は fail する

  # WINDOW_NAME 変数が設定されるかを確認するため、spawn-controller.sh を grep で検査する
  # 実装後: line 285 近辺に WINDOW_NAME="wt-..." の代入が存在するはず
  # パターン: 行頭が WINDOW_NAME=" で始まる（HAS_WINDOW_NAME= や WINDOW_NAME_ARG= は除外）
  local wname_count
  wname_count=$(grep -cE '^\s*WINDOW_NAME="' "${SPAWN_SCRIPT}" 2>/dev/null || true)
  [[ "$wname_count" -ge 1 ]] || {
    echo "RED: WINDOW_NAME=\"...\" 代入が spawn-controller.sh に存在しない（HAS_WINDOW_NAME= や WINDOW_NAME_ARG= は別物）"
    echo "現在の WINDOW_NAME 関連行:"
    grep -n 'WINDOW_NAME' "${SPAWN_SCRIPT}" || echo "(none)"
    false
  }
}

@test "ac3.0: --window-name 明示時に WINDOW_NAME が指定値を保持する（getopt 風 loop）" {
  # AC: --window-name 明示時: \$@ を getopt 風 loop でパースして WINDOW_NAME に格納
  # RED: 実装前は fail する（WINDOW_NAME 変数が未定義）

  # spawn-controller.sh 内で --window-name の値を WINDOW_NAME 変数に格納するロジックが存在するか確認
  # 実装後: prev_arg == "--window-name" 時に WINDOW_NAME="$arg" のような代入が存在するはず
  # パターン: WINDOW_NAME="$arg" または WINDOW_NAME=$arg の代入行（単独の WINDOW_NAME 代入）
  local match_count
  match_count=$(grep -cE '^\s*WINDOW_NAME="\$arg"' "${SPAWN_SCRIPT}" 2>/dev/null || true)
  [[ "$match_count" -ge 1 ]] || {
    echo "RED: WINDOW_NAME=\"\$arg\" 代入（--window-name パース）が spawn-controller.sh に存在しない"
    echo "現在の --window-name 関連行:"
    grep -n 'window-name\|WINDOW_NAME' "${SPAWN_SCRIPT}" || echo "(none)"
    false
  }
}

# ===========================================================================
# AC3.1: emit は exec/cld-spawn 呼出の直前に行う
#
# 検証: spawn-controller.sh のソースコードに emit 文が exec の直前にあること
# RED: 実装前は fail する（emit 文が存在しない）
# PASS 条件（実装後）:
#   - exec "$CLD_SPAWN" ... の直前行に echo ">>> Monitor 再 arm 必要: ..." が存在する
#   - "$CLD_SPAWN" ... （非 exec 呼び出し）の直前行にも同様に存在する
#   - exec bash "$AUTOPILOT_LAUNCH_SH" ... の直前行にも存在する
# ===========================================================================

@test "ac3.1: exec CLD_SPAWN 直前に emit 文が存在する（else 分岐）" {
  # AC: emit は exec/cld-spawn 呼出の直前に行う（else 分岐 line 376-378）
  # RED: 実装前は fail する

  run grep -n '>>> Monitor 再 arm 必要' "${SPAWN_SCRIPT}"

  [[ "${status}" -eq 0 ]] || {
    echo "RED: '>>> Monitor 再 arm 必要' emit 文が spawn-controller.sh に存在しない"
    false
  }

  # emit が exec の直前（直前1行以内）にあることを確認
  # exec "$CLD_SPAWN" を含む行番号を取得
  local exec_line
  exec_line=$(grep -n 'exec "\$CLD_SPAWN"' "${SPAWN_SCRIPT}" | head -1 | cut -d: -f1)
  [[ -n "$exec_line" ]] || {
    echo "RED: exec \"\$CLD_SPAWN\" が spawn-controller.sh に見つからない"
    false
  }

  # exec の直前1行に emit が存在するか確認
  local prev_line=$(( exec_line - 1 ))
  local prev_content
  prev_content=$(sed -n "${prev_line}p" "${SPAWN_SCRIPT}")
  echo "$prev_content" | grep -q '>>> Monitor 再 arm 必要' || {
    echo "RED: exec \"\$CLD_SPAWN\" (line ${exec_line}) の直前行に emit が存在しない"
    echo "直前行 (${prev_line}): ${prev_content}"
    false
  }
}

@test "ac3.1: cld-spawn 非 exec 呼び出し直前にも emit 文が存在する（co-autopilot 非 --with-chain 分岐）" {
  # AC: co-autopilot 非 --with-chain (line 372-375) でも emit する
  # RED: 実装前は fail する

  # "\$CLD_SPAWN" (exec なし呼び出し) の行番号を特定
  local cld_line
  cld_line=$(grep -n '^\s*"\$CLD_SPAWN"' "${SPAWN_SCRIPT}" | head -1 | cut -d: -f1)
  [[ -n "$cld_line" ]] || {
    echo "RED: \"\$CLD_SPAWN\" (非 exec) 呼び出し行が spawn-controller.sh に見つからない"
    false
  }

  # 直前1行に emit が存在するか確認
  local prev_line=$(( cld_line - 1 ))
  local prev_content
  prev_content=$(sed -n "${prev_line}p" "${SPAWN_SCRIPT}")
  echo "$prev_content" | grep -q '>>> Monitor 再 arm 必要' || {
    echo "RED: \"\$CLD_SPAWN\" 非 exec 呼び出し (line ${cld_line}) の直前行に emit が存在しない"
    echo "直前行 (${prev_line}): ${prev_content}"
    false
  }
}

@test "ac3.1: exec autopilot-launch.sh 直前にも emit 文が存在する（--with-chain 分岐）" {
  # AC: --with-chain 分岐 (line 219-223) も同様に exec の直前で emit
  # RED: 実装前は fail する

  # exec bash "$AUTOPILOT_LAUNCH_SH" の行番号を特定
  local autopilot_exec_line
  autopilot_exec_line=$(grep -n 'exec bash "\$AUTOPILOT_LAUNCH_SH"' "${SPAWN_SCRIPT}" | head -1 | cut -d: -f1)
  [[ -n "$autopilot_exec_line" ]] || {
    echo "RED: exec bash \"\$AUTOPILOT_LAUNCH_SH\" が spawn-controller.sh に見つからない"
    false
  }

  # 直前1行に emit が存在するか確認
  local prev_line=$(( autopilot_exec_line - 1 ))
  local prev_content
  prev_content=$(sed -n "${prev_line}p" "${SPAWN_SCRIPT}")
  echo "$prev_content" | grep -q '>>> Monitor 再 arm 必要' || {
    echo "RED: exec bash \"\$AUTOPILOT_LAUNCH_SH\" (line ${autopilot_exec_line}) の直前行に emit が存在しない"
    echo "直前行 (${prev_line}): ${prev_content}"
    false
  }
}

# ===========================================================================
# AC3.2: emit pattern を monitor-channel-catalog.md に追加
#
# 検証: monitor-channel-catalog.md に regex パターンが追加されていること
# RED: 実装前は fail する（パターンが存在しない）
# PASS 条件（実装後）:
#   - `>>> Monitor 再 arm 必要: [^\n]+` が catalog に記載されている
#   - [CONTROLLER-SPAWN-COMPLETE] ブラケット形式は採用していない
# ===========================================================================

@test "ac3.2: monitor-channel-catalog.md に '>>> Monitor 再 arm 必要:' パターンが追加されている" {
  # AC: 単一 regex で確定: >>> Monitor 再 arm 必要: [^\n]+
  # RED: 実装前は fail する

  local catalog="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"

  [[ -f "$catalog" ]] || {
    echo "RED: monitor-channel-catalog.md が存在しない: ${catalog}"
    false
  }

  grep -q '>>> Monitor 再 arm 必要' "$catalog" || {
    echo "RED: '>>> Monitor 再 arm 必要' が monitor-channel-catalog.md に存在しない"
    false
  }
}

@test "ac3.2: monitor-channel-catalog.md の emit regex が [^\n]+ パターンを含む" {
  # AC: 単一 regex: >>> Monitor 再 arm 必要: [^\n]+
  # RED: 実装前は fail する

  local catalog="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"

  [[ -f "$catalog" ]] || {
    echo "RED: monitor-channel-catalog.md が存在しない"
    false
  }

  # regex パターン文字列が catalog に存在するか確認
  # 実装後: '>>> Monitor 再 arm 必要: [^\n]+' という文字列が catalog 内に記載されるはず
  # grep でリテラル検索（ERE を避けてエスケープ）
  grep -qF '[^\n]+' "$catalog" && grep -q 'Monitor 再 arm 必要' "$catalog" || {
    echo "RED: '>>> Monitor 再 arm 必要: [^\n]+' の regex パターンが catalog に存在しない"
    echo "現在の 'Monitor 再 arm' 周辺の記述:"
    grep -A 3 'Monitor 再 arm' "$catalog" 2>/dev/null || echo "(見つからない)"
    false
  }
}

# ===========================================================================
# AC3.3: pitfalls-catalog.md に §11.6 として channel reset MUST エントリを追加
#
# 検証: pitfalls-catalog.md に §11.6 または §11.7 として記載があること
# RED: 実装前は fail する（エントリが存在しない）
# PASS 条件（実装後）:
#   - §11.6 または §11.7 として「controller 遷移時 channel reset MUST」が記載されている
#   - Hash 3ecbfbc2 対策案を formal 化した内容であること
# ===========================================================================

@test "ac3.3: pitfalls-catalog.md に channel reset MUST エントリが追加されている" {
  # AC: pitfalls-catalog.md に §11.6 として「controller 遷移時 channel reset MUST」エントリを追加
  # RED: 実装前は fail する

  local catalog="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] || {
    echo "RED: pitfalls-catalog.md が存在しない: ${catalog}"
    false
  }

  # §11.6 または §11.7 の channel reset エントリを確認
  grep -q 'channel reset\|channel.reset\|Monitor 再 arm\|Monitor.*re.arm\|Monitor.*rearm' "$catalog" || {
    echo "RED: 'channel reset' / 'Monitor 再 arm' エントリが pitfalls-catalog.md に存在しない"
    echo "現在の §11 末尾:"
    grep -n '§11\.' "$catalog" | tail -5 || echo "(見つからない)"
    false
  }
}

@test "ac3.3: pitfalls-catalog.md の channel reset エントリが §11 セクション内に存在する" {
  # AC: §11.6 として追加（Hash 3ecbfbc2 対策案を formal 化）
  # RED: 実装前は fail する

  local catalog="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] || {
    echo "RED: pitfalls-catalog.md が存在しない"
    false
  }

  # §11.6 または channel reset が §11 セクション内に存在するか確認
  # 現状の §11 末尾は §11.6 Observer Self-Supervision (ADR-031) が存在するため
  # §11.7 として追加される可能性もある
  grep -qE '§11\.(6|7).*[Cc]hannel|[Cc]hannel.*reset.*MUST|Monitor.*再.*arm.*MUST' "$catalog" || {
    echo "RED: §11.6/§11.7 の channel reset MUST エントリが pitfalls-catalog.md に存在しない"
    echo "現在の §11.x エントリ一覧:"
    grep -n '§11\.' "$catalog" || echo "(見つからない)"
    false
  }
}

# ===========================================================================
# AC3.4: 完了判定 (bats test)
#   - stdout 末尾1行に '>>> Monitor 再 arm 必要: test-spawn' を含む
#   - --window-name 省略時の自動生成名も emit に含まれる
#
# RED: 実装前は fail する（emit 文が存在しないため）
# PASS 条件（実装後）:
#   - co-issue --window-name test-spawn の stdout 末尾に emit が含まれる
#   - --window-name 省略時は wt-co-issue-HHMMSS パターンの emit が含まれる
# ===========================================================================

@test "ac3.4: co-issue --window-name test-spawn の stdout 末尾に emit が含まれる" {
  # AC: bash spawn-controller.sh co-issue <prompt-file> --window-name test-spawn の stdout 末尾1行に
  #     >>> Monitor 再 arm 必要: test-spawn を含む
  # RED: 実装前は fail する

  # CLD_SPAWN の実体を stub に差し替え（exec 呼び出しをラップして stdout をキャプチャ可能にする）
  # exec は現在のプロセスを置換するため、exec 直前の echo が stdout に出力される
  local spawn_script_dir
  spawn_script_dir="$(dirname "${SPAWN_SCRIPT}")"

  # stub を TWILL_ROOT 下の正規パスに配置する必要があるため、wrapper を使う
  # TWILL_ROOT を SANDBOX に差し替え、SANDBOX/plugins/session/scripts/cld-spawn を stub に
  mkdir -p "$SANDBOX/plugins/session/scripts"
  cat > "$SANDBOX/plugins/session/scripts/cld-spawn" <<'CLD_STUB_EOF'
#!/usr/bin/env bash
echo "cld-spawn-stub: $*" >> "${CLD_SPAWN_LOG:-/dev/null}"
exit 0
CLD_STUB_EOF
  chmod +x "$SANDBOX/plugins/session/scripts/cld-spawn"

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SKIP_PARALLEL_CHECK=1
export SKIP_PARALLEL_REASON='bats test RED phase ac3.4'
export CLD_SPAWN_LOG='${CLD_SPAWN_LOG}'
export TMUX_LOG='${TMUX_LOG}'

# TWILL_ROOT を SANDBOX 下に差し替えて cld-spawn stub を解決
export TWILL_ROOT='${SANDBOX}'

bash '${SPAWN_SCRIPT}' co-issue '${SANDBOX}/test-prompt.txt' --window-name test-spawn
"

  # stdout の最後の出力行（emit 行）を確認
  # exec により spawn-controller.sh が置換されるが、exec 直前の echo が stdout に出力される
  echo "--- stdout ---"
  echo "${output}"
  echo "--- end ---"

  echo "${output}" | grep -q '>>> Monitor 再 arm 必要: test-spawn' || {
    echo "RED: stdout に '>>> Monitor 再 arm 必要: test-spawn' が含まれない"
    echo "stdout 末尾:"
    echo "${output}" | tail -3
    false
  }
}

@test "ac3.4: --window-name 省略時の自動生成名 wt-co-issue-HHMMSS が emit に含まれる" {
  # AC: --window-name 省略時の自動生成名 (wt-co-issue-HHMMSS) も emit に含まれる
  # RED: 実装前は fail する

  mkdir -p "$SANDBOX/plugins/session/scripts"
  cat > "$SANDBOX/plugins/session/scripts/cld-spawn" <<'CLD_STUB_EOF'
#!/usr/bin/env bash
echo "cld-spawn-stub: $*" >> "${CLD_SPAWN_LOG:-/dev/null}"
exit 0
CLD_STUB_EOF
  chmod +x "$SANDBOX/plugins/session/scripts/cld-spawn"

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SKIP_PARALLEL_CHECK=1
export SKIP_PARALLEL_REASON='bats test RED phase ac3.4 auto-name'
export CLD_SPAWN_LOG='${CLD_SPAWN_LOG}'
export TMUX_LOG='${TMUX_LOG}'
export TWILL_ROOT='${SANDBOX}'

bash '${SPAWN_SCRIPT}' co-issue '${SANDBOX}/test-prompt.txt'
"

  echo "--- stdout ---"
  echo "${output}"
  echo "--- end ---"

  # 自動生成名は wt-co-issue-HHMMSS パターン（6桁の時刻）
  echo "${output}" | grep -qE '>>> Monitor 再 arm 必要: wt-co-issue-[0-9]{6}' || {
    echo "RED: stdout に '>>> Monitor 再 arm 必要: wt-co-issue-HHMMSS' パターンが含まれない"
    echo "stdout 末尾:"
    echo "${output}" | tail -3
    false
  }
}
