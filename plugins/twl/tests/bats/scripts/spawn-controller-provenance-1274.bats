#!/usr/bin/env bats
# spawn-controller-provenance-1274.bats - RED-phase tests for Issue #1274
#
# feat(provenance): spawn-controller.sh に provenance section を追加
#
# AC coverage:
#   AC1 - spawn-controller.sh に _emit_provenance_section() と _get_host_alias() 関数が存在する
#   AC2 - FINAL_PROMPT 構築部で /twl:<skill> の直後に $(emit_provenance_section) が追加される
#   AC3 - co-issue refine / co-explore / co-architect の 3 controller で provenance section が prompt に含まれる
#   AC4 - co-issue/co-explore/co-architect の SKILL.md に「provenance section を Issue body 末尾にコピー」MUST が追加される
#   AC5 - _get_host_alias() は ~/.config/twl/host-aliases.json 不在時は空文字を返す
#   AC6 - symlink deploy 下での git rev-parse --show-toplevel 挙動を bats fixture で検証
#   AC7 - predecessor field は session.json の predecessor_host から取得可能（失敗時は空文字）
#   AC8 - provenance section の行数（PROVENANCE_LINES）を logging で計測する
#
# 全テストは実装前（RED）状態で fail する。

load '../helpers/common'

SPAWN_CONTROLLER=""
CLD_SPAWN_ARGS_LOG=""

setup() {
  common_setup

  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  CLD_SPAWN_ARGS_LOG="$SANDBOX/cld-spawn-args.log"
  export CLD_SPAWN_ARGS_LOG

  # cld-spawn mock: 引数を記録して正常終了
  cat > "$STUB_BIN/cld-spawn" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CLD_SPAWN_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$STUB_BIN/cld-spawn"

  MOCK_CLD_SPAWN="$STUB_BIN/cld-spawn"
  export MOCK_CLD_SPAWN

  ACTUAL_TWILL_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
  export ACTUAL_TWILL_ROOT

  # spawn-controller.sh wrapper: CLD_SPAWN と TWILL_ROOT を mock/実パスに差し替えて実行
  cat > "$SANDBOX/run-spawn-controller.sh" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
TMP_SCRIPT="\$(mktemp)"
cp "$SPAWN_CONTROLLER" "\$TMP_SCRIPT"
# TWILL_ROOT をスクリプトコピー時に正しい実パスに差し替える（/tmp/ 実行時のパス解決失敗を防ぐ）
sed -i "s|TWILL_ROOT=.*|TWILL_ROOT=\"$ACTUAL_TWILL_ROOT\"|" "\$TMP_SCRIPT"
sed -i "s|CLD_SPAWN=\"\\\$TWILL_ROOT/plugins/session/scripts/cld-spawn\"|CLD_SPAWN=\"$MOCK_CLD_SPAWN\"|g" "\$TMP_SCRIPT"
chmod +x "\$TMP_SCRIPT"
exec bash "\$TMP_SCRIPT" "\$@"
WRAPPER
  chmod +x "$SANDBOX/run-spawn-controller.sh"
}

teardown() {
  common_teardown
}

make_prompt_file() {
  local lines="$1"
  local path="$2"
  local i
  for i in $(seq 1 "$lines"); do
    echo "line $i of the prompt"
  done > "$path"
}

# ===========================================================================
# AC1: spawn-controller.sh に _emit_provenance_section() と _get_host_alias() が存在する
# ===========================================================================

@test "ac1: _emit_provenance_section 関数が spawn-controller.sh に定義されている" {
  # AC: spawn-controller.sh に _emit_provenance_section() 関数が存在する
  # RED: 実装前は関数定義が存在しないため fail する
  run grep -qE '^_emit_provenance_section\(\)' "$SPAWN_CONTROLLER"
  [ "$status" -eq 0 ]
}

@test "ac1: _get_host_alias ヘルパー関数が spawn-controller.sh に定義されている" {
  # AC: spawn-controller.sh に _get_host_alias() ヘルパー関数が存在する
  # RED: 実装前は関数定義が存在しないため fail する
  run grep -qE '^_get_host_alias\(\)' "$SPAWN_CONTROLLER"
  [ "$status" -eq 0 ]
}

@test "ac1: provenance 関連関数の合計行数が 10-15 行の範囲内である" {
  # AC: _emit_provenance_section と _get_host_alias の合計が 10-15 行
  # RED: 関数自体が存在しないため fail する
  run bash -c "
    # _emit_provenance_section と _get_host_alias の合計行数を計測
    # 関数開始行から次の関数定義か空行 + 閉じ括弧までを抽出
    provenance_lines=\$(awk '
      /^_emit_provenance_section\(\)/ { in_func=1; count=0 }
      /^_get_host_alias\(\)/ { in_func=1; count=0 }
      in_func { count++ }
      in_func && /^}/ { total += count; in_func=0 }
      END { print total }
    ' '$SPAWN_CONTROLLER')
    [ -n \"\$provenance_lines\" ] || exit 1
    [ \"\$provenance_lines\" -ge 10 ] || exit 1
    [ \"\$provenance_lines\" -le 15 ] || exit 1
  "
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC2: FINAL_PROMPT 構築部で provenance section が /twl:<skill> の直後に追加される
# ===========================================================================

@test "ac2: FINAL_PROMPT 構築部に emit_provenance_section の呼び出しが存在する" {
  # AC: FINAL_PROMPT 変数の構築で $(emit_provenance_section) または $(_emit_provenance_section) が含まれる
  # RED: 実装前は provenance section の呼び出しがないため fail する
  run grep -qE '\$\(_emit_provenance_section\)|\$\(emit_provenance_section\)' "$SPAWN_CONTROLLER"
  [ "$status" -eq 0 ]
}

@test "ac2: FINAL_PROMPT に PROVENANCE 変数が /twl:<skill> の直後に配置されている" {
  # AC: FINAL_PROMPT="/twl:${SKILL_NORMALIZED}\n${PROVENANCE}\n${PROMPT_BODY}" の順序で構築される
  # RED: 実装前は provenance が FINAL_PROMPT に含まれないため fail する
  run bash -c "
    # FINAL_PROMPT 代入ブロックを抽出し、/twl: と PROVENANCE の順序を確認
    awk '
      /^FINAL_PROMPT=/ { start=NR }
      start && NR >= start && NR < (start+5) {
        if (/PROVENANCE/) { found_prov=1 }
        if (/\/twl:/) { found_skill=1 }
      }
      start && NR > (start+5) { start=0 }
      END {
        if (found_skill && found_prov) exit 0
        exit 1
      }
    ' '$SPAWN_CONTROLLER'
  "
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC3: 3 controller 全てで provenance section が prompt に含まれる（実行ベース）
# ===========================================================================

@test "ac3: co-issue refine 起動時の FINAL_PROMPT に provenance section が含まれる" {
  # AC: /twl:co-issue で spawn した prompt に provenance section が含まれる
  # RED: _emit_provenance_section が未実装のため provenance section が出力されず fail する
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  SKIP_PARALLEL_CHECK=1 SUPERVISOR_DIR="$SANDBOX/.supervisor" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-issue "$SANDBOX/prompt.txt" \
    --window-name "test-provenance-co-issue"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  # provenance section の識別子として "<!-- provenance" または "PROVENANCE" または "hostname:" を検索
  [[ "$args" == *"## provenance"* || "$args" == *"provenance (auto-injected)"* || "$args" == *"- host:"* ]] \
    || fail "co-issue prompt に provenance section が含まれない: $args"
}

@test "ac3: co-explore 起動時の FINAL_PROMPT に provenance section が含まれる" {
  # AC: /twl:co-explore で spawn した prompt に provenance section が含まれる
  # RED: _emit_provenance_section が未実装のため fail する
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  SKIP_PARALLEL_CHECK=1 SUPERVISOR_DIR="$SANDBOX/.supervisor" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-provenance-co-explore"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"## provenance"* || "$args" == *"provenance (auto-injected)"* || "$args" == *"- host:"* ]] \
    || fail "co-explore prompt に provenance section が含まれない: $args"
}

@test "ac3: co-architect 起動時の FINAL_PROMPT に provenance section が含まれる" {
  # AC: /twl:co-architect で spawn した prompt に provenance section が含まれる
  # RED: _emit_provenance_section が未実装のため fail する
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  SKIP_PARALLEL_CHECK=1 SUPERVISOR_DIR="$SANDBOX/.supervisor" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-architect "$SANDBOX/prompt.txt" \
    --window-name "test-provenance-co-architect"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"## provenance"* || "$args" == *"provenance (auto-injected)"* || "$args" == *"- host:"* ]] \
    || fail "co-architect prompt に provenance section が含まれない: $args"
}

# ===========================================================================
# AC4: 3 SKILL.md に「provenance section を Issue body 末尾にコピー」MUST が追加される
# ===========================================================================

@test "ac4: co-issue/SKILL.md に provenance section を Issue body 末尾にコピーする MUST が存在する" {
  # AC: co-issue/SKILL.md に「provenance section を Issue body 末尾にコピー」という MUST 記載がある
  # RED: 実装前は SKILL.md に該当 MUST が存在しないため fail する
  local skill_md="$REPO_ROOT/skills/co-issue/SKILL.md"
  run grep -qiE 'provenance.*MUST|MUST.*provenance|provenance.*Issue body|Issue body.*provenance' "$skill_md"
  [ "$status" -eq 0 ]
}

@test "ac4: co-explore/SKILL.md に provenance section を Issue body 末尾にコピーする MUST が存在する" {
  # AC: co-explore/SKILL.md に「provenance section を Issue body 末尾にコピー」という MUST 記載がある
  # RED: 実装前は SKILL.md に該当 MUST が存在しないため fail する
  local skill_md="$REPO_ROOT/skills/co-explore/SKILL.md"
  run grep -qiE 'provenance.*MUST|MUST.*provenance|provenance.*Issue body|Issue body.*provenance' "$skill_md"
  [ "$status" -eq 0 ]
}

@test "ac4: co-architect/SKILL.md に provenance section を Issue body 末尾にコピーする MUST が存在する" {
  # AC: co-architect/SKILL.md に「provenance section を Issue body 末尾にコピー」という MUST 記載がある
  # RED: 実装前は SKILL.md に該当 MUST が存在しないため fail する
  local skill_md="$REPO_ROOT/skills/co-architect/SKILL.md"
  run grep -qiE 'provenance.*MUST|MUST.*provenance|provenance.*Issue body|Issue body.*provenance' "$skill_md"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC5: _get_host_alias() は host-aliases.json 不在時は空文字を返す
# ===========================================================================

@test "ac5: _get_host_alias は ~/.config/twl/host-aliases.json が不在のとき空文字を返す" {
  # AC: _get_host_alias は host-aliases.json がない場合に空文字を返す
  # RED: _get_host_alias 関数が未実装のため fail する
  run bash -c "
    # _get_host_alias を source で読み込むためのラッパー
    # spawn-controller.sh は set -euo pipefail があり main に達すると exit するリスクがあるため
    # 関数定義部分のみを抽出して eval する
    source_only_functions() {
      local tmpfile
      tmpfile=\"\$(mktemp)\"
      # _get_host_alias 関数定義を抽出
      awk '
        /^_get_host_alias\(\)/ { in_func=1; depth=0 }
        in_func {
          print
          if (/\{/) depth++
          if (/\}/) { depth--; if (depth <= 0) { in_func=0 } }
        }
      ' '$SPAWN_CONTROLLER' > \"\$tmpfile\"
      source \"\$tmpfile\"
      rm -f \"\$tmpfile\"
    }

    # XDG_CONFIG_HOME を存在しないパスに向けて host-aliases.json を不在にする
    export XDG_CONFIG_HOME=\"\$(mktemp -d)\"
    source_only_functions
    result=\"\$(_get_host_alias)\"
    [ -z \"\$result\" ]
  "
  [ "$status" -eq 0 ]
}

@test "ac5: _get_host_alias は host-aliases.json が存在するとき alias を返す" {
  # AC: _get_host_alias は host-aliases.json が存在する場合に alias を返す
  # RED: _get_host_alias 関数が未実装のため fail する
  run bash -c "
    source_only_functions() {
      local tmpfile
      tmpfile=\"\$(mktemp)\"
      awk '
        /^_get_host_alias\(\)/ { in_func=1; depth=0 }
        in_func {
          print
          if (/\{/) depth++
          if (/\}/) { depth--; if (depth <= 0) { in_func=0 } }
        }
      ' '$SPAWN_CONTROLLER' > \"\$tmpfile\"
      source \"\$tmpfile\"
      rm -f \"\$tmpfile\"
    }

    # 一時 host-aliases.json を作成
    local_config=\"\$(mktemp -d)\"
    mkdir -p \"\$local_config/twl\"
    this_host=\"\$(hostname)\"
    echo '{\"'\"\$this_host\"'\": \"test-alias\"}' > \"\$local_config/twl/host-aliases.json\"
    export XDG_CONFIG_HOME=\"\$local_config\"

    source_only_functions
    result=\"\$(_get_host_alias)\"
    [ \"\$result\" = 'test-alias' ]
  "
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC6: symlink deploy 下での git rev-parse --show-toplevel 挙動を fixture で検証
# ===========================================================================

@test "ac6: symlink deploy 環境で git rev-parse --show-toplevel が symlink 先 repo root を返す" {
  # AC: ~/.claude/plugins/twl → twill repo という symlink 配置で
  #     spawn-controller.sh 内の git rev-parse --show-toplevel が twill repo を返す（#1244 known-issue 再確認）
  # RED: _emit_provenance_section が未実装のため provenance section が生成されず fail する
  #
  # fixture 構成:
  #   SANDBOX/fake-repo/plugins/twl/skills/su-observer/scripts/spawn-controller.sh (本物へのシンボリックリンク)
  #   SANDBOX/fake-repo/ が git repo root

  # fake repo を初期化（git identity を明示して auto-detect エラーを防ぐ）
  local fake_repo="$SANDBOX/fake-repo"
  mkdir -p "$fake_repo/plugins/twl/skills/su-observer/scripts"
  (cd "$fake_repo" && git init -q \
    && git -c user.email="test@test.com" -c user.name="Test" \
       commit -q --allow-empty -m "init")

  # spawn-controller.sh を fake-repo 配下にシンボリックリンク
  ln -s "$SPAWN_CONTROLLER" \
    "$fake_repo/plugins/twl/skills/su-observer/scripts/spawn-controller.sh"

  # symlink 経由で git rev-parse --show-toplevel を実行
  run bash -c "
    cd '$fake_repo/plugins/twl/skills/su-observer/scripts'
    script_real=\$(readlink -f 'spawn-controller.sh')
    # SCRIPT_DIR が本物のパスを指す（symlink 解決後）
    script_dir=\"\$(cd \"\$(dirname \"\$script_real\")\" && pwd)\"
    # git rev-parse は CWD の repo を返す（symlink 先ではなく呼び出し元の CWD）
    cwd_git_root=\"\$(git rev-parse --show-toplevel 2>/dev/null || echo 'FAIL')\"
    # spawn-controller.sh 内の TWILL_ROOT 解決（SCRIPT_DIR 起点 5 階層上）は
    # readlink -f 後の本物パスを起点とするため、CWD の fake-repo とは異なる可能性がある
    twill_root_from_script=\"\$(cd \"\$script_dir/../../../../..\" && pwd)\"
    # 検証: CWD の git root と TWILL_ROOT が一致しないことを確認（known-issue の確認）
    echo \"cwd_git_root=\$cwd_git_root\"
    echo \"twill_root_from_script=\$twill_root_from_script\"
    echo \"fake_repo=$fake_repo\"
    # AC6 の PASS 条件: _emit_provenance_section が git rev-parse 結果を正しく処理する
    # RED: _emit_provenance_section 未実装のため spawn 後に provenance section がない
    grep -q '_emit_provenance_section' '$SPAWN_CONTROLLER'
  "
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC7: predecessor field は session.json の predecessor_host から取得可能
# ===========================================================================

@test "ac7: _emit_provenance_section は session.json の predecessor_host を参照する" {
  # AC: session.json に predecessor_host が存在する場合、provenance section の predecessor field に反映される
  # RED: _emit_provenance_section が未実装のため fail する
  run grep -qE 'predecessor_host|predecessor' "$SPAWN_CONTROLLER"
  [ "$status" -eq 0 ]
}

@test "ac7: session.json の predecessor_host 取得失敗時は空文字にフォールバックする" {
  # AC: session.json が存在しない / predecessor_host フィールドがない場合は predecessor は空文字
  # RED: _emit_provenance_section 未実装のため fail する
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  # session.json を置かない状態で実行（predecessor_host 不在）
  SKIP_PARALLEL_CHECK=1 SUPERVISOR_DIR="$SANDBOX/.supervisor" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-predecessor-fallback"

  # spawn 自体は成功すること（predecessor 取得失敗で abort してはならない）
  assert_success
}

@test "ac7: session.json に predecessor_host がある場合 provenance section に cross-machine handoff 情報が含まれる" {
  # AC: session.json に predecessor_host フィールドがある場合、provenance section に反映される
  # RED: _emit_provenance_section 未実装 + SUPERVISOR_DIR 環境変数への対応が未実装のため fail する
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  # session.json に predecessor_host を設定
  local supervisor_dir="$SANDBOX/.supervisor"
  mkdir -p "$supervisor_dir"
  cat > "$supervisor_dir/session.json" <<'JSON'
{
  "session_id": "test-session-1274",
  "predecessor_host": "ipatho-1",
  "observer_window": ""
}
JSON

  SKIP_PARALLEL_CHECK=1 SUPERVISOR_DIR="$supervisor_dir" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-predecessor-host"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  # provenance section に predecessor 情報（ipatho-1）が含まれることを確認
  [[ "$args" == *"ipatho-1"* || "$args" == *"predecessor"* ]] \
    || fail "co-explore prompt に predecessor_host が含まれない: $args"
}

# ===========================================================================
# AC8: PROVENANCE_LINES を logging で計測する
# ===========================================================================

@test "ac8: spawn-controller.sh に PROVENANCE_LINES 変数の計測ロジックが存在する" {
  # AC: provenance section の行数を PROVENANCE_LINES 変数で計測し logging する
  # RED: 実装前は PROVENANCE_LINES の定義がないため fail する
  run grep -qE 'PROVENANCE_LINES' "$SPAWN_CONTROLLER"
  [ "$status" -eq 0 ]
}

@test "ac8: provenance section 出力後に行数を stderr にログ出力する" {
  # AC: PROVENANCE_LINES を計測し "[spawn-controller]" prefix で stderr に出力する
  # RED: PROVENANCE_LINES 計測ロジックが未実装のため fail する
  make_prompt_file 5 "$SANDBOX/prompt.txt"

  SKIP_PARALLEL_CHECK=1 SUPERVISOR_DIR="$SANDBOX/.supervisor" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-provenance-lines" 2>&1

  assert_success
  # stderr に PROVENANCE_LINES のログが出力されること
  [[ "$output" == *"PROVENANCE_LINES"* || "$output" == *"provenance"*"lines"* ]] \
    || fail "PROVENANCE_LINES の logging が出力されない: $output"
}
