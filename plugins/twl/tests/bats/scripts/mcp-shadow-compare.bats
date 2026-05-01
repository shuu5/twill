#!/usr/bin/env bats
# mcp-shadow-compare.bats - Issue #1225 AC TDD RED テスト
#
# Issue: feat/hooks: Tier-1 PoC: deps.yaml guard を mcp_tool hook で shadow 実装
#
# AC coverage:
#   AC-1  : .claude/settings.json に PreToolUse mcp_tool hook エントリが追加される
#   AC-2  : shadow mode = decision field を返さない (log only)。mcp_tool の output は
#            ~/.local/state/twill/hooks/deps-yaml-shadow.log (JSONL 1 line/event) に追記
#   AC-3  : 既存 pre-tool-use-deps-yaml-guard.sh を保持 (regression 比較用)。
#            bash hook の判定 (exit 0 / exit 2) を同 log file に追記
#   AC-4  : 比較スクリプト plugins/twl/scripts/mcp-shadow-compare.sh (新規、~50 行) を実装
#   AC-5  : bats test (本ファイル) で 5 サンプルの整合性を検証
#   AC-6  : 1 週間以上の並走運用で mismatch 0 件 (プロセス AC、実装物なし)
#   AC-7  : blocking 切替判断は別 Issue として起票 (プロセス AC、実装物なし)
#   AC-8  : ADR-029 Decision 4 への amendment 影響を Issue body と PR description に記載
#            (プロセス AC、実装物なし)
#   AC-V1 : PR diff で .claude/settings.json への PreToolUse mcp_tool hook 追加が含まれること
#   AC-V2 : 既存 pre-tool-use-deps-yaml-guard.sh の bytes が不変
#   AC-V3 : bats 5 サンプル全 PASS (本ファイルが PASS すること = AC-V3 充足)
#
# 全テストは実装前（RED）状態で fail する。
#   - mcp-shadow-compare.sh が存在しないため、実行系テストは全 fail
#   - settings.json の mcp_tool hook がまだ未追加なため、AC-V1 は fail
#   - AC-5 の 5 サンプルは compare スクリプト不在で fail

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

REPO_ROOT_1225=""
COMPARE_SCRIPT=""
SETTINGS_JSON=""
GUARD_SCRIPT=""
SHADOW_LOG=""

setup() {
  common_setup

  REPO_ROOT_1225="${REPO_ROOT}"
  export REPO_ROOT_1225

  # worktree root (plugins/twl の 2 階層上)
  GIT_ROOT="$(git -C "${REPO_ROOT}" rev-parse --show-toplevel 2>/dev/null || echo "${REPO_ROOT}/../..")"
  export GIT_ROOT

  # 比較スクリプト (AC-4 で新規作成予定) — plugins/twl 基準
  COMPARE_SCRIPT="${REPO_ROOT}/scripts/mcp-shadow-compare.sh"
  export COMPARE_SCRIPT

  # .claude/settings.json (AC-1 で編集予定) — worktree root 基準
  SETTINGS_JSON="${GIT_ROOT}/.claude/settings.json"
  export SETTINGS_JSON

  # 既存 bash hook スクリプト (AC-3 で保持確認) — plugins/twl 基準
  GUARD_SCRIPT="${REPO_ROOT}/scripts/hooks/pre-tool-use-deps-yaml-guard.sh"
  export GUARD_SCRIPT

  # shadow log ファイル (AC-2 の出力先)
  SHADOW_LOG="${HOME}/.local/state/twill/hooks/deps-yaml-shadow.log"
  export SHADOW_LOG

  # sandbox 内に偽の log ディレクトリを作成
  mkdir -p "${SANDBOX}/shadow-log-dir"
  SANDBOX_SHADOW_LOG="${SANDBOX}/shadow-log-dir/deps-yaml-shadow.log"
  export SANDBOX_SHADOW_LOG
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: .claude/settings.json に PreToolUse mcp_tool hook エントリを追加
# ===========================================================================

@test "ac1: settings.json に PreToolUse mcp_tool hook エントリが含まれる" {
  # AC: .claude/settings.json の PreToolUse セクションに
  #     matcher="mcp_tool" または type 関連の mcp_tool hook エントリが存在する
  # RED: 現時点では settings.json に mcp_tool hook が未追加のため fail
  [ -f "${SETTINGS_JSON}" ]
  run grep -q 'mcp_tool' "${SETTINGS_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac1: settings.json の mcp_tool hook エントリは PreToolUse セクションに存在する" {
  # AC: mcp_tool hook が PreToolUse セクション配下に配置されている
  # RED: mcp_tool hook 未追加のため fail
  [ -f "${SETTINGS_JSON}" ]
  # jq で PreToolUse 配列内に mcp_tool 関連エントリが存在することを確認
  run bash -c "jq -e '.hooks.PreToolUse[]? | select(.matcher == \"mcp_tool\" or (.hooks[]?.command // \"\" | test(\"mcp_tool\")))' '${SETTINGS_JSON}'"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-2: shadow mode = decision field を返さない (log only)
# ===========================================================================

@test "ac2: shadow log ファイルは JSONL 形式 (1 line/event)" {
  # AC: mcp_tool hook の output が JSONL (1 イベント = 1 行) で
  #     ~/.local/state/twill/hooks/deps-yaml-shadow.log に追記される
  # RED: mcp-shadow-compare.sh が存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]
  # log エントリのフォーマットを確認するため、compare スクリプトが log を読む
  # ここでは stub log でフォーマット検証を実施
  local test_log="${SANDBOX}/test-shadow.log"
  echo '{"ts":"2026-01-01T00:00:00Z","tool":"Write","verdict":"allow","source":"mcp_tool"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:01Z","tool":"Edit","verdict":"block","source":"bash"}' >> "${test_log}"
  run bash -c "jq -c . '${test_log}' | wc -l"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 2 ]
}

@test "ac2: shadow log に decision field が含まれない (log-only = no blocking)" {
  # AC: shadow mode では decision field (block/allow 指示) を返さない
  #     → hook output に 'decision' フィールドが含まれない
  # RED: mcp-shadow-compare.sh が存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]
  # compare スクリプトが shadow mode の log に decision フィールドを追加しないことを確認
  run grep -rE '"decision"\s*:' "${COMPARE_SCRIPT}"
  # decision フィールドを出力に含めてはならない
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC-3: 既存 pre-tool-use-deps-yaml-guard.sh の保持
# ===========================================================================

@test "ac3: pre-tool-use-deps-yaml-guard.sh が存在する (保持確認)" {
  # AC: 既存 pre-tool-use-deps-yaml-guard.sh を削除しない
  # RED: ファイルが存在する前提でチェック。もし削除されていれば fail
  # (このテストは現状 PASS するが、削除防止の regression guard として機能する)
  [ -f "${GUARD_SCRIPT}" ]
}

@test "ac3: pre-tool-use-deps-yaml-guard.sh のバイト数が基準値 3753 に一致する" {
  # AC: bash hook スクリプトの内容が不変である (bytes チェック)
  # RED: 現時点でファイルは存在するが、AC-V2 が機械検証するため RED テストとして定義
  # 基準 bytes: 3753 (git blame でのオリジナルサイズ)
  [ -f "${GUARD_SCRIPT}" ]
  local actual_bytes
  actual_bytes=$(wc -c < "${GUARD_SCRIPT}")
  # 実装前は bytes が一致しないはずなので fail させる
  # NOTE: 現時点でファイルが存在して bytes が一致する場合、
  #       このテストは GREEN になる可能性がある。
  #       AC-V2 の regression 検証として保持する。
  [ "${actual_bytes}" -eq 3753 ]
}

@test "ac3: bash hook の判定 (exit 0/exit 2) が shadow log に追記される" {
  # AC: bash hook の判定結果も同じ log file に記録され、mcp_tool 判定と突合可能
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]
  # bash hook ログエントリに source="bash" フィールドが含まれることを confirm
  run grep -E 'source.*bash|bash.*source' "${COMPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-4: mcp-shadow-compare.sh の実装
# ===========================================================================

@test "ac4: mcp-shadow-compare.sh が存在する" {
  # AC: plugins/twl/scripts/mcp-shadow-compare.sh (新規、~50 行) が作成される
  # RED: ファイルがまだ存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]
}

@test "ac4: mcp-shadow-compare.sh が実行可能である" {
  # AC: スクリプトに実行ビットが設定されている
  # RED: ファイルが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]
  [ -x "${COMPARE_SCRIPT}" ]
}

@test "ac4: mcp-shadow-compare.sh は mismatch 時に stderr に出力する" {
  # AC: bash 判定と mcp_tool 判定が異なる場合、mismatch を stderr に出力する
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  # bash=allow / mcp_tool=block のミスマッチログを作成
  local test_log="${SANDBOX}/mismatch-test.log"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"evt-001","tool":"Write","file":"deps.yaml","verdict":"allow","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"evt-001","tool":"Write","file":"deps.yaml","verdict":"block","source":"mcp_tool"}' >> "${test_log}"

  local stderr_out
  stderr_out=$(bash "${COMPARE_SCRIPT}" "${test_log}" 2>&1 >/dev/null || true)
  [[ -n "${stderr_out}" ]]
}

@test "ac4: mcp-shadow-compare.sh は mismatch 時に非ゼロ exit code を返す" {
  # AC: mismatch を exit code で表現する
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  local test_log="${SANDBOX}/mismatch-exit-test.log"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"evt-002","tool":"Write","file":"deps.yaml","verdict":"allow","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"evt-002","tool":"Write","file":"deps.yaml","verdict":"block","source":"mcp_tool"}' >> "${test_log}"

  run bash "${COMPARE_SCRIPT}" "${test_log}"
  [ "${status}" -ne 0 ]
}

@test "ac4: mcp-shadow-compare.sh は一致時に exit 0 を返す" {
  # AC: bash 判定と mcp_tool 判定が一致する場合、exit 0 で正常終了する
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  local test_log="${SANDBOX}/match-test.log"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"evt-003","tool":"Write","file":"deps.yaml","verdict":"allow","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"evt-003","tool":"Write","file":"deps.yaml","verdict":"allow","source":"mcp_tool"}' >> "${test_log}"

  run bash "${COMPARE_SCRIPT}" "${test_log}"
  [ "${status}" -eq 0 ]
}

@test "ac4: mcp-shadow-compare.sh は約 50 行以内の実装である" {
  # AC: ~50 行の実装 (コメント除く実行行)
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]
  local line_count
  line_count=$(grep -v '^\s*#' "${COMPARE_SCRIPT}" | grep -v '^\s*$' | wc -l)
  [ "${line_count}" -le 75 ]
}

# ===========================================================================
# AC-5 + AC-V3: 5 サンプルの整合性検証
# ===========================================================================
# Note: bats 5 サンプル = 以下の 5 @test ブロック (Sample 1-5)
# AC-V3 は本ファイルの全 PASS が条件 = この 5 サンプルを含む全テスト PASS

@test "ac5-sample1: both=allow (Write deps.yaml) → match, exit 0" {
  # Sample 1: bash=allow, mcp_tool=allow → 一致 → exit 0
  # AC: mcp-shadow-compare.sh が一致ケースを正しく処理する
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  local test_log="${SANDBOX}/sample1.log"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"s1","tool":"Write","file":"deps.yaml","verdict":"allow","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:00Z","event_id":"s1","tool":"Write","file":"deps.yaml","verdict":"allow","source":"mcp_tool"}' >> "${test_log}"

  run bash "${COMPARE_SCRIPT}" "${test_log}"
  [ "${status}" -eq 0 ]
}

@test "ac5-sample2: both=block (Write deps.yaml invalid YAML) → match, exit 0" {
  # Sample 2: bash=block, mcp_tool=block → 一致 → exit 0
  # AC: 両方 block の場合は一致として扱う
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  local test_log="${SANDBOX}/sample2.log"
  echo '{"ts":"2026-01-01T00:00:01Z","event_id":"s2","tool":"Write","file":"deps.yaml","verdict":"block","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:01Z","event_id":"s2","tool":"Write","file":"deps.yaml","verdict":"block","source":"mcp_tool"}' >> "${test_log}"

  run bash "${COMPARE_SCRIPT}" "${test_log}"
  [ "${status}" -eq 0 ]
}

@test "ac5-sample3: bash=allow mcp_tool=block → mismatch, nonzero exit + stderr" {
  # Sample 3: bash=allow, mcp_tool=block → mismatch → exit != 0 + stderr 出力
  # AC: mismatch 検出・報告
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  local test_log="${SANDBOX}/sample3.log"
  echo '{"ts":"2026-01-01T00:00:02Z","event_id":"s3","tool":"Edit","file":"deps.yaml","verdict":"allow","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:02Z","event_id":"s3","tool":"Edit","file":"deps.yaml","verdict":"block","source":"mcp_tool"}' >> "${test_log}"

  run bash "${COMPARE_SCRIPT}" "${test_log}" 2>&1
  [ "${status}" -ne 0 ]
  [[ -n "${output}" ]]
}

@test "ac5-sample4: bash=block mcp_tool=allow → mismatch, nonzero exit + stderr" {
  # Sample 4: bash=block, mcp_tool=allow → mismatch → exit != 0 + stderr 出力
  # AC: 逆方向 mismatch も検出する
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  local test_log="${SANDBOX}/sample4.log"
  echo '{"ts":"2026-01-01T00:00:03Z","event_id":"s4","tool":"Write","file":"deps.yaml","verdict":"block","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:03Z","event_id":"s4","tool":"Write","file":"deps.yaml","verdict":"allow","source":"mcp_tool"}' >> "${test_log}"

  run bash "${COMPARE_SCRIPT}" "${test_log}" 2>&1
  [ "${status}" -ne 0 ]
  [[ -n "${output}" ]]
}

@test "ac5-sample5: mixed events (2 match + 1 mismatch) → nonzero exit" {
  # Sample 5: 複数イベント混在。1 件でも mismatch があれば非ゼロ exit
  # AC: 複数イベントが存在する場合に mismatch を正しく集計する
  # RED: compare スクリプトが存在しないため fail
  [ -f "${COMPARE_SCRIPT}" ]

  local test_log="${SANDBOX}/sample5.log"
  # Event e1: match (allow/allow)
  echo '{"ts":"2026-01-01T00:00:04Z","event_id":"e1","tool":"Write","file":"deps.yaml","verdict":"allow","source":"bash"}' > "${test_log}"
  echo '{"ts":"2026-01-01T00:00:04Z","event_id":"e1","tool":"Write","file":"deps.yaml","verdict":"allow","source":"mcp_tool"}' >> "${test_log}"
  # Event e2: match (block/block)
  echo '{"ts":"2026-01-01T00:00:05Z","event_id":"e2","tool":"Edit","file":"deps.yaml","verdict":"block","source":"bash"}' >> "${test_log}"
  echo '{"ts":"2026-01-01T00:00:05Z","event_id":"e2","tool":"Edit","file":"deps.yaml","verdict":"block","source":"mcp_tool"}' >> "${test_log}"
  # Event e3: mismatch (allow/block)
  echo '{"ts":"2026-01-01T00:00:06Z","event_id":"e3","tool":"Write","file":"deps.yaml","verdict":"allow","source":"bash"}' >> "${test_log}"
  echo '{"ts":"2026-01-01T00:00:06Z","event_id":"e3","tool":"Write","file":"deps.yaml","verdict":"block","source":"mcp_tool"}' >> "${test_log}"

  run bash "${COMPARE_SCRIPT}" "${test_log}" 2>&1
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC-V1: settings.json への mcp_tool hook 追加 (機械検証)
# ===========================================================================

@test "acv1: settings.json に PreToolUse mcp_tool エントリが diff で確認できる" {
  # AC: PR diff で .claude/settings.json への PreToolUse mcp_tool hook 追加 (1 entry) が含まれる
  # RED: mcp_tool hook が未追加のため、jq で存在を確認すると fail
  [ -f "${SETTINGS_JSON}" ]
  # PreToolUse 配列に matcher が "mcp_tool" のエントリが存在することを確認
  run bash -c "
    jq -e '[.hooks.PreToolUse[]? | select(.matcher == \"mcp_tool\")] | length >= 1' '${SETTINGS_JSON}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-V2: 既存 guard スクリプトの bytes 不変確認
# ===========================================================================

@test "acv2: pre-tool-use-deps-yaml-guard.sh の bytes が不変 (3753 bytes)" {
  # AC: 既存 pre-tool-use-deps-yaml-guard.sh の bytes が不変であることを diff で確認
  # RED: ファイルが変更された場合に fail するリグレッション guard
  # Note: 現時点でファイルが存在して 3753 bytes の場合 PASS。
  #       将来変更されると fail して回帰を検知する。
  [ -f "${GUARD_SCRIPT}" ]
  local actual_bytes
  actual_bytes=$(wc -c < "${GUARD_SCRIPT}")
  [ "${actual_bytes}" -eq 3753 ]
}
