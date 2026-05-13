#!/usr/bin/env bats
# vocabulary-audit.bats — EXP-038: forbidden 語 word boundary 検出 + false positive 抑制
#
# 検証内容 (registry.yaml §5 vocabulary_forbidden_use rule の動作):
#   - 真陽性: 単独 forbidden 語の検出 (orchestrator / worker / pilot / state etc.)
#   - 偽陽性抑制:
#     1. backtick 内引用: `pilot` → 除外
#     2. 「旧」「廃止予定」line skip: 旧 pilot → 除外
#     3. migration-stage: `Phase 1 PoC` → backtick 除去で副次対応
#     4. compound canonical entity: co-autopilot → 除外 (registry.yaml glossary に登録)
#
# 検証手法: tmpfile fixture を作成し、Python 正規表現で audit ロジックを再現
# (twl-audit-vocabulary.sh は実 plugins/twl scan するため、unit-test 的に分離)

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT
  REGISTRY_FILE="${REPO_ROOT}/registry.yaml"
  export REGISTRY_FILE

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}" 2>/dev/null || true
}

_assert_detection() {
  # _assert_detection <fixture_file> <forbidden_word> <expected: hit|miss>
  local fixture="$1"
  local word="$2"
  local expected="$3"
  local result
  result=$(python3 -c "
import re, sys
with open('$fixture') as f:
    content = f.read()
# backtick 除去 (false positive 抑制 1)
cleaned = re.sub(r'\`[^\`\n]*\`', '', content)
# canonical entity を集める (compound exclusion 用、最小 mock)
canonical_names = {'co-autopilot'}
pattern = re.compile(r'\b' + re.escape('$word') + r'\b')
compound_pattern = re.compile(r'\b([\w]+(?:-[\w]+)*-' + re.escape('$word') + r')\b')
hit = False
for line in cleaned.splitlines():
    # 「旧」「廃止予定」 line skip (false positive 抑制 2)
    if '旧' in line or '廃止予定' in line:
        continue
    if not pattern.search(line):
        continue
    compound_matches = compound_pattern.findall(line)
    if compound_matches:
        excluded = [m for m in compound_matches if m in canonical_names]
        if excluded:
            tmp = line
            for c in excluded:
                tmp = tmp.replace(c, '')
            if not pattern.search(tmp):
                continue
    hit = True
    break
print('hit' if hit else 'miss')
")
  [ "$result" = "$expected" ] || {
    echo "FAIL: word='$word', expected=$expected, got=$result, fixture=$fixture"
    cat "$fixture"
    return 1
  }
}

@test "vocabulary-audit: registry.yaml に glossary.phaser.forbidden 'pilot' が登録されている (EXP-038 前提)" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
phaser = data.get('glossary', {}).get('phaser', {})
forbidden = phaser.get('forbidden', [])
assert 'pilot' in forbidden, f'pilot not in phaser.forbidden: {forbidden}'
sys.exit(0)
"
}

@test "vocabulary-audit: 真陽性 - 単独 'pilot' 使用を検出" {
  local fix="${TMPDIR_TEST}/positive-pilot.md"
  echo "The pilot handles the request." > "$fix"
  _assert_detection "$fix" "pilot" "hit"
}

@test "vocabulary-audit: 真陽性 - 単独 'orchestrator' 使用を検出" {
  local fix="${TMPDIR_TEST}/positive-orch.md"
  echo "The orchestrator is responsible." > "$fix"
  _assert_detection "$fix" "orchestrator" "hit"
}

@test "vocabulary-audit: 真陽性 - 単独 'worker' 使用を検出" {
  local fix="${TMPDIR_TEST}/positive-worker.md"
  echo "The worker executes commands." > "$fix"
  _assert_detection "$fix" "worker" "hit"
}

@test "vocabulary-audit: 真陽性 - 単独 'state' 使用を検出" {
  local fix="${TMPDIR_TEST}/positive-state.md"
  echo "Update the state field." > "$fix"
  _assert_detection "$fix" "state" "hit"
}

@test "vocabulary-audit: 偽陽性抑制 - backtick 内 \`pilot\` は除外" {
  local fix="${TMPDIR_TEST}/negative-backtick.md"
  echo "Use \`pilot\` as the canonical reference." > "$fix"
  _assert_detection "$fix" "pilot" "miss"
}

@test "vocabulary-audit: 偽陽性抑制 - 「旧 pilot」 line は除外" {
  local fix="${TMPDIR_TEST}/negative-old.md"
  echo "旧 pilot は廃止予定" > "$fix"
  _assert_detection "$fix" "pilot" "miss"
}

@test "vocabulary-audit: 偽陽性抑制 - migration-stage \`Phase 1 PoC\` 内の phase は除外" {
  local fix="${TMPDIR_TEST}/negative-phase.md"
  echo "Currently in \`Phase 1 PoC\` stage." > "$fix"
  _assert_detection "$fix" "phase" "miss"
}

@test "vocabulary-audit: 偽陽性抑制 - compound canonical 'co-autopilot' 内の pilot は除外" {
  local fix="${TMPDIR_TEST}/negative-compound.md"
  echo "Launch co-autopilot to process." > "$fix"
  _assert_detection "$fix" "pilot" "miss"
}
