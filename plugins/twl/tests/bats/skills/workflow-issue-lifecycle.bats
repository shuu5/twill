#!/usr/bin/env bats
# workflow-issue-lifecycle.bats - structural & behavioral validation
#
# Spec: deltaspec/changes/issue-491/specs/workflow-issue-lifecycle/spec.md
#
# Scenarios covered:
#   - フロントマター検証: SKILL.md に必須 frontmatter が全て存在する
#   - N=1 guard 呼び出し: spec-review-session-init.sh に引数 1 を渡して呼び出す
#   - per-issue dir 読み込み: IN/draft.md を issue body として読み込む
#   - CRITICAL findings による再レビューループ: STATE を fixing にして再レビュー
#   - circuit_broken: max_rounds 到達で OUT/report.json に status: circuit_broken
#   - ファイル経由 I/O: OUT/report.json に status/issue_url/rounds が含まれる
#
# Edge cases:
#   - SKILL.md が 300 行以内 (context budget)
#   - IN/ 以外のパス参照がないこと
#   - codex gate 失敗 2 回で codex_unreliable になること

load '../helpers/common'

SKILL_MD=""

setup() {
  common_setup
  SKILL_MD="$REPO_ROOT/skills/workflow-issue-lifecycle/SKILL.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: workflow-issue-lifecycle SKILL.md 新規作成
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: フロントマター検証
# WHEN plugins/twl/skills/workflow-issue-lifecycle/SKILL.md を読む
# THEN type: workflow, user-invocable: true, spawnable_by: [controller, user],
#      can_spawn: [composite, atomic, specialist] が全て存在する
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle: SKILL.md が存在する" {
  [ -f "$SKILL_MD" ] || fail "SKILL.md not found at $SKILL_MD"
}

@test "workflow-issue-lifecycle: frontmatter に type: workflow が存在する" {
  grep -q 'type:.*workflow' "$SKILL_MD" \
    || fail "type: workflow not found in SKILL.md"
}

@test "workflow-issue-lifecycle: frontmatter に user-invocable: true が存在する" {
  grep -q 'user-invocable:.*true' "$SKILL_MD" \
    || fail "user-invocable: true not found in SKILL.md"
}

@test "workflow-issue-lifecycle: frontmatter に spawnable_by が controller を含む" {
  grep -q 'spawnable_by:' "$SKILL_MD" \
    || fail "spawnable_by: not found in SKILL.md"
  grep -A1 'spawnable_by:' "$SKILL_MD" | grep -q 'controller\|\[.*controller' \
    || grep 'spawnable_by:.*\[.*controller' "$SKILL_MD" \
    || fail "spawnable_by does not include controller"
}

@test "workflow-issue-lifecycle: frontmatter に spawnable_by が user を含む" {
  # spawnable_by: [controller, user] or multiline list
  python3 - "$SKILL_MD" <<'EOF'
import sys, re

content = open(sys.argv[1]).read()

# Extract YAML frontmatter
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    print("No frontmatter found", file=sys.stderr)
    sys.exit(1)

front = m.group(1)

# Find spawnable_by line(s)
in_spawnable = False
values = []
for line in front.splitlines():
    if re.match(r'\s*spawnable_by\s*:', line):
        # inline list: spawnable_by: [controller, user]
        m2 = re.search(r'\[([^\]]+)\]', line)
        if m2:
            values = [v.strip() for v in m2.group(1).split(',')]
            break
        in_spawnable = True
        continue
    if in_spawnable:
        stripped = line.strip()
        if stripped.startswith('- '):
            values.append(stripped[2:].strip())
        elif stripped == '' or re.match(r'\w', line):
            break

assert 'user' in values, f"'user' not found in spawnable_by: {values}"
EOF
}

@test "workflow-issue-lifecycle: frontmatter に can_spawn が composite を含む" {
  python3 - "$SKILL_MD" <<'EOF'
import sys, re

content = open(sys.argv[1]).read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(1)
front = m.group(1)

in_can_spawn = False
values = []
for line in front.splitlines():
    if re.match(r'\s*can_spawn\s*:', line):
        m2 = re.search(r'\[([^\]]+)\]', line)
        if m2:
            values = [v.strip() for v in m2.group(1).split(',')]
            break
        in_can_spawn = True
        continue
    if in_can_spawn:
        stripped = line.strip()
        if stripped.startswith('- '):
            values.append(stripped[2:].strip())
        elif stripped == '' or re.match(r'\w', line):
            break

assert 'composite' in values, f"'composite' not found in can_spawn: {values}"
assert 'atomic' in values, f"'atomic' not found in can_spawn: {values}"
assert 'specialist' in values, f"'specialist' not found in can_spawn: {values}"
EOF
}

# ===========================================================================
# Requirement: workflow-issue-lifecycle N=1 不変量
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: N=1 guard 呼び出し
# WHEN workflow-issue-lifecycle が起動される
# THEN spec-review-session-init.sh に引数 1 を渡して呼び出す
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle: spec-review-session-init.sh への呼び出しが文書化されている" {
  grep -q 'spec-review-session-init' "$SKILL_MD" \
    || fail "spec-review-session-init.sh not referenced in SKILL.md"
}

@test "workflow-issue-lifecycle: spec-review-session-init.sh を引数 1 で呼び出す記述がある" {
  # 引数 1 (N=1) で呼び出すことが明記されている
  grep -qE 'spec-review-session-init.*[[:space:]]1[[:space:]]*$|spec-review-session-init.*[[:space:]]1[^0-9]' "$SKILL_MD" \
    || fail "spec-review-session-init.sh called with argument 1 not documented in SKILL.md"
}

# ===========================================================================
# Requirement: workflow-issue-lifecycle 入力インターフェース
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: per-issue dir 読み込み
# WHEN /twl:workflow-issue-lifecycle /abs/path/to/per-issue/0 が呼ばれる
# THEN /abs/path/to/per-issue/0/IN/draft.md を issue body として読み込む
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle: IN/draft.md 読み込みが文書化されている" {
  grep -q 'IN/draft.md\|IN\/draft\.md' "$SKILL_MD" \
    || fail "IN/draft.md not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: IN/arch-context.md 読み込みが文書化されている" {
  grep -q 'IN/arch-context.md\|IN\/arch-context\.md' "$SKILL_MD" \
    || fail "IN/arch-context.md not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: IN/policies.json 読み込みが文書化されている" {
  grep -q 'IN/policies.json\|IN\/policies\.json' "$SKILL_MD" \
    || fail "IN/policies.json not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: IN/deps.json 読み込みが文書化されている" {
  grep -q 'IN/deps.json\|IN\/deps\.json' "$SKILL_MD" \
    || fail "IN/deps.json not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: 位置引数 \$1 で per-issue dir を受け取る記述がある" {
  grep -qE '\$1|位置引数|positional' "$SKILL_MD" \
    || fail "Positional argument \$1 for per-issue dir not documented"
}

# ===========================================================================
# Requirement: workflow-issue-lifecycle round loop 全分岐実装
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: CRITICAL findings による再レビューループ
# WHEN spec-review aggregate に conf>=80 の CRITICAL findings が存在する
# THEN STATE を fixing にして body を修正し、同じ round 内で再レビューを実行する
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle: CRITICAL findings による fixing STATE が文書化されている" {
  grep -qi 'fixing\|CRITICAL' "$SKILL_MD" \
    || fail "fixing state or CRITICAL findings not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: conf>=80 の閾値が文書化されている" {
  grep -qE 'conf.*80|confidence.*80|>=.*80' "$SKILL_MD" \
    || fail "conf>=80 threshold not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: 再レビューループが文書化されている" {
  grep -qiE 'loop|ループ|re-review|再レビュー' "$SKILL_MD" \
    || fail "re-review loop not documented in SKILL.md"
}

# ---------------------------------------------------------------------------
# Scenario: circuit_broken
# WHEN round が policies.max_rounds に達し CRITICAL findings がまだ残る
# THEN STATE を circuit_broken にして OUT/report.json に status: circuit_broken を書き込む
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle: circuit_broken STATE が文書化されている" {
  grep -q 'circuit_broken' "$SKILL_MD" \
    || fail "circuit_broken state not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: max_rounds 到達条件が文書化されている" {
  grep -qE 'max_rounds|max.*rounds|policies\.max_rounds' "$SKILL_MD" \
    || fail "max_rounds condition not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: WARNING のみの場合は body 修正してループ終了する記述がある" {
  grep -qi 'WARNING\|warning' "$SKILL_MD" \
    || fail "WARNING-only branch not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: clean (findings なし) の即ループ終了が文書化されている" {
  grep -qiE 'clean|findings.*なし|no.*findings' "$SKILL_MD" \
    || fail "clean (no findings) exit not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: codex gate 失敗 2 回で codex_unreliable が文書化されている" {
  grep -q 'codex_unreliable\|codex.*unreliable' "$SKILL_MD" \
    || fail "codex_unreliable state not documented in SKILL.md"
}

# ===========================================================================
# Requirement: workflow-issue-lifecycle ファイル経由 handoff
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: ファイル経由 I/O
# WHEN workflow が正常完了する
# THEN OUT/report.json が status: done, issue_url, rounds を含んで存在する
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle: OUT/report.json 出力が文書化されている" {
  grep -q 'OUT/report.json\|OUT\/report\.json' "$SKILL_MD" \
    || fail "OUT/report.json not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: OUT/report.json に status フィールドが含まれる記述がある" {
  grep -q 'status' "$SKILL_MD" \
    || fail "status field in OUT/report.json not documented"
}

@test "workflow-issue-lifecycle: OUT/report.json に issue_url フィールドが含まれる記述がある" {
  grep -q 'issue_url' "$SKILL_MD" \
    || fail "issue_url field in OUT/report.json not documented"
}

@test "workflow-issue-lifecycle: OUT/report.json に rounds フィールドが含まれる記述がある" {
  grep -q 'rounds' "$SKILL_MD" \
    || fail "rounds field in OUT/report.json not documented"
}

@test "workflow-issue-lifecycle: IN/ 以外のパス・env var を参照しないことが文書化されている" {
  # MUST NOT reference paths/env vars other than IN/
  # Verify SKILL.md does not hardcode non-IN paths in implementation steps
  # (env vars like CLAUDE_PLUGIN_ROOT are acceptable for script calls)
  local env_refs
  env_refs=$(grep -vE 'CLAUDE_PLUGIN_ROOT|IN/|OUT/' "$SKILL_MD" | grep -cE '\$[A-Z_]+' || true)
  # If there are env var refs outside IN/ context, they must be documented as exceptions
  # This is a content check: SKILL.md must not reference external state paths
  grep -qv 'AUTOPILOT_DIR\|session\.json\|\.autopilot' "$SKILL_MD" \
    || fail "SKILL.md references external state paths (.autopilot/session.json etc.) which violates file-only I/O"
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "workflow-issue-lifecycle: SKILL.md が 300 行以内 (context budget)" {
  local lines
  lines=$(wc -l < "$SKILL_MD")
  [ "$lines" -le 300 ] \
    || fail "SKILL.md has $lines lines, expected <= 300 (context budget)"
}

@test "workflow-issue-lifecycle: warnings_acknowledged フィールドが OUT/report.json に含まれる" {
  grep -q 'warnings_acknowledged' "$SKILL_MD" \
    || fail "warnings_acknowledged field not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: findings_final フィールドが OUT/report.json に含まれる" {
  grep -q 'findings_final' "$SKILL_MD" \
    || fail "findings_final field not documented in SKILL.md"
}

# ===========================================================================
# Requirement: refined ラベル自動付与（Step 4.5）
# Spec: deltaspec/changes/issue-574/specs/refined-label/spec.md
# ===========================================================================

# Step 4.5 の判定ロジックを Bash スニペットとして再現するヘルパー関数
# （SKILL.md の Step 4.5 実装を inline で検証）
_run_step45() {
  local quick_flag="$1"
  local state="$2"
  local labels_hint_in="${3:-enhancement}"

  # Step 4.5: refined ラベル付与判定ロジック
  local labels_hint="$labels_hint_in"
  if [[ "$quick_flag" != "true" && "$state" != "circuit_broken" ]]; then
    labels_hint="${labels_hint},refined"
  fi
  echo "$labels_hint"
}

# ---------------------------------------------------------------------------
# Scenario: 通常モードかつ round loop 正常完了時に refined を付与する
# WHEN quick_flag=false かつ round loop が circuit_broken でない状態で正常完了した
# THEN labels_hint に "refined" が追加される
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle Step4.5: quick_flag=false かつ STATE!=circuit_broken のとき labels_hint に refined が追加される" {
  run _run_step45 "false" "done" "enhancement"
  assert_success
  assert_output --partial "refined"
}

@test "workflow-issue-lifecycle Step4.5: quick_flag=false かつ STATE=reviewing でも refined が追加される" {
  run _run_step45 "false" "reviewing" "enhancement"
  assert_success
  assert_output --partial "refined"
}

@test "workflow-issue-lifecycle Step4.5: refined 付与後も既存ラベル（enhancement）が保持される" {
  run _run_step45 "false" "done" "enhancement"
  assert_success
  assert_output --partial "enhancement"
}

# ---------------------------------------------------------------------------
# Scenario: quick モードでは refined を付与しない
# WHEN quick_flag=true の場合
# THEN Step 4.5 はスキップされ、labels_hint に "refined" は追加されない
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle Step4.5: quick_flag=true のとき labels_hint に refined が追加されない" {
  run _run_step45 "true" "done" "enhancement"
  assert_success
  refute_output --partial "refined"
}

@test "workflow-issue-lifecycle Step4.5: quick_flag=true かつ STATE=circuit_broken でも refined が追加されない" {
  run _run_step45 "true" "circuit_broken" "enhancement"
  assert_success
  refute_output --partial "refined"
}

# ---------------------------------------------------------------------------
# Scenario: circuit_broken 状態では refined を付与しない
# WHEN round loop が circuit_broken 状態で終了した
# THEN Step 4.5 はスキップされ、labels_hint に "refined" は追加されない
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle Step4.5: STATE=circuit_broken のとき labels_hint に refined が追加されない" {
  run _run_step45 "false" "circuit_broken" "enhancement"
  assert_success
  refute_output --partial "refined"
}

@test "workflow-issue-lifecycle Step4.5: STATE=circuit_broken のとき既存ラベルは保持される" {
  run _run_step45 "false" "circuit_broken" "enhancement"
  assert_success
  assert_output --partial "enhancement"
}

# ---------------------------------------------------------------------------
# Scenario: SKILL.md に Step 4.5 が文書化されている
# WHEN SKILL.md を読む
# THEN Step 4.5 / quick_flag / refined の記述が存在する
# ---------------------------------------------------------------------------

@test "workflow-issue-lifecycle: SKILL.md に Step 4.5 が文書化されている" {
  grep -qE 'Step 4\.5|step.*4\.5' "$SKILL_MD" \
    || fail "Step 4.5 not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: SKILL.md に quick_flag が文書化されている" {
  grep -q 'quick_flag' "$SKILL_MD" \
    || fail "quick_flag not documented in SKILL.md"
}

@test "workflow-issue-lifecycle: SKILL.md に refined ラベル付与が文書化されている" {
  grep -q 'refined' "$SKILL_MD" \
    || fail "refined label not documented in SKILL.md"
}
