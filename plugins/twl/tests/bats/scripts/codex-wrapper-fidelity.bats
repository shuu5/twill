#!/usr/bin/env bats
# codex-wrapper-fidelity.bats
#
# Issue #1484: observability - codex CLI wrapper
#
# AC1: /home/shuu5/.local/bin/codex を wrapper に置換、codex.real に元本体を rename。
#      wrapper は exec で透過実行 (副作用なし)
# AC2: 全呼び出しを ~/.codex-call-trace.log に記録
#      (timestamp/PID/PPID/PWD/ARGS/PARENT/STDIN_LEN/STDIN_HEAD/EXIT_CODE/stdout/stderr)
# AC3: wrapper 透過性を 3 項目以上 assert (このファイル自体が AC3)
# AC4: codex-call-trace-monitor.sh で定期 audit
#      (24h ゼロ call → WARN, exit ≠ 0 連続 → WARN)
# AC5: ロールバック手順をドキュメント化
#      mv ~/.local/bin/codex.real ~/.local/bin/codex で 1 コマンド復旧
# AC6: [Qq]uota|exceeded パターン match 時に CODEX_SKIP_REASON 記録 +
#      ~/.codex-call-trace.log に該当エントリ存在
# AC7: Wave 57 dummy PR で wrapper log にエントリ生成 (subagent が実際に codex を呼ぶことを確認)
#
# RED フェーズ:
#   実装前のため全テストが FAIL することを意図する。
#   - codex.real が存在しない
#   - ~/.local/bin/codex が wrapper になっていない
#   - codex-call-trace-monitor.sh が存在しない
#   - ドキュメントが存在しない

load '../helpers/common'

CODEX_WRAPPER=/home/shuu5/.local/bin/codex
CODEX_REAL=/home/shuu5/.local/bin/codex.real
MONITOR_SCRIPT=""
TRACE_LOG=""

setup() {
  common_setup
  MONITOR_SCRIPT="$REPO_ROOT/scripts/codex-call-trace-monitor.sh"
  TRACE_LOG="$(mktemp -u /tmp/codex-call-trace-test-XXXXXX.log)"
}

teardown() {
  # テスト用一時ログファイルを削除
  [[ -n "${TRACE_LOG:-}" && -f "$TRACE_LOG" ]] && rm -f "$TRACE_LOG"
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: wrapper 置換確認
# ---------------------------------------------------------------------------

@test "ac1: codex.real が ~/.local/bin/ に存在する" {
  # RED: 実装前は codex.real が存在しないため FAIL
  [[ -f "$CODEX_REAL" ]] || {
    echo "FAIL: $CODEX_REAL が存在しない (wrapper への置換が未実施)" >&2
    return 1
  }
}

@test "ac1: codex.real が実行可能である" {
  # RED: codex.real が存在しないため FAIL
  [[ -x "$CODEX_REAL" ]] || {
    echo "FAIL: $CODEX_REAL が実行可能でない" >&2
    return 1
  }
}

@test "ac1: ~/.local/bin/codex が bash wrapper スクリプトである (バイナリではない)" {
  # RED: 現在 codex は Node.js binary へのシンボリックリンクのため FAIL
  # wrapper に置換後は bash スクリプトになる
  local file_type
  file_type=$(file "$CODEX_WRAPPER" 2>/dev/null || echo "not found")
  echo "$file_type" | grep -qiE "(shell script|bash script|text)" || {
    echo "FAIL: $CODEX_WRAPPER が bash wrapper でない (現在: $file_type)" >&2
    return 1
  }
}

@test "ac1: codex wrapper が exec で codex.real を呼ぶ (透過実行)" {
  # RED: wrapper が存在しないため FAIL
  # wrapper 内に 'exec' で codex.real を呼ぶ記述が必要
  grep -qE 'exec[[:space:]].*codex\.real' "$CODEX_WRAPPER" || {
    echo "FAIL: $CODEX_WRAPPER に exec codex.real パターンが存在しない" >&2
    return 1
  }
}

@test "ac1: codex wrapper が引数を変更せずに codex.real に渡す (透過性)" {
  # RED: wrapper が存在しないため FAIL
  # wrapper は引数を変更せずに codex.real に exec すること
  # wrapper のソースに '"\$@"' または '"${@}"' が含まれることを確認
  grep -qE '"?\$\{?@\}?"?' "$CODEX_WRAPPER" || {
    echo "FAIL: $CODEX_WRAPPER が \$@ を codex.real に渡していない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC2: ログ記録確認
# ---------------------------------------------------------------------------

@test "ac2: wrapper 実行後に ~/.codex-call-trace.log にエントリが追記される" {
  # RED: wrapper が存在しないためエントリが記録されず FAIL
  local log_file="$HOME/.codex-call-trace.log"
  local before_lines=0
  [[ -f "$log_file" ]] && before_lines=$(wc -l < "$log_file")

  # 実際の wrapper を呼び出す (codex --version 相当の軽量呼び出し)
  # wrapper が存在しなければ codex.real も存在せず失敗する
  "$CODEX_WRAPPER" --version 2>/dev/null || true

  local after_lines=0
  [[ -f "$log_file" ]] && after_lines=$(wc -l < "$log_file")

  [[ "$after_lines" -gt "$before_lines" ]] || {
    echo "FAIL: $log_file に新しいエントリが追記されなかった" >&2
    return 1
  }
}

@test "ac2: ログエントリに timestamp フィールドが含まれる" {
  # RED: wrapper が存在しないためエントリが記録されず FAIL
  local log_file="$HOME/.codex-call-trace.log"
  [[ -f "$log_file" ]] || {
    echo "FAIL: $log_file が存在しない" >&2
    return 1
  }
  grep -qE 'timestamp=' "$log_file" || {
    echo "FAIL: $log_file に timestamp フィールドが存在しない" >&2
    return 1
  }
}

@test "ac2: ログエントリに PID フィールドが含まれる" {
  # RED: wrapper が存在しないためエントリが記録されず FAIL
  local log_file="$HOME/.codex-call-trace.log"
  [[ -f "$log_file" ]] || {
    echo "FAIL: $log_file が存在しない" >&2
    return 1
  }
  grep -qE 'PID=' "$log_file" || {
    echo "FAIL: $log_file に PID フィールドが存在しない" >&2
    return 1
  }
}

@test "ac2: ログエントリに EXIT_CODE フィールドが含まれる" {
  # RED: wrapper が存在しないためエントリが記録されず FAIL
  local log_file="$HOME/.codex-call-trace.log"
  [[ -f "$log_file" ]] || {
    echo "FAIL: $log_file が存在しない" >&2
    return 1
  }
  grep -qE 'EXIT_CODE=' "$log_file" || {
    echo "FAIL: $log_file に EXIT_CODE フィールドが存在しない" >&2
    return 1
  }
}

@test "ac2: ログエントリに ARGS フィールドが含まれる" {
  # RED: wrapper が存在しないためエントリが記録されず FAIL
  local log_file="$HOME/.codex-call-trace.log"
  [[ -f "$log_file" ]] || {
    echo "FAIL: $log_file が存在しない" >&2
    return 1
  }
  grep -qE 'ARGS=' "$log_file" || {
    echo "FAIL: $log_file に ARGS フィールドが存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC3: wrapper 透過性 (AC3 はこのファイル全体を指すが、追加の直接確認テストを記載)
# ---------------------------------------------------------------------------

@test "ac3: codex wrapper の exit code が codex.real の exit code と一致する" {
  # RED: wrapper が存在しないため FAIL
  # codex.real が存在しない場合も FAIL
  [[ -x "$CODEX_REAL" ]] || {
    echo "FAIL: $CODEX_REAL が存在しないため透過性を確認できない" >&2
    return 1
  }
  # codex.real を直接実行した exit code
  "$CODEX_REAL" --version 2>/dev/null; local real_exit=$?
  # wrapper 経由の exit code
  "$CODEX_WRAPPER" --version 2>/dev/null; local wrapper_exit=$?
  [[ "$real_exit" -eq "$wrapper_exit" ]] || {
    echo "FAIL: codex.real exit=$real_exit, wrapper exit=$wrapper_exit (不一致)" >&2
    return 1
  }
}

@test "ac3: codex wrapper の stdout が codex.real の stdout と一致する" {
  # RED: wrapper が存在しないため FAIL
  [[ -x "$CODEX_REAL" ]] || {
    echo "FAIL: $CODEX_REAL が存在しないため透過性を確認できない" >&2
    return 1
  }
  local real_out wrapper_out
  real_out=$("$CODEX_REAL" --version 2>/dev/null || echo "")
  wrapper_out=$("$CODEX_WRAPPER" --version 2>/dev/null || echo "")
  [[ "$real_out" == "$wrapper_out" ]] || {
    echo "FAIL: stdout 不一致: real='$real_out', wrapper='$wrapper_out'" >&2
    return 1
  }
}

@test "ac3: codex wrapper が stdin を codex.real に透過的に渡す" {
  # RED: wrapper が存在しないため FAIL
  [[ -x "$CODEX_REAL" ]] || {
    echo "FAIL: $CODEX_REAL が存在しないため透過性を確認できない" >&2
    return 1
  }
  # stdin を持つ呼び出しの透過確認 (STDIN_LEN が記録されることを確認)
  local log_file="$HOME/.codex-call-trace.log"
  local before_lines=0
  [[ -f "$log_file" ]] && before_lines=$(wc -l < "$log_file")
  echo "test-input" | "$CODEX_WRAPPER" --version 2>/dev/null || true
  local after_lines=0
  [[ -f "$log_file" ]] && after_lines=$(wc -l < "$log_file")
  [[ "$after_lines" -gt "$before_lines" ]] || {
    echo "FAIL: stdin 付き呼び出しがログに記録されなかった" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC4: codex-call-trace-monitor.sh の存在と機能確認
# ---------------------------------------------------------------------------

@test "ac4: codex-call-trace-monitor.sh が scripts/ に存在する" {
  # RED: 未実装のため FAIL
  [[ -f "$MONITOR_SCRIPT" ]] || {
    echo "FAIL: $MONITOR_SCRIPT が存在しない" >&2
    return 1
  }
}

@test "ac4: codex-call-trace-monitor.sh が実行可能である" {
  # RED: 未実装のため FAIL
  [[ -x "$MONITOR_SCRIPT" ]] || {
    echo "FAIL: $MONITOR_SCRIPT が実行可能でない" >&2
    return 1
  }
}

@test "ac4: codex-call-trace-monitor.sh が bash 構文チェック pass" {
  # RED: 未実装のため FAIL
  [[ -f "$MONITOR_SCRIPT" ]] || {
    echo "FAIL: $MONITOR_SCRIPT が存在しない" >&2
    return 1
  }
  run bash -n "$MONITOR_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "ac4: monitor.sh が 24h ゼロ call 時に WARN を出力する" {
  # RED: codex-call-trace-monitor.sh が存在しないため FAIL
  [[ -x "$MONITOR_SCRIPT" ]] || {
    echo "FAIL: $MONITOR_SCRIPT が存在しないためテスト不能" >&2
    return 1
  }
  # 空のログファイルを用意して 24h ゼロ call 状態をシミュレート
  local empty_log
  empty_log=$(mktemp /tmp/codex-trace-empty-XXXXXX.log)
  run bash "$MONITOR_SCRIPT" --log "$empty_log"
  rm -f "$empty_log"
  echo "$output" | grep -qi "WARN" || {
    echo "FAIL: ゼロ call 時に WARN が出力されなかった (output: $output)" >&2
    return 1
  }
}

@test "ac4: monitor.sh が exit != 0 連続時に WARN を出力する" {
  # RED: codex-call-trace-monitor.sh が存在しないため FAIL
  [[ -x "$MONITOR_SCRIPT" ]] || {
    echo "FAIL: $MONITOR_SCRIPT が存在しないためテスト不能" >&2
    return 1
  }
  # exit != 0 が連続するログを作成
  local fail_log
  fail_log=$(mktemp /tmp/codex-trace-fail-XXXXXX.log)
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  for i in 1 2 3; do
    echo "timestamp=${ts} PID=${i} EXIT_CODE=1 ARGS=--version" >> "$fail_log"
  done
  run bash "$MONITOR_SCRIPT" --log "$fail_log"
  rm -f "$fail_log"
  echo "$output" | grep -qi "WARN" || {
    echo "FAIL: exit!=0 連続時に WARN が出力されなかった (output: $output)" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC5: ロールバックドキュメント確認
# ---------------------------------------------------------------------------

@test "ac5: ロールバック手順ドキュメントが存在する" {
  # RED: ドキュメントが未作成のため FAIL
  # ロールバック手順は refs/ または docs/ 配下に存在するはず
  local doc_found=0
  # docs/ または refs/ 配下に codex wrapper rollback 手順が存在するか確認
  if find "$REPO_ROOT" -maxdepth 3 \
      \( -name "*.md" -o -name "*.txt" \) \
      -not -path "*/tests/*" \
      -not -path "*/.git/*" \
      | xargs grep -l "codex.real" 2>/dev/null | grep -q .; then
    doc_found=1
  fi
  [[ "$doc_found" -eq 1 ]] || {
    echo "FAIL: codex.real ロールバック手順を含むドキュメントが存在しない" >&2
    return 1
  }
}

@test "ac5: ロールバック手順に 'mv ~/.local/bin/codex.real ~/.local/bin/codex' が記載されている" {
  # RED: ドキュメントが未作成のため FAIL
  local found=0
  if find "$REPO_ROOT" -maxdepth 3 \
      \( -name "*.md" -o -name "*.txt" \) \
      -not -path "*/tests/*" \
      -not -path "*/.git/*" \
      | xargs grep -lF "codex.real" 2>/dev/null | xargs grep -lF "codex.real ~/.local/bin/codex" 2>/dev/null | grep -q .; then
    found=1
  fi
  [[ "$found" -eq 1 ]] || {
    echo "FAIL: 'mv ~/.local/bin/codex.real ~/.local/bin/codex' のロールバックコマンドがドキュメントに存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC6: Quota/exceeded パターン検知と CODEX_SKIP_REASON 記録
# ---------------------------------------------------------------------------

@test "ac6: wrapper が quota パターン検知時に CODEX_SKIP_REASON を記録する" {
  # RED: wrapper が実装されていないため FAIL
  # また codex.real が quota エラーを返す状況を再現できないため FAIL
  [[ -x "$CODEX_REAL" ]] || {
    echo "FAIL: $CODEX_REAL が存在しないため AC6 テスト不能" >&2
    return 1
  }
  # quota エラーを含む stderr を持つ mock wrapper 実行をシミュレート
  # wrapper が CODEX_SKIP_REASON 環境変数またはログに記録するかを確認
  local log_file="$HOME/.codex-call-trace.log"
  local before_lines=0
  [[ -f "$log_file" ]] && before_lines=$(wc -l < "$log_file")

  # quota パターンを含む出力を強制するには実際の quota 状態が必要。
  # wrapper が [Qq]uota|exceeded パターンを検出するロジックをグレップで確認する
  grep -qE '\[Qq\]uota|exceeded' "$CODEX_WRAPPER" || {
    echo "FAIL: $CODEX_WRAPPER に [Qq]uota|exceeded パターン検知ロジックが存在しない" >&2
    return 1
  }
}

@test "ac6: wrapper が quota 検知時に ~/.codex-call-trace.log に CODEX_SKIP_REASON エントリを記録する" {
  # RED: wrapper が実装されていないため FAIL
  [[ -f "$CODEX_WRAPPER" ]] || {
    echo "FAIL: $CODEX_WRAPPER が存在しない" >&2
    return 1
  }
  # wrapper ソースに CODEX_SKIP_REASON 記録処理が存在するかを確認
  grep -qE 'CODEX_SKIP_REASON' "$CODEX_WRAPPER" || {
    echo "FAIL: $CODEX_WRAPPER に CODEX_SKIP_REASON 記録ロジックが存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC7: subagent が実際に codex を呼ぶことを確認 (Wave 57 依存のため skip)
# ---------------------------------------------------------------------------

@test "ac7: [SKIP] Wave 57 dummy PR 実行後に wrapper log にエントリが生成される" {
  # このテストは Wave 57 dummy PR 実行後の実機確認が必要なため skip する。
  # 実機確認手順:
  #   1. Wave 57 で dummy PR を作成し worker-codex-reviewer subagent を invoke する
  #   2. ~/.codex-call-trace.log に新規エントリが追記されることを確認する
  #   3. エントリに PARENT フィールドで worker-codex-reviewer が呼び出し元と確認できること
  skip "AC7 は Wave 57 dummy PR 実行依存。実機確認が必要なため自動テストは skip"
}
