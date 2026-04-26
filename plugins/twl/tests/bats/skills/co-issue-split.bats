#!/usr/bin/env bats
# co-issue-split.bats - TDD RED tests for Issue #983 co-issue SKILL.md split

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: controller_size <= 200 lines (frontmatter 除外)
# 現状: SKILL.md が 351 行のため fail する
# ---------------------------------------------------------------------------

@test "ac1: co-issue SKILL.md body (frontmatter-excluded) is at most 200 lines" {
  local skill_file="$REPO_ROOT/skills/co-issue/SKILL.md"
  [ -f "$skill_file" ]

  # frontmatter は --- から次の --- までの行を除外してカウント
  local body_lines
  body_lines=$(awk '
    BEGIN { in_fm=0; found_first=0 }
    /^---$/ {
      if (!found_first) { in_fm=1; found_first=1; next }
      if (in_fm)        { in_fm=0; next }
    }
    !in_fm { count++ }
    END { print count+0 }
  ' "$skill_file")

  [ "$body_lines" -le 200 ]
}

# ---------------------------------------------------------------------------
# AC2: token_bloat <= 1500 words
# split 後 refs/ 外出しが完了した状態を確認するため、refs/ 存在を前提とした
# 本体語数チェック。refs/ が未作成の場合は split 未完了として fail する。
# ---------------------------------------------------------------------------

@test "ac2: co-issue SKILL.md word count is at most 1500 (requires refs/ split to be complete)" {
  local skill_file="$REPO_ROOT/skills/co-issue/SKILL.md"
  local refs_dir="$REPO_ROOT/skills/co-issue/refs"
  [ -f "$skill_file" ]

  # refs/ が存在しない = split 未完了 → fail（RED 条件）
  [ -d "$refs_dir" ]

  # refs/ に 5 件の ref ファイルが揃っていることを確認（split 完了の代理指標）
  local refs_count
  refs_count=$(find "$refs_dir" -name '*.md' | wc -l)
  [ "$refs_count" -ge 5 ]

  # split 完了後の本体語数が 1500 以下であることを確認
  local word_count
  word_count=$(wc -w < "$skill_file")
  [ "$word_count" -le 1500 ]
}

# ---------------------------------------------------------------------------
# AC3: refs/ の全 .md が SKILL.md の Read 指示文から 1:1 参照（差集合空）
# 現状: refs/ ディレクトリが存在しないため fail する
# ---------------------------------------------------------------------------

@test "ac3: all refs/*.md files are referenced by Read instructions in SKILL.md" {
  local refs_dir="$REPO_ROOT/skills/co-issue/refs"
  local skill_file="$REPO_ROOT/skills/co-issue/SKILL.md"

  # refs/ が存在しなければ fail
  [ -d "$refs_dir" ]

  # refs/ に .md ファイルが存在することを確認
  local refs_count
  refs_count=$(find "$refs_dir" -name '*.md' | wc -l)
  [ "$refs_count" -gt 0 ]

  # refs/ の各ファイル名が SKILL.md の Read 指示文で参照されているか確認
  # パターン: `refs/<filename>` を Read または Read.*refs/<filename>
  local unref_count=0
  while IFS= read -r ref_file; do
    local basename
    basename=$(basename "$ref_file")
    if ! grep -qE "refs/${basename}.*Read|Read.*refs/${basename}" "$skill_file"; then
      unref_count=$((unref_count + 1))
    fi
  done < <(find "$refs_dir" -name '*.md')

  [ "$unref_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC4: 逆方向 dead reference なし（SKILL.md が参照する refs ファイルが実在）
# 現状: refs/ ディレクトリが存在しないため fail する
# ---------------------------------------------------------------------------

@test "ac4: all refs referenced in SKILL.md actually exist in refs/" {
  local refs_dir="$REPO_ROOT/skills/co-issue/refs"
  local skill_file="$REPO_ROOT/skills/co-issue/SKILL.md"

  # refs/ が存在しなければ fail
  [ -d "$refs_dir" ]

  # SKILL.md 内の refs/co-issue-*.md 参照を抽出
  local dead_count=0
  while IFS= read -r ref_name; do
    if [ ! -f "$refs_dir/$ref_name" ]; then
      dead_count=$((dead_count + 1))
    fi
  # ドット文字も許可（co-issue-step0.5-modes.md のような名前に対応）
  done < <(grep -oE 'refs/co-issue-[a-z0-9.-]+\.md' "$skill_file" | sed 's|refs/||' | sort -u)

  [ "$dead_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC5: ref 間 cross-reference 禁止（ref ファイル内に他 ref への参照なし）
# 現状: refs/ ディレクトリが存在しないため fail する
# ---------------------------------------------------------------------------

@test "ac5: no cross-references between ref files" {
  local refs_dir="$REPO_ROOT/skills/co-issue/refs"

  # refs/ が存在しなければ fail
  [ -d "$refs_dir" ]

  # refs/ 内の .md ファイルが他の refs/co-issue-*.md を参照していないことを確認
  # ドット文字も許可（co-issue-step0.5-modes.md のような名前に対応）
  local cross_ref_count
  cross_ref_count=$(grep -rlE 'refs/co-issue-[a-z0-9.-]+\.md' "$refs_dir"/*.md 2>/dev/null | wc -l)

  [ "$cross_ref_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC6: 各 ref ファイルが 200 行以下
# 現状: refs/ ディレクトリが存在しないため fail する
# ---------------------------------------------------------------------------

@test "ac6: each file in refs/ is at most 200 lines" {
  local refs_dir="$REPO_ROOT/skills/co-issue/refs"

  # refs/ が存在しなければ fail
  [ -d "$refs_dir" ]

  # refs/ に .md ファイルが存在することを確認
  local refs_count
  refs_count=$(find "$refs_dir" -name '*.md' | wc -l)
  [ "$refs_count" -gt 0 ]

  local oversized_count=0
  while IFS= read -r ref_file; do
    local line_count
    line_count=$(wc -l < "$ref_file")
    if [ "$line_count" -gt 200 ]; then
      oversized_count=$((oversized_count + 1))
    fi
  done < <(find "$refs_dir" -name '*.md')

  [ "$oversized_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC7: deps.yaml に co-issue の calls セクションに 5 件の reference エントリ
# 現状: reference タイプエントリがないため fail する
# ---------------------------------------------------------------------------

@test "ac7: deps.yaml co-issue calls section has exactly 5 reference type entries" {
  local deps_file="$REPO_ROOT/deps.yaml"
  [ -f "$deps_file" ]

  local ref_count
  ref_count=$(yq '.skills."co-issue".calls[] | select(has("reference")) | length' "$deps_file" 2>/dev/null | wc -l)

  [ "$ref_count" -eq 5 ]
}

# ---------------------------------------------------------------------------
# AC8: README.md に refs/ 構造が反映されている
# 現状: README.md に co-issue refs への言及がないため fail する
# ---------------------------------------------------------------------------

@test "ac8: deps-co-issue.svg reflects refs structure (twl update-readme 済み)" {
  local svg_file="$REPO_ROOT/docs/deps-co-issue.svg"
  local dot_file="$REPO_ROOT/docs/deps-co-issue.dot"

  # SVG または DOT ファイルが存在することを確認
  [ -f "$svg_file" ] || [ -f "$dot_file" ]

  # co-issue refs ノードが SVG/DOT に含まれていることを確認（twl --update-readme で生成）
  local check_file
  if [ -f "$dot_file" ]; then
    check_file="$dot_file"
  else
    check_file="$svg_file"
  fi

  grep -qE 'co-issue-step0\.5-modes|co-issue-phase2-bundles|co-issue-phase3-dispatch|co-issue-phase4-aggregate|co-issue-cleanup' "$check_file"
}
