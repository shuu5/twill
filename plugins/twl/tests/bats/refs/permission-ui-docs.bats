#!/usr/bin/env bats
# permission-ui-docs.bats - AC1/AC3/AC5: permission UI 対応のドキュメント構造検証
#
# Issue #973: observer Auto レイヤーの permission UI menu 自動代理応答対応
#
# Coverage (RED phase — 未実装のため多くのテストが fail):
#   AC1: cld-observe-any emit_event に prompt_context / options フィールドが追加されている
#   AC2: intervene-auto.md に --pattern permission-ui-response が追加されている
#   AC3: soft-deny-rules.md が新設され schema_version/必須ルールを含む
#   AC5: monitor-channel-catalog / pitfalls-catalog / intervention-catalog / observation-pattern-catalog 更新

load '../helpers/common'

SESSION_SCRIPTS=""
SOFT_DENY_RULES=""
MONITOR_CATALOG=""
PITFALLS_CATALOG=""
INTERVENTION_CATALOG=""
OBSERVATION_CATALOG=""

setup() {
  common_setup
  SESSION_SCRIPTS="$(cd "$REPO_ROOT/../../plugins/session/scripts" && pwd)"
  SOFT_DENY_RULES="$REPO_ROOT/skills/su-observer/refs/soft-deny-rules.md"
  MONITOR_CATALOG="$REPO_ROOT/skills/su-observer/refs/monitor-channel-catalog.md"
  PITFALLS_CATALOG="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  INTERVENTION_CATALOG="$REPO_ROOT/refs/intervention-catalog.md"
  OBSERVATION_CATALOG="$REPO_ROOT/refs/observation-pattern-catalog.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: cld-observe-any emit_event 拡張
# ===========================================================================

@test "AC1: cld-observe-any が存在する" {
  [ -f "$SESSION_SCRIPTS/cld-observe-any" ] \
    || fail "cld-observe-any が存在しない: $SESSION_SCRIPTS/cld-observe-any"
}

@test "AC1: emit_event に prompt_context フィールドが追加されている (RED: 未実装)" {
  grep -q 'prompt_context' "$SESSION_SCRIPTS/cld-observe-any" \
    || fail "cld-observe-any の emit_event に prompt_context フィールドがない"
}

@test "AC1: emit_event に options フィールドが追加されている (RED: 未実装)" {
  grep -q '"options"' "$SESSION_SCRIPTS/cld-observe-any" \
    || fail "cld-observe-any の emit_event に options フィールドがない"
}

@test "AC1: PERMISSION-PROMPT emit_event が capture-pane を呼び出す (RED: 未実装)" {
  # prompt_context 取得のため capture-pane -S -50 を呼ぶことを確認
  grep -A5 'PERMISSION-PROMPT' "$SESSION_SCRIPTS/cld-observe-any" \
    | grep -q 'capture-pane' \
    || fail "PERMISSION-PROMPT 検知後の capture-pane 呼び出しがない"
}

# ===========================================================================
# AC3: soft-deny-rules.md 新設
# ===========================================================================

@test "AC3: soft-deny-rules.md が存在する (RED: 未作成)" {
  [ -f "$SOFT_DENY_RULES" ] \
    || fail "soft-deny-rules.md が存在しない: $SOFT_DENY_RULES"
}

@test "AC3: soft-deny-rules.md に schema_version: 1 が含まれる (RED: 未作成)" {
  grep -q 'schema_version: 1' "$SOFT_DENY_RULES" \
    || fail "soft-deny-rules.md に schema_version: 1 がない"
}

@test "AC3: code-from-external ルールが存在する (RED: 未作成)" {
  grep -q 'code-from-external' "$SOFT_DENY_RULES" \
    || fail "soft-deny-rules.md に code-from-external ルールがない"
}

@test "AC3: irreversible-local-destruction ルールが存在する (RED: 未作成)" {
  grep -q 'irreversible-local-destruction' "$SOFT_DENY_RULES" \
    || fail "soft-deny-rules.md に irreversible-local-destruction ルールがない"
}

@test "AC3: memory-poisoning ルールが存在する (RED: 未作成)" {
  grep -q 'memory-poisoning' "$SOFT_DENY_RULES" \
    || fail "soft-deny-rules.md に memory-poisoning ルールがない"
}

@test "AC3: secret-exfiltration ルールが存在する (RED: 未作成)" {
  grep -q 'secret-exfiltration' "$SOFT_DENY_RULES" \
    || fail "soft-deny-rules.md に secret-exfiltration ルールがない"
}

@test "AC3: privilege-escalation ルールが存在し layer: escalate である (RED: 未作成)" {
  grep -q 'privilege-escalation' "$SOFT_DENY_RULES" \
    || fail "soft-deny-rules.md に privilege-escalation ルールがない"
  grep -A5 'privilege-escalation' "$SOFT_DENY_RULES" \
    | grep -q 'layer: escalate' \
    || fail "privilege-escalation の layer が escalate でない"
}

@test "AC3: 全ルールに id/regex/layer/rationale フィールドが含まれる (RED: 未作成)" {
  grep -q '^\s*id:' "$SOFT_DENY_RULES" || fail "id フィールドがない"
  grep -q '^\s*regex:' "$SOFT_DENY_RULES" || fail "regex フィールドがない"
  grep -q '^\s*layer:' "$SOFT_DENY_RULES" || fail "layer フィールドがない"
  grep -q '^\s*rationale:' "$SOFT_DENY_RULES" || fail "rationale フィールドがない"
}

# ===========================================================================
# AC5: ドキュメント更新 — monitor-channel-catalog
# ===========================================================================

@test "AC5: monitor-channel-catalog.md が存在する" {
  [ -f "$MONITOR_CATALOG" ] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"
}

@test "AC5: PERMISSION-PROMPT の Layer が Auto に更新されている (RED: 未更新)" {
  # 旧: Layer = Confirm / 新: Layer = Auto (deny 該当時 Confirm/Escalate 昇格)
  grep -E 'PERMISSION-PROMPT.*Auto|PERMISSION-PROMPT.*Layer 0' "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md の PERMISSION-PROMPT Layer が Auto に更新されていない"
}

@test "AC5: monitor-channel-catalog cheat sheet が auto inject 記述に更新されている (RED: 未更新)" {
  grep -q 'soft_deny\|Layer 0 Auto inject\|自動 inject' "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md cheat sheet に auto inject 記述がない"
}

# ===========================================================================
# AC5: ドキュメント更新 — pitfalls-catalog §4.7
# ===========================================================================

@test "AC5: pitfalls-catalog.md が存在する" {
  [ -f "$PITFALLS_CATALOG" ] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"
}

@test "AC5: pitfalls-catalog §4.7 に soft_deny 記述が含まれる (RED: 未更新)" {
  # 旧: "ユーザー確認後に inject" / 新: "soft_deny rule 非該当時は Layer 0 Auto inject"
  grep -q 'soft_deny\|Layer 0 Auto\|soft-deny' "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md §4.7 に soft_deny 記述がない"
}

# ===========================================================================
# AC5: ドキュメント更新 — intervention-catalog パターン14
# ===========================================================================

@test "AC5: intervention-catalog.md が存在する" {
  [ -f "$INTERVENTION_CATALOG" ] \
    || fail "intervention-catalog.md が存在しない: $INTERVENTION_CATALOG"
}

@test "AC5: intervention-catalog にパターン 14 が追加されている (RED: 未追加)" {
  grep -qE 'パターン 14:|Pattern 14:' "$INTERVENTION_CATALOG" \
    || fail "intervention-catalog.md にパターン 14 がない"
}

@test "AC5: intervention-catalog パターン14 に permission-ui-auto-yes が含まれる (RED: 未追加)" {
  grep -q 'permission-ui-auto-yes' "$INTERVENTION_CATALOG" \
    || fail "intervention-catalog.md に permission-ui-auto-yes がない"
}

@test "AC5: intervention-catalog パターン14 が Layer 0 Auto セクションに含まれる (RED: 未追加)" {
  sed -n '/Layer 0.*Auto/,/^---$/p' "$INTERVENTION_CATALOG" \
    | grep -qE 'パターン 14|permission-ui-auto-yes' \
    || fail "パターン 14 が Layer 0 Auto セクションにない"
}

# ===========================================================================
# AC5: ドキュメント更新 — observation-pattern-catalog
# ===========================================================================

@test "AC5: observation-pattern-catalog.md が存在する" {
  [ -f "$OBSERVATION_CATALOG" ] \
    || fail "observation-pattern-catalog.md が存在しない: $OBSERVATION_CATALOG"
}

@test "AC5: observation-pattern-catalog に permission-ui-response sub-pattern が追加されている (RED: 未追加)" {
  grep -q 'permission-ui-response' "$OBSERVATION_CATALOG" \
    || fail "observation-pattern-catalog.md に permission-ui-response sub-pattern がない"
}

@test "AC5: observation-pattern-catalog に permission-ui > channel-input-wait 優先順位が明記されている (RED: 未追加)" {
  grep -q 'permission-ui-response > channel-input-wait\|permission-ui.*優先' "$OBSERVATION_CATALOG" \
    || fail "observation-pattern-catalog.md に permission-ui-response 優先順位記述がない"
}

# ===========================================================================
# AC2: intervene-auto.md に permission-ui-response パターンが追加されている
# ===========================================================================

@test "AC2: intervene-auto.md に --pattern permission-ui-response が追加されている (RED: 未追加)" {
  grep -q 'permission-ui-response' "$REPO_ROOT/commands/intervene-auto.md" \
    || fail "intervene-auto.md に permission-ui-response パターンがない"
}
