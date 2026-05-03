#!/usr/bin/env bats
# issue-1322-mode-strict-prompt.bats
# AC-4: regression bats — keyword 経路で menu skip が確認できること
#
# Tests FAIL (RED) until co-self-improve/SKILL.md is updated to strict mode detection.
# Issue #1322: feat(co-self-improve): mode 補完 strict (prompt 完備時 menu skip)

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-1: co-self-improve/SKILL.md L41,57 mode 判定 strict 化
# spawn 受取手順 section の skip 条件が明示的なキーワードで書かれていること
# ---------------------------------------------------------------------------

@test "ac1: spawn 受取手順 skip condition explicitly references mode keywords" {
  # AC-1: L41 は vague な「情報が含まれている」ではなく、
  # scenario-run / retrospect / test-project-manage の明示的なキーワード条件を持つこと
  # RED: 現状 L41 は「情報が含まれている」と vague であり、キーワード名が skip 条件として出現しない
  local skill="$REPO_ROOT/skills/co-self-improve/SKILL.md"
  grep -q 'scenario-run.*スキップ\|retrospect.*スキップ\|test-project-manage.*スキップ' "$skill"
}

@test "ac1: Step 0 fallback condition uses explicit judgment-failure language" {
  # AC-1: L57「情報が含まれない場合のみ」→「判定不可の場合のみ」等の明示表現に strict 化
  # RED: 現状「情報が含まれない」は vague であり「判定不可」という語が不在
  local skill="$REPO_ROOT/skills/co-self-improve/SKILL.md"
  grep -q '判定不可' "$skill"
}

# ---------------------------------------------------------------------------
# AC-2: prompt に scenario-run/retrospect/test-project-manage keyword 含む → menu skip
# ---------------------------------------------------------------------------

@test "ac2: scenario-run keyword in prompt triggers menu skip" {
  # AC-2: prompt に scenario-run が含まれる → menu skip であることが SKILL.md に明示
  # RED: 現状 scenario-run と スキップ が同一文脈（同一行）に出現しない
  local skill="$REPO_ROOT/skills/co-self-improve/SKILL.md"
  grep -q 'scenario-run.*スキップ\|スキップ.*scenario-run' "$skill"
}

@test "ac2: retrospect keyword in prompt triggers menu skip" {
  # AC-2: prompt に retrospect が含まれる → menu skip であることが明示
  # RED: 現状 retrospect と スキップ が spawn 受取手順 section に出現しない
  local skill="$REPO_ROOT/skills/co-self-improve/SKILL.md"
  grep -q 'retrospect.*スキップ\|スキップ.*retrospect' "$skill"
}

@test "ac2: test-project-manage keyword in prompt triggers menu skip" {
  # AC-2: prompt に test-project-manage が含まれる → menu skip であることが明示
  # RED: 現状 test-project-manage と スキップ が同一文脈に出現しない
  local skill="$REPO_ROOT/skills/co-self-improve/SKILL.md"
  grep -q 'test-project-manage.*スキップ\|スキップ.*test-project-manage' "$skill"
}

# ---------------------------------------------------------------------------
# AC-3: 不完全時 (judgment 不可) のみ既存 menu 表示
# ---------------------------------------------------------------------------

@test "ac3: AskUserQuestion menu shown only when mode judgment is not possible" {
  # AC-3: キーワード不在で判定不可の場合のみ AskUserQuestion で menu 表示することが明示
  # RED: 現状「情報が含まれない場合のみ」は vague で「判定不可」等の明示表現が不在
  local skill="$REPO_ROOT/skills/co-self-improve/SKILL.md"
  grep -qE '判定不可|キーワード.*(不完全|なし|不在)' "$skill"
}
