#!/usr/bin/env bats
# autopilot-phase-sanity.bats — static structure checks for Issue #139
#
# 受け入れ基準:
# - commands/autopilot-phase-sanity.md が存在する
# - 必須セクション（## 入力 / ## 処理ロジック (MUST) / ## 出力）を含む
# - gh issue view と gh issue close を呼び出す
# - skills/co-autopilot/SKILL.md Step 4 にサニティチェック呼び出しが追加されている
# - SKILL.md には処理詳細を記載せず、autopilot-phase-sanity.md を正典とする旨が明記されている
# - deps.yaml に atomic として登録されている (spawnable_by: [controller], can_spawn: [])
# - deps.yaml にプレースホルダ <実装時に解決> が残っていない
#
# Note: bats-support/bats-assert 非依存（環境にサブモジュール未初期化でも実行可能）。

setup() {
  REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SANITY_MD="$REPO_ROOT_REAL/commands/autopilot-phase-sanity.md"
  SKILL_MD="$REPO_ROOT_REAL/skills/co-autopilot/SKILL.md"
  DEPS_YAML="$REPO_ROOT_REAL/deps.yaml"
}

# ---------------------------------------------------------------------------
# Scenario: autopilot-phase-sanity.md prompt structure
# ---------------------------------------------------------------------------

@test "autopilot-phase-sanity.md exists" {
  [ -f "$SANITY_MD" ]
}

@test "autopilot-phase-sanity.md contains '## 入力' section" {
  grep -F "## 入力" "$SANITY_MD"
}

@test "autopilot-phase-sanity.md contains '## 処理ロジック (MUST)' section" {
  grep -F "## 処理ロジック (MUST)" "$SANITY_MD"
}

@test "autopilot-phase-sanity.md contains '## 出力' section" {
  grep -F "## 出力" "$SANITY_MD"
}

@test "autopilot-phase-sanity.md references 'gh issue view'" {
  grep -F "gh issue view" "$SANITY_MD"
}

@test "autopilot-phase-sanity.md references 'gh issue close'" {
  grep -F "gh issue close" "$SANITY_MD"
}

@test "autopilot-phase-sanity.md MUST NOT read PR diff or Issue body" {
  # 禁止事項セクションに PR diff/Issue body を読まない旨が明記されているか
  grep -F "PR diff" "$SANITY_MD"
  grep -F "Issue body" "$SANITY_MD"
}

# ---------------------------------------------------------------------------
# Scenario: SKILL.md Step 4 integration
# ---------------------------------------------------------------------------

@test "co-autopilot SKILL.md references autopilot-phase-sanity.md" {
  grep -F "commands/autopilot-phase-sanity.md" "$SKILL_MD"
}

@test "co-autopilot SKILL.md Step 4.5 exists" {
  grep -E "^### Step 4\.5" "$SKILL_MD"
}

@test "co-autopilot SKILL.md delegates sanity logic to atomic (single source of truth)" {
  # 「正典とする」記述があり、SKILL.md 側に詳細処理（gh issue close）を書いていない
  grep -F "正典" "$SKILL_MD"
  ! grep -F "gh issue close" "$SKILL_MD"
}

# ---------------------------------------------------------------------------
# Scenario: deps.yaml registration
# ---------------------------------------------------------------------------

@test "deps.yaml registers autopilot-phase-sanity as atomic" {
  grep -E "^  autopilot-phase-sanity:" "$DEPS_YAML"
}

@test "deps.yaml autopilot-phase-sanity has spawnable_by: [controller]" {
  awk '/^  autopilot-phase-sanity:/{flag=1; next} /^  autopilot-phase-postprocess:/{flag=0} flag' "$DEPS_YAML" | grep -F "spawnable_by: [controller]"
}

@test "deps.yaml autopilot-phase-sanity has can_spawn: []" {
  awk '/^  autopilot-phase-sanity:/{flag=1; next} /^  autopilot-phase-postprocess:/{flag=0} flag' "$DEPS_YAML" | grep -F "can_spawn: []"
}

@test "deps.yaml co-autopilot calls includes autopilot-phase-sanity" {
  awk '/^  co-autopilot:/,/^  co-issue:/' "$DEPS_YAML" | grep -F "atomic: autopilot-phase-sanity"
}

@test "deps.yaml has no <実装時に解決> placeholder" {
  ! grep -F "<実装時に解決>" "$DEPS_YAML"
}
