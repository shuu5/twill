#!/usr/bin/env bats
# pre-bash-merge-guard-security.bats — Issue #1280 (TDD RED フェーズ)
#
# AC-1: デフォルトログパスの安全化
#   plugins/twl/scripts/hooks/mcp-shadow-merge-guard-writer.sh の LOG_FILE デフォルト値が
#   /tmp/mcp-shadow-merge-guard.log（固定パス）から安全なパスに変更される。
#   - XDG_RUNTIME_DIR が設定されている場合は ${XDG_RUNTIME_DIR}/mcp-shadow-merge-guard.log を使用する
#   - SHADOW_LOG_PATH 環境変数によるオーバーライドは維持
#
# AC-2: コマンド平文記録のマスキング
#   mcp-shadow-merge-guard-writer.sh が出力する JSONL の command フィールドに、
#   コマンド全文ではなく先頭128文字のみ（または類似の上限）が記録される。
#   - command の長さが 128（またはスクリプトで定義された定数）以下である
#   - 元のフルコマンドが記録されないこと
#
# RED: 全テストは実装前に FAIL する。
#
# bats §9 チェック: このファイルでは heredoc 内に外部変数（$BATS_TEST_FILENAME 等）を使用しない。
# bats §10 チェック: mcp-shadow-merge-guard-writer.sh は `bash <script>` で直接実行するスクリプトであり
#   source を前提としていない。source guard の不在はリスクではない（直接実行のみを意図）。

REPO_ROOT=""
WRITER=""
SHADOW_LOG=""

setup() {
  REPO_ROOT="$(git -C "$(dirname "$BATS_TEST_FILENAME")" rev-parse --show-toplevel 2>/dev/null)"
  WRITER="${REPO_ROOT}/plugins/twl/scripts/hooks/mcp-shadow-merge-guard-writer.sh"
  # 並列実行での競合を防ぐため一意パスを使用
  SHADOW_LOG="$(mktemp /tmp/mcp-shadow-merge-guard-XXXXXX.log)"
}

teardown() {
  rm -f "$SHADOW_LOG"
}

# ---------------------------------------------------------------------------
# AC-1: デフォルトログパスの安全化
#
# WHEN SHADOW_LOG_PATH が未設定かつ XDG_RUNTIME_DIR が設定されている
# THEN LOG_FILE のデフォルトが ${XDG_RUNTIME_DIR}/mcp-shadow-merge-guard.log になる
#
# RED: 現在の実装では LOG_FILE="${SHADOW_LOG_PATH:-/tmp/mcp-shadow-merge-guard.log}" と
#      ハードコードされており、XDG_RUNTIME_DIR を参照しない。
#      このテストは XDG_RUNTIME_DIR ベースのパスへの書き込みを期待するため FAIL する。
# ---------------------------------------------------------------------------

@test "ac1: XDG_RUNTIME_DIR が設定されている場合 XDG_RUNTIME_DIR 配下のパスに書き込まれる" {
  # AC: XDG_RUNTIME_DIR が設定されている場合、デフォルトログパスが
  #     ${XDG_RUNTIME_DIR}/mcp-shadow-merge-guard.log になること
  # RED: 現在の実装は /tmp/mcp-shadow-merge-guard.log 固定のため FAIL
  local xdg_runtime_dir
  xdg_runtime_dir="$(mktemp -d /tmp/xdg-runtime-XXXXXX)"

  XDG_RUNTIME_DIR="$xdg_runtime_dir" \
    bash "$WRITER" \
      --command "git merge feat/test" \
      --bash-exit 0 \
      --mcp-exit 0

  local expected_log="${xdg_runtime_dir}/mcp-shadow-merge-guard.log"
  local result
  result=1
  if [[ -f "$expected_log" ]]; then
    result=0
  fi
  rm -rf "$xdg_runtime_dir"
  [ "$result" -eq 0 ]
}

@test "ac1: XDG_RUNTIME_DIR が設定されている場合 /tmp/mcp-shadow-merge-guard.log には書き込まれない" {
  # AC: XDG_RUNTIME_DIR ベースのパスを使用するため、固定の /tmp パスには書き込まれないこと
  # RED: 現在の実装は /tmp/mcp-shadow-merge-guard.log に書き込むため FAIL
  local xdg_runtime_dir
  xdg_runtime_dir="$(mktemp -d /tmp/xdg-runtime-XXXXXX)"
  local tmp_fixed_log="/tmp/mcp-shadow-merge-guard.log"

  # 固定パスが既存の場合でも上書きしないよう退避
  local backed_up=false
  if [[ -f "$tmp_fixed_log" ]]; then
    mv "$tmp_fixed_log" "${tmp_fixed_log}.bak.$$"
    backed_up=true
  fi

  XDG_RUNTIME_DIR="$xdg_runtime_dir" \
    bash "$WRITER" \
      --command "git merge feat/test" \
      --bash-exit 0 \
      --mcp-exit 0

  local fixed_created=false
  [[ -f "$tmp_fixed_log" ]] && fixed_created=true

  # クリーンアップ
  rm -rf "$xdg_runtime_dir"
  rm -f "$tmp_fixed_log"
  if [[ "$backed_up" == "true" ]]; then
    mv "${tmp_fixed_log}.bak.$$" "$tmp_fixed_log"
  fi

  # 固定パスに書き込まれていないことを確認
  # RED: 現在の実装は固定パスに書き込むため $fixed_created == true になり FAIL
  [[ "$fixed_created" == "false" ]]
}

@test "ac1: SHADOW_LOG_PATH によるオーバーライドは XDG_RUNTIME_DIR 設定時も維持される" {
  # AC: SHADOW_LOG_PATH が設定されている場合は XDG_RUNTIME_DIR より優先される
  # このテストは SHADOW_LOG_PATH オーバーライドの継続動作を確認する
  # 現在の実装でも SHADOW_LOG_PATH は機能するが、XDG_RUNTIME_DIR サポート追加後も維持されることを確認
  local xdg_runtime_dir
  xdg_runtime_dir="$(mktemp -d /tmp/xdg-runtime-XXXXXX)"
  local override_log
  override_log="$(mktemp /tmp/mcp-override-XXXXXX.log)"

  XDG_RUNTIME_DIR="$xdg_runtime_dir" \
  SHADOW_LOG_PATH="$override_log" \
    bash "$WRITER" \
      --command "git merge feat/test" \
      --bash-exit 0 \
      --mcp-exit 0

  local xdg_log="${xdg_runtime_dir}/mcp-shadow-merge-guard.log"
  local override_has_entry=false
  local xdg_has_entry=false

  [[ -f "$override_log" ]] && [[ -s "$override_log" ]] && override_has_entry=true
  [[ -f "$xdg_log" ]] && [[ -s "$xdg_log" ]] && xdg_has_entry=true

  rm -rf "$xdg_runtime_dir"
  rm -f "$override_log"

  # SHADOW_LOG_PATH に書き込まれ、XDG パスには書き込まれないこと
  [[ "$override_has_entry" == "true" ]]
  [[ "$xdg_has_entry" == "false" ]]
}

@test "ac1: スクリプト本体に XDG_RUNTIME_DIR の参照が含まれる（静的検査）" {
  # AC: mcp-shadow-merge-guard-writer.sh が XDG_RUNTIME_DIR を参照していること
  # RED: 現在の実装には XDG_RUNTIME_DIR が含まれないため FAIL
  grep -q "XDG_RUNTIME_DIR" "$WRITER"
}

@test "ac1: スクリプト本体に /tmp/mcp-shadow-merge-guard.log のハードコードが含まれない（静的検査）" {
  # AC: 固定の /tmp パスがハードコードされていないこと
  # RED: 現在の実装には /tmp/mcp-shadow-merge-guard.log がハードコードされているため FAIL
  # grep -c は no-match 時に exit 1 を返すため || true でガード
  local count
  count=$(grep -c '/tmp/mcp-shadow-merge-guard\.log' "$WRITER" || true)
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-2: コマンド平文記録のマスキング
#
# WHEN 128文字を超えるコマンドを --command に渡す
# THEN JSONL の command フィールドが 128 文字以下に切り詰められる
#
# RED: 現在の実装では --arg command "$CMD" をそのまま jq に渡すため、
#      全文が記録される。切り詰めを期待するテストは FAIL する。
# ---------------------------------------------------------------------------

@test "ac2: 129文字のコマンドを渡すと command フィールドが 128 文字以下になる" {
  # AC: command フィールドの長さが 128 以下であること
  # RED: 現在の実装は全文記録のため 129 文字が記録され FAIL
  local long_cmd
  long_cmd="$(python3 -c "print('git merge feat/' + 'a' * 114)")"
  # long_cmd は "git merge feat/" (15) + "a" * 114 = 129 文字

  bash "$WRITER" \
    --command "$long_cmd" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local recorded_len
  recorded_len=$(jq -r '.command | length' "$SHADOW_LOG")
  [ "$recorded_len" -le 128 ]
}

@test "ac2: 256文字のコマンドを渡すと command フィールドが 128 文字以下になる" {
  # AC: 256文字でも command フィールドは 128 文字以下に切り詰められる
  # RED: 現在の実装は全文記録のため 256 文字が記録され FAIL
  local long_cmd
  long_cmd="$(python3 -c "print('git merge feat/' + 'x' * 241)")"
  # long_cmd は "git merge feat/" (15) + "x" * 241 = 256 文字

  bash "$WRITER" \
    --command "$long_cmd" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local recorded_len
  recorded_len=$(jq -r '.command | length' "$SHADOW_LOG")
  [ "$recorded_len" -le 128 ]
}

@test "ac2: 128文字丁度のコマンドは切り詰めされずそのまま記録される" {
  # AC: 128 文字以下のコマンドは全文記録される（マスキングは上限のみ）
  # このテストは現在の実装でも PASS する可能性があるが、
  # 実装後の回帰防止として含める
  local exact_cmd
  exact_cmd="$(python3 -c "print('git merge feat/' + 'c' * 113)")"
  # "git merge feat/" (15) + "c" * 113 = 128 文字

  bash "$WRITER" \
    --command "$exact_cmd" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local recorded_len
  recorded_len=$(jq -r '.command | length' "$SHADOW_LOG")
  # 128文字以下のコマンドは切り詰めされずに記録される
  [ "$recorded_len" -eq 128 ]
}

@test "ac2: 短いコマンドは全文がそのまま記録される" {
  # AC: 短いコマンド（128文字未満）は全文記録される
  # このテストは実装前後で PASS する（回帰テスト）
  local short_cmd="git merge feat/sample"

  bash "$WRITER" \
    --command "$short_cmd" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local recorded_cmd
  recorded_cmd=$(jq -r '.command' "$SHADOW_LOG")
  [ "$recorded_cmd" = "$short_cmd" ]
}

@test "ac2: 長いコマンドの記録後 mismatch フィールドが正しく記録される" {
  # AC: コマンド切り詰め後も mismatch フィールドは正常に記録される
  # RED: 現在の実装が切り詰めをサポートしていないため、切り詰め後の mismatch 検証は行えない
  #      ただし、AC-2 の実装後に mismatch フィールドが壊れていないことを確認するため記載
  #      現状: このテストは command 長の assertion が先に FAIL する
  local long_cmd
  long_cmd="$(python3 -c "print('git merge feat/' + 'z' * 241)")"
  # "git merge feat/" (15) + "z" * 241 = 256 文字

  bash "$WRITER" \
    --command "$long_cmd" \
    --bash-exit 0 \
    --mcp-exit 1 \
    --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local recorded_len
  recorded_len=$(jq -r '.command | length' "$SHADOW_LOG")
  [ "$recorded_len" -le 128 ]

  # mismatch は bash_exit=0, mcp_exit=1 で true
  local mismatch
  mismatch=$(jq -r '.mismatch' "$SHADOW_LOG")
  [ "$mismatch" = "true" ]
}

@test "ac2: スクリプト本体に command 切り詰め（128 または定数）の実装が含まれる（静的検査）" {
  # AC: mcp-shadow-merge-guard-writer.sh に command の切り詰め実装が含まれること
  #     具体的には "128" または切り詰め関連のキーワードが存在する
  # RED: 現在の実装には切り詰め処理が存在しないため FAIL
  grep -qE '\b128\b|truncat|cut_|CMD_MAX|COMMAND_MAX|\.[:0-9]*128|.[[:space:]]*\[:128\]' "$WRITER"
}
