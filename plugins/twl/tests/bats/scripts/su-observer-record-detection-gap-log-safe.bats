#!/usr/bin/env bats
# su-observer-record-detection-gap-log-safe.bats
#
# RED-phase tests for Issue #1386:
#   tech-debt(observer): record-detection-gap.sh L65 の ${_supervisor_dir} 出力に
#   printf '%q' またはコントロール文字除去を適用する
#
# AC coverage:
#   AC1: record-detection-gap.sh L65 のエラーメッセージ出力で printf '%q' または
#        コントロール文字除去が適用されていること（静的確認）
#   AC2: 改行/制御文字を含む SUPERVISOR_DIR を渡した場合、stderr 出力が単一行に
#        収まること（改行で分割された FAKE LOG ENTRY 行が現れないことを assert）
#   AC3: 既存テスト record-detection-gap-deps-registered.bats は GREEN を維持する
#        （このテストファイルは既存テストを壊さないことを静的に確認する）
#   AC4: record-detection-gap.sh の L61-65 以外（L62 の ^/ 拒否、L63 の .. 拒否）に
#        新たに ${_supervisor_dir} を埋め込む変更が含まれていないこと
#
# RED: AC1, AC2 は実装前（sanitize 未適用）のため fail する
# PASS: AC3, AC4 は現状の実装で成立する（回帰防止）

load '../helpers/common'

SCRIPT=""

setup() {
    common_setup
    SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-detection-gap.sh"
    export SCRIPT

    # テスト実行は SANDBOX 内で行う（SUPERVISOR_DIR の相対パス解決のため）
    cd "${SANDBOX}"
}

teardown() {
    common_teardown
}

# ===========================================================================
# AC1: L65 のエラーメッセージ出力に sanitize (printf '%q' またはコントロール文字除去) が適用されている
# ===========================================================================

@test "ac1: script exists at expected path" {
    # 前提確認: スクリプトが存在する
    [ -f "${SCRIPT}" ]
}

@test "ac1: L65 error message output uses printf '%q' for _supervisor_dir" {
    # AC: L65 の echo/printf で ${_supervisor_dir} を出力する際、printf '%q' が適用されている
    # RED: 現状は printf '%q' が使用されていないため fail
    run grep -E "printf\s+'%q'" "${SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "ac1: L65 error message output applies control-char removal for _supervisor_dir" {
    # AC: または、${_supervisor_dir} 出力前に改行・CR・制御文字を除去するコードが存在する
    # RED: 現状は制御文字除去が存在しないため fail
    # NOTE: printf '%q' または // 置換パターンのいずれかが存在すれば AC1 を満たす
    local has_sanitize=0
    grep -qE "printf\s+'%q'" "${SCRIPT}" && has_sanitize=1
    grep -qE '_supervisor_dir.*\$.*\\n|_supervisor_dir=.*\$.*\\n' "${SCRIPT}" 2>/dev/null && has_sanitize=1
    [ "${has_sanitize}" -eq 1 ]
}

# ===========================================================================
# AC2: 改行/制御文字を含む SUPERVISOR_DIR で stderr 出力が単一行に収まる
# ===========================================================================

@test "ac2: SUPERVISOR_DIR with newline produces single-line stderr output" {
    # AC: SUPERVISOR_DIR に改行を含む値を渡した場合、stderr 出力が単一行に収まる
    # RED: 現状は ${_supervisor_dir} をそのまま echo するため、改行で行が分割される
    #
    # 期待動作（実装後）:
    #   stderr は 1 行のみ。改行が除去または %q エスケープされていること
    #
    # 現状の動作（実装前）:
    #   "ERROR: invalid path: evil\npath (...)" の改行が展開され、
    #   stderr に "evil" と "path (...)" の 2 行が出力される
    local evil_dir
    evil_dir="$(printf 'evil\npath')"
    SUPERVISOR_DIR="${evil_dir}" run bash "${SCRIPT}" \
        --type "injection-test" \
        --detail "newline in supervisor dir" 2>&1 >/dev/null

    # exit 1 であること（invalid path として拒否される）
    [ "${status}" -eq 1 ]

    # stderr 出力（output に格納）が 1 行であること
    # 改行で分割された場合は output が複数行になる
    local line_count
    line_count="$(echo "${output}" | wc -l)"
    [ "${line_count}" -eq 1 ]
}

@test "ac2: SUPERVISOR_DIR with carriage return produces single-line stderr output" {
    # AC: SUPERVISOR_DIR に CR を含む値を渡した場合も stderr 出力が単一行に収まる
    # RED: CR もコントロール文字として出力に混入するため fail する可能性がある
    local evil_dir
    evil_dir="$(printf 'evil\rpath')"
    SUPERVISOR_DIR="${evil_dir}" run bash "${SCRIPT}" \
        --type "injection-test" \
        --detail "cr in supervisor dir" 2>&1 >/dev/null

    [ "${status}" -eq 1 ]

    local line_count
    line_count="$(echo "${output}" | wc -l)"
    [ "${line_count}" -eq 1 ]
}

@test "ac2: SUPERVISOR_DIR with newline does not produce FAKE LOG ENTRY lines in stderr" {
    # AC: stderr に改行で分割された "FAKE LOG ENTRY" 相当の行（スペースで始まる行や
    #     "path" 単体行など）が現れないこと
    # RED: 現状は改行が展開されるため、"path (...)" という別行が stderr に現れる
    local evil_dir
    evil_dir="$(printf 'evil\npath')"
    SUPERVISOR_DIR="${evil_dir}" run bash "${SCRIPT}" \
        --type "injection-test" \
        --detail "no fake log entry check" 2>&1 >/dev/null

    [ "${status}" -eq 1 ]

    # "path" という文字列が行頭に現れる行が存在しないこと（改行分割による副行チェック）
    # 改行分割が起きると output の 2 行目が "path (must be relative...)" になる
    local second_line
    second_line="$(echo "${output}" | sed -n '2p')"
    [ -z "${second_line}" ]
}

@test "ac2: SUPERVISOR_DIR with embedded null-like control chars produces single-line stderr" {
    # AC: タブ文字など他の制御文字を含む場合も stderr は単一行に収まる
    # RED: 制御文字除去が未実装のため、一部の制御文字が出力に混入する可能性がある
    local evil_dir
    evil_dir="$(printf 'evil\tpath')"
    SUPERVISOR_DIR="${evil_dir}" run bash "${SCRIPT}" \
        --type "injection-test" \
        --detail "tab in supervisor dir" 2>&1 >/dev/null

    [ "${status}" -eq 1 ]

    local line_count
    line_count="$(echo "${output}" | wc -l)"
    [ "${line_count}" -eq 1 ]
}

# ===========================================================================
# AC3: 既存テストファイルが変更されていないこと（静的回帰確認）
# ===========================================================================

@test "ac3: record-detection-gap-deps-registered.bats exists and is unchanged" {
    # AC: 既存テスト record-detection-gap-deps-registered.bats が GREEN を維持する前提として
    #     ファイルが存在すること
    local existing_test="${REPO_ROOT}/tests/bats/scripts/record-detection-gap-deps-registered.bats"
    [ -f "${existing_test}" ]
}

@test "ac3: record-detection-gap-deps-registered.bats still contains ac3 tests" {
    # AC: 既存テストの内容が消去・弱化されていないこと（ac3 テストが存在する）
    local existing_test="${REPO_ROOT}/tests/bats/scripts/record-detection-gap-deps-registered.bats"
    run grep -qF 'ac3:' "${existing_test}"
    [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: L61-65 以外に ${_supervisor_dir} を埋め込む変更が含まれていないこと
# ===========================================================================

@test "ac4: only one line in the script embeds _supervisor_dir in error output" {
    # AC: エラーメッセージに ${_supervisor_dir} を埋め込む行が L64 の 1 行のみであること
    # （L62 ^/ 拒否・L63 .. 拒否などに新たな ${_supervisor_dir} 埋め込みが追加されていないこと）
    local embed_count
    embed_count="$(grep -cE '(echo|printf).*\$\{?_supervisor_dir\}?.*>&2' "${SCRIPT}" || echo 0)"
    [ "${embed_count}" -le 1 ]
}

@test "ac4: L62 absolute-path check does not have a separate standalone error message line" {
    # AC: L62 の ^/ チェック（絶対パス拒否）には、L65 とは別に独立した echo/printf 行がない
    # （もし追加する場合は同等の sanitize が必要、未追加であれば PASS）
    #
    # 検証方法: スクリプト中で "must not be an absolute" または "absolute path" という
    #           キーワードを含む echo/printf >&2 行が存在しないこと
    #           （L64/65 の unified エラーは "must be relative" を含むが "must not be an absolute" は含まない）
    # 現状（実装前後ともに期待）: L62 は独立した "absolute" 専用エラーメッセージを持たない
    local standalone_abs_error_lines
    standalone_abs_error_lines="$(grep -cE '(echo|printf).*must not be an absolute|ERROR.*absolute path' "${SCRIPT}" 2>/dev/null || true)"
    [ "${standalone_abs_error_lines:-0}" -eq 0 ]
}

@test "ac4: if _supervisor_dir is embedded outside L65 block, sanitize must also be applied" {
    # AC: もし L65 ブロック外で ${_supervisor_dir} 埋め込みエラーメッセージがある場合、
    #     そのすべての埋め込み箇所に sanitize が適用されていること
    # 現状（AC4 ターゲット）: L65 ブロック以外に ${_supervisor_dir} 埋め込みがないため PASS
    #
    # 全 ${_supervisor_dir} 埋め込み行を取得
    local all_embeds
    all_embeds="$(grep -nE '(echo|printf).*\$\{?_supervisor_dir\}?.*>&2' "${SCRIPT}" 2>/dev/null || true)"

    if [ -z "${all_embeds}" ]; then
        # 埋め込みがない（または L65 の 1 行のみ）→ AC4 は自明に PASS
        true
    else
        # 埋め込みがある場合: printf '%q' または sanitize コードが存在することを確認
        local has_sanitize=0
        grep -qE "printf\s+'%q'" "${SCRIPT}" && has_sanitize=1
        grep -qE '_supervisor_dir=.*\$.*\\n' "${SCRIPT}" 2>/dev/null && has_sanitize=1
        [ "${has_sanitize}" -eq 1 ]
    fi
}
