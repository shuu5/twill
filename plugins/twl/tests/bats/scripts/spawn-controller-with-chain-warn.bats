#!/usr/bin/env bats
# spawn-controller-with-chain-warn.bats - Issue #942 TDD RED フェーズ用テスト
#
# Generated from: Issue #942 (design su-observer skill spawn-control)
#
# Coverage:
#   S1: spawn-controller.sh co-autopilot --with-chain --issue N 実行時の WARN 出力と exit 0 維持
#   S2: pitfalls-catalog.md §13.5 追加（with-chain skill bypass pitfall 記載）
#   S3: ADR-026-spawn-syntax-discipline.md 新規作成
#   S4: su-observer/SKILL.md L105-125 節への MUST 追加
#
# 全テストは実装前の RED 状態で fail することを意図している。
# 実装後に GREEN になること。
#
# Setup pattern: spawn-controller-with-chain.bats の AUTOPILOT_LAUNCH_SH mock を流用。

load '../helpers/common'

SPAWN_CONTROLLER=""
AUTOPILOT_LAUNCH_ARGS_LOG=""
CLD_SPAWN_ARGS_LOG=""
PITFALLS_CATALOG=""
SKILL_MD=""
ADR_026=""

setup() {
  common_setup

  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  AUTOPILOT_LAUNCH_ARGS_LOG="$SANDBOX/autopilot-launch-args.log"
  export AUTOPILOT_LAUNCH_ARGS_LOG

  CLD_SPAWN_ARGS_LOG="$SANDBOX/cld-spawn-args.log"
  export CLD_SPAWN_ARGS_LOG

  PITFALLS_CATALOG="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
  ADR_026="$REPO_ROOT/architecture/decisions/ADR-026-spawn-syntax-discipline.md"

  # autopilot-launch.sh mock: 引数を記録して正常終了
  cat > "$STUB_BIN/autopilot-launch.sh" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${AUTOPILOT_LAUNCH_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$STUB_BIN/autopilot-launch.sh"

  # cld-spawn mock: 引数を記録して正常終了
  cat > "$STUB_BIN/cld-spawn" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CLD_SPAWN_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$STUB_BIN/cld-spawn"

  # Issue #1644: CLD_SPAWN_OVERRIDE env var で mock 切り替え
  cat > "$SANDBOX/run-spawn-controller.sh" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
_DEFAULT_AUTOPILOT_LAUNCH="$STUB_BIN/autopilot-launch.sh"
_AUTOPILOT_LAUNCH_SH="\${AUTOPILOT_LAUNCH_SH:-\$_DEFAULT_AUTOPILOT_LAUNCH}"
exec env CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
  AUTOPILOT_LAUNCH_SH="\$_AUTOPILOT_LAUNCH_SH" \
  SKIP_PARALLEL_CHECK=\${SKIP_PARALLEL_CHECK:-1} \
  SKIP_PARALLEL_REASON="\${SKIP_PARALLEL_REASON:-bats test}" \
  bash "$SPAWN_CONTROLLER" "\$@"
WRAPPER
  chmod +x "$SANDBOX/run-spawn-controller.sh"

  # テスト用 prompt ファイル
  echo "context: issue #942 spawn-control test" > "$SANDBOX/prompt.txt"
}

teardown() {
  common_teardown
}

# ===========================================================================
# S1: spawn-controller.sh --with-chain 実行時の WARN 出力
# AC: `spawn-controller.sh co-autopilot <p> --with-chain --issue N` 実行時、
#     stderr に `WARN:` 接頭辞を持つメッセージが出力され、exit code は 0 を維持
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: --with-chain --issue N 実行時に exit code 0 を維持する
# WHEN: spawn-controller.sh co-autopilot <prompt> --with-chain --issue 942 を実行
# THEN: exit code が 0（WARN 出力後も autopilot-launch.sh 委譲継続）
# ---------------------------------------------------------------------------

@test "S1: --with-chain --issue N は exit code 0 を維持する" {
  # AC: exit code は 0 を維持（autopilot-launch.sh 委譲継続）
  # RED: WARN 実装前は exit code が変わらないか、WARN 出力が存在しない
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain --issue 942

  assert_success
  # WARN が出力されていることを stderr で確認
  # run は stdout+stderr を $output にまとめるため --partial で確認
  assert_output --partial "WARN:"
}

# ---------------------------------------------------------------------------
# Scenario: WARN メッセージに "skill bypass" キーワードが含まれる
# WHEN: spawn-controller.sh co-autopilot <prompt> --with-chain --issue 942 を実行
# THEN: stderr に "skill bypass" を含む WARN メッセージが出力される
# ---------------------------------------------------------------------------

@test "S1: WARN メッセージに 'skill bypass' キーワードが含まれる" {
  # AC: WARN message に (a) `skill bypass` キーワードを含む
  # RED: WARN 未実装のため fail する
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain --issue 942

  assert_success
  assert_output --partial "skill bypass"
}

# ---------------------------------------------------------------------------
# Scenario: WARN メッセージに正規運用例が含まれる
# WHEN: spawn-controller.sh co-autopilot <prompt> --with-chain --issue 942 を実行
# THEN: stderr に "spawn-controller.sh co-autopilot <prompt>" 形式の正規運用例が含まれる
# ---------------------------------------------------------------------------

@test "S1: WARN メッセージに正規運用例 'spawn-controller.sh co-autopilot' が含まれる" {
  # AC: WARN message に (b) 正規運用例 spawn-controller.sh co-autopilot <prompt>（option 無し）を含む
  # RED: WARN 未実装のため fail する
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain --issue 942

  assert_success
  assert_output --partial "正規運用"
}

# ---------------------------------------------------------------------------
# Scenario: WARN メッセージに pitfalls-catalog.md §13.5 参照リンクが含まれる
# WHEN: spawn-controller.sh co-autopilot <prompt> --with-chain --issue 942 を実行
# THEN: stderr に "pitfalls-catalog.md §13.5" が含まれる
# ---------------------------------------------------------------------------

@test "S1: WARN メッセージに 'pitfalls-catalog.md §13.5' 参照リンクが含まれる" {
  # AC: WARN message に (c) `pitfalls-catalog.md §13.5` 参照リンクを含む
  # RED: WARN 未実装のため fail する
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain --issue 942

  assert_success
  assert_output --partial "pitfalls-catalog.md §13.5"
}

# ===========================================================================
# S2: pitfalls-catalog.md §13.5 の追加確認
# AC: §13.5 行が追加され、1 Issue = 1 Pilot 錯覚 pitfall が明記されている
#     §13 冒頭の経路 table に A': --with-chain 行が追加されている
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: §13.5 セクションが pitfalls-catalog.md に存在する
# WHEN: pitfalls-catalog.md を参照する
# THEN: "13.5" 節が存在する
# ---------------------------------------------------------------------------

@test "S2: pitfalls-catalog.md に §13.5 セクションが存在する" {
  # AC: pitfalls-catalog.md §13.5 行が追加されている
  # RED: §13.5 未追加のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"
  grep -qE '13\.5' "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md に '13.5' が存在しない（§13.5 未追加）"
}

# ---------------------------------------------------------------------------
# Scenario: §13.5 に "1 Issue = 1 Pilot" 錯覚の pitfall が明記されている
# WHEN: pitfalls-catalog.md §13.5 を参照する
# THEN: observer が --with-chain --issue N で Issue 毎に Worker を直接 spawn する pitfall が明記
# ---------------------------------------------------------------------------

@test "S2: §13.5 に 'skill bypass' または '--with-chain' 誤用 pitfall が明記されている" {
  # AC: observer が --with-chain --issue N で Issue 毎に Worker を直接 spawn pitfall 明記
  # RED: §13.5 未追加のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"
  # §13.5 前後のコンテキストで --with-chain または skill bypass を確認
  sed -n '/13\.5/,/13\.[6-9]\|## 14\./p' "$PITFALLS_CATALOG" \
    | grep -qE 'with-chain|skill bypass|1 Issue.*1 Pilot|1.*Pilot.*錯覚' \
    || fail "§13.5 に with-chain skill bypass pitfall が明記されていない"
}

# ---------------------------------------------------------------------------
# Scenario: §13 冒頭の経路 table に A': --with-chain 行が追加されている
# WHEN: pitfalls-catalog.md §13 の経路 table を参照する
# THEN: "A'" または "--with-chain" を含む行が経路 table に存在する
# ---------------------------------------------------------------------------

@test "S2: §13 経路 table に A': --with-chain 行が追加されている" {
  # AC: §13 冒頭の経路 table に「A': spawn-controller.sh --with-chain（skill bypass 副作用）」行追加
  # RED: 未追加のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"
  sed -n '/^## 13\./,/^## 14\./p' "$PITFALLS_CATALOG" \
    | grep -qE "A'|A'" \
    || fail "§13 経路 table に A' 行が存在しない"
}

# ===========================================================================
# S3: ADR-026-spawn-syntax-discipline.md の新規作成確認
# AC: Context に 14 PR skip incident、Decision に WARN/exit 0 不変、
#     Consequences に rename/deprecate は Phase AB 以降 を記載
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: ADR-026 ファイルが存在する
# WHEN: architecture/decisions/ADR-026-spawn-syntax-discipline.md を参照する
# THEN: ファイルが存在する
# ---------------------------------------------------------------------------

@test "S3: ADR-026-spawn-syntax-discipline.md が存在する" {
  # AC: ADR-026-spawn-syntax-discipline.md が新規作成されている
  # RED: 未作成のため fail する
  [[ -f "$ADR_026" ]] \
    || fail "ADR-026-spawn-syntax-discipline.md が存在しない: $ADR_026"
}

# ---------------------------------------------------------------------------
# Scenario: ADR-026 の Context に 14 PR skip incident (#923/#925-#937) が記載されている
# WHEN: ADR-026 を参照する
# THEN: Context セクションに PR skip incident と issue 番号が含まれる
# ---------------------------------------------------------------------------

@test "S3: ADR-026 の Context に 14 PR skip incident が記載されている" {
  # AC: Context に 14 PR skip incident (#923/#925-#937) を記載
  # RED: ADR-026 未作成のため fail する
  [[ -f "$ADR_026" ]] \
    || fail "ADR-026-spawn-syntax-discipline.md が存在しない: $ADR_026"
  grep -qiE 'Context|コンテキスト' "$ADR_026" \
    || fail "ADR-026 に Context セクションが存在しない"
  grep -qE '#923|#925|#937|14 PR|PR.*skip' "$ADR_026" \
    || fail "ADR-026 の Context に 14 PR skip incident が記載されていない"
}

# ---------------------------------------------------------------------------
# Scenario: ADR-026 の Decision に WARN で誤用防止・exit code 不変が記載されている
# WHEN: ADR-026 を参照する
# THEN: Decision セクションに WARN および exit code 不変が含まれる
# ---------------------------------------------------------------------------

@test "S3: ADR-026 の Decision に WARN 誤用防止と exit code 不変が記載されている" {
  # AC: Decision に「WARN で誤用防止、後方互換のため exit code 不変」を記載
  # RED: ADR-026 未作成のため fail する
  [[ -f "$ADR_026" ]] \
    || fail "ADR-026-spawn-syntax-discipline.md が存在しない: $ADR_026"
  grep -qiE 'Decision|決定|決断' "$ADR_026" \
    || fail "ADR-026 に Decision セクションが存在しない"
  grep -qE 'WARN|exit.*0|exit code' "$ADR_026" \
    || fail "ADR-026 の Decision に WARN/exit code が記載されていない"
}

# ---------------------------------------------------------------------------
# Scenario: ADR-026 の Consequences に rename/deprecate は Phase AB 以降が記載されている
# WHEN: ADR-026 を参照する
# THEN: Consequences セクションに "Phase AB" または "rename/deprecate" が含まれる
# ---------------------------------------------------------------------------

@test "S3: ADR-026 の Consequences に rename/deprecate は Phase AB 以降が記載されている" {
  # AC: Consequences に「rename/deprecate は Phase AB 以降で再評価（本 Issue scope 外）」を記載
  # RED: ADR-026 未作成のため fail する
  [[ -f "$ADR_026" ]] \
    || fail "ADR-026-spawn-syntax-discipline.md が存在しない: $ADR_026"
  grep -qiE 'Consequences|結果|影響' "$ADR_026" \
    || fail "ADR-026 に Consequences セクションが存在しない"
  grep -qE 'Phase AB|rename|deprecate' "$ADR_026" \
    || fail "ADR-026 の Consequences に rename/deprecate Phase AB 以降が記載されていない"
}

# ===========================================================================
# S4: su-observer/SKILL.md L105-125 節への MUST 追加確認
# AC: 「1 Pilot = 複数 Issue が正規運用」MUST と
#     「--with-chain --issue N 単独使用禁止」MUST が追加されている
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: SKILL.md に「1 Pilot = 複数 Issue が正規運用」MUST が存在する
# WHEN: su-observer/SKILL.md の L105-125 節を参照する
# THEN: "1 Pilot" と "複数 Issue" および "MUST" が同節内に存在する
# ---------------------------------------------------------------------------

@test "S4: SKILL.md に '1 Pilot = 複数 Issue が正規運用' MUST が追加されている" {
  # AC: SKILL.md L105-125 節に「1 Pilot = 複数 Issue が正規運用」MUST 追加
  # RED: 未追加のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"
  # L105-125 のコンテキスト前後（controller spawn セクション）で確認
  sed -n '/controller spawn が必要な場合/,/spawn プロンプトの文脈包含/p' "$SKILL_MD" \
    | grep -qE '1 Pilot.*複数.*Issue|複数.*Issue.*1 Pilot|1 Pilot = 複数' \
    || fail "SKILL.md の controller spawn 節に '1 Pilot = 複数 Issue が正規運用' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: SKILL.md に「--with-chain --issue N 単独使用禁止」MUST が存在する
# WHEN: su-observer/SKILL.md の L105-125 節を参照する
# THEN: "--with-chain --issue N" および禁止を示す記述が同節内に存在する
# ---------------------------------------------------------------------------

@test "S4: SKILL.md に '--with-chain --issue N 単独使用禁止' MUST が追加されている" {
  # AC: SKILL.md L105-125 節に「--with-chain --issue N 単独使用禁止」MUST 追加
  # RED: 未追加のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"
  sed -n '/controller spawn が必要な場合/,/spawn プロンプトの文脈包含/p' "$SKILL_MD" \
    | grep -qE 'with-chain.*issue.*禁止|with-chain.*単独.*禁止|禁止.*with-chain' \
    || fail "SKILL.md の controller spawn 節に '--with-chain --issue N 単独使用禁止' が存在しない"
}
