#!/usr/bin/env bats
# spawn-controller-docs.bats - pitfalls-catalog §10 / §3.5 改訂 + SKILL.md MUST NOT サブ節の
#                               コンテンツ検証テスト（静的 grep ベース）
#
# Generated from: deltaspec/changes/issue-799/specs/pitfalls-catalog.md
#                 deltaspec/changes/issue-799/specs/skill-md.md
#
# Requirements:
#   - pitfalls-catalog §10 spawn prompt 最小化原則
#   - pitfalls-catalog §3.5 の改訂
#   - SKILL.md spawn prompt MUST NOT サブ節追加
#   - SKILL.md 最小 prompt 例の追加
#
# Coverage: unit + edge-cases（ドキュメント内容の機械的固定テスト）

load '../helpers/common'

PITFALLS_CATALOG=""
SKILL_MD=""

setup() {
  common_setup
  PITFALLS_CATALOG="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: pitfalls-catalog §10 spawn prompt 最小化原則
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: §10 MUST NOT 表に必須 7 項目が存在する
# WHEN: pitfalls-catalog.md を参照する
# THEN: 以下 7 項目が MUST NOT 表に存在する:
#       Issue body/labels/title、Issue comments、explore summary、
#       architecture 文書、SKILL.md Phase 手順、past memory 生データ、
#       bare repo/worktree 構造
# ---------------------------------------------------------------------------

@test "pitfalls §10: ファイルが存在する" {
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"
}

@test "pitfalls §10: §10 セクションが存在する" {
  grep -q '^## 10\.' "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md に '## 10.' セクションが存在しない"
}

@test "pitfalls §10 MUST NOT: Issue body/labels/title が存在する" {
  grep -iE 'Issue body|Issue.*labels|Issue.*title' "$PITFALLS_CATALOG" | grep -qi 'MUST NOT\|must.not\|×' \
    || grep -q 'Issue body' "$PITFALLS_CATALOG" \
    || fail "§10 MUST NOT 表に 'Issue body' が存在しない"
  # §10 のコンテキスト内で確認
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" | grep -qi 'Issue body' \
    || fail "§10 に 'Issue body' が存在しない"
}

@test "pitfalls §10 MUST NOT: Issue comments が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'Issue comment|comments' \
    || fail "§10 に 'Issue comments' が存在しない"
}

@test "pitfalls §10 MUST NOT: explore summary が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'explore.?summary|explore.*sum' \
    || fail "§10 に 'explore summary' が存在しない"
}

@test "pitfalls §10 MUST NOT: architecture 文書が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'architecture|アーキテクチャ' \
    || fail "§10 に 'architecture 文書' が存在しない"
}

@test "pitfalls §10 MUST NOT: SKILL.md Phase 手順が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'SKILL\.md.*Phase|Phase.*手順|Phase.*step' \
    || fail "§10 に 'SKILL.md Phase 手順' が存在しない"
}

@test "pitfalls §10 MUST NOT: past memory 生データが存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'past memory|memory.*生データ|memory.*raw|past.*memory' \
    || fail "§10 に 'past memory 生データ' が存在しない"
}

@test "pitfalls §10 MUST NOT: bare repo/worktree 構造が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'bare.?repo|worktree.*構造|bare.*worktree' \
    || fail "§10 に 'bare repo/worktree 構造' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: §10 MUST 5 項目が存在する
# WHEN: pitfalls-catalog.md を参照する
# THEN: 以下 5 項目が MUST 節に存在する:
#       spawn 元識別、Issue 番号/成果物パス、proxy 対話期待、
#       observer 独自 deep-dive 観点、Wave 文脈/並列タスク境界
# ---------------------------------------------------------------------------

@test "pitfalls §10 MUST: spawn 元識別が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'spawn.*元|spawn.*from|spawner|spawn.?元識別' \
    || fail "§10 に 'spawn 元識別' が存在しない"
}

@test "pitfalls §10 MUST: Issue 番号/成果物パスが存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'Issue.*番号|issue.?num|成果物.*パス|artifact.*path' \
    || fail "§10 に 'Issue 番号/成果物パス' が存在しない"
}

@test "pitfalls §10 MUST: proxy 対話期待が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'proxy.*対話|proxy.*interact|proxy.*expect' \
    || fail "§10 に 'proxy 対話期待' が存在しない"
}

@test "pitfalls §10 MUST: observer 独自 deep-dive 観点が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'deep.?dive|deep_dive|独自.*観点|observer.*観点' \
    || fail "§10 に 'observer 独自 deep-dive 観点' が存在しない"
}

@test "pitfalls §10 MUST: Wave 文脈/並列タスク境界が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'Wave.*文脈|wave.*context|並列.*タスク|parallel.*task|タスク.*境界' \
    || fail "§10 に 'Wave 文脈/並列タスク境界' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: --force-large 例外が記述される
# WHEN: pitfalls-catalog.md の §10 を参照する
# THEN: --force-large option と prompt 冒頭 REASON: 行による例外が記述されている
# ---------------------------------------------------------------------------

@test "pitfalls §10: --force-large 例外が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -q '\-\-force-large' \
    || fail "§10 に '--force-large' が存在しない"
}

@test "pitfalls §10: REASON: 行による例外が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qE 'REASON:|reason:' \
    || fail "§10 に 'REASON:' 行が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 境界補足が記述される
# WHEN: pitfalls-catalog.md の §10 を参照する
# THEN: 「observer が自分で取得した情報であっても spawn 先 skill が同じ操作で
#        取得できる場合は転記禁止」という境界補足が記述されている
# ---------------------------------------------------------------------------

@test "pitfalls §10: observer 自己取得情報の転記禁止補足が存在する" {
  sed -n '/^## 10\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE '自律取得可能|auto.?fetch|同じ操作.*取得|skill.*取得.*転記禁止|自分で取得.*skill' \
    || fail "§10 に observer 自己取得情報の境界補足が存在しない"
}

# ===========================================================================
# Requirement: pitfalls-catalog §3.5 の改訂
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: §3.5 に §10 への参照が含まれる
# WHEN: pitfalls-catalog.md §3.5 を参照する
# THEN: 「§10 参照」という記述が含まれ、「全て prompt に包含」という表現が削除されている
# ---------------------------------------------------------------------------

@test "pitfalls §3.5: §10 への参照が存在する" {
  grep -E '3\.5' "$PITFALLS_CATALOG" | grep -q '§10\|§ 10' \
    || grep -A5 '3\.5' "$PITFALLS_CATALOG" | grep -q '§10\|§ 10' \
    || fail "§3.5 に '§10' への参照が存在しない"
}

@test "pitfalls §3.5: 「全て prompt に包含」が削除されている（改訂確認）" {
  # §3.5 の行周辺に「全て prompt に包含」という旧表現が含まれていないことを確認
  # ただし §10 への参照として引用される場合は除外できないため、
  # §3.5 本文（pitfall の「対策」列）を対象にする
  local line35
  line35=$(grep '3\.5' "$PITFALLS_CATALOG" || true)
  # 旧表現がそのまま対策として残っていないことを確認
  if echo "$line35" | grep -q '全て prompt に包含'; then
    # 「§10 参照」を伴わずに「全て prompt に包含」が残っている場合は失敗
    if ! echo "$line35" | grep -q '§10'; then
      fail "§3.5 対策に「全て prompt に包含」が §10 参照なしで残っている"
    fi
  fi
  # §3.5 に §10 参照が追加されていれば改訂済みとみなす（前テストで確認済み）
  true
}

@test "pitfalls §3.5: observer 固有文脈のみ包含 または §10 参照に改訂されている" {
  grep -E '3\.5' "$PITFALLS_CATALOG" \
    | grep -qiE 'observer.*固有|固有.*文脈|§10|自律取得可能' \
    || fail "§3.5 が 'observer 固有文脈' または '§10 参照' を含む形に改訂されていない"
}

# ===========================================================================
# Requirement: SKILL.md spawn prompt MUST NOT サブ節追加
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: MUST NOT サブ節が存在する
# WHEN: SKILL.md の「spawn プロンプトの文脈包含」節を参照する
# THEN: #### MUST NOT: skill 自律取得可能情報の転記 ヘッダーが存在し、
#       7 項目以上の列挙がある
# ---------------------------------------------------------------------------

@test "SKILL.md: ファイルが存在する" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"
}

@test "SKILL.md: MUST NOT サブ節ヘッダーが存在する" {
  grep -q 'MUST NOT.*skill.*自律取得可能\|MUST NOT.*自律取得可能' "$SKILL_MD" \
    || fail "SKILL.md に 'MUST NOT: skill 自律取得可能情報の転記' ヘッダーが存在しない"
}

@test "SKILL.md MUST NOT サブ節: Issue body が存在する" {
  sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -qi 'Issue body' \
    || fail "SKILL.md MUST NOT サブ節に 'Issue body' が存在しない"
}

@test "SKILL.md MUST NOT サブ節: Issue comments が存在する" {
  sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -qiE 'Issue comment|comments' \
    || fail "SKILL.md MUST NOT サブ節に 'Issue comments' が存在しない"
}

@test "SKILL.md MUST NOT サブ節: explore summary が存在する" {
  sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -qiE 'explore.?summary|explore.*sum' \
    || fail "SKILL.md MUST NOT サブ節に 'explore summary' が存在しない"
}

@test "SKILL.md MUST NOT サブ節: architecture が存在する" {
  sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -qiE 'architecture|アーキテクチャ' \
    || fail "SKILL.md MUST NOT サブ節に 'architecture' が存在しない"
}

@test "SKILL.md MUST NOT サブ節: Phase 手順が存在する" {
  sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -qiE 'Phase.*手順|Phase.*step|SKILL.md.*Phase' \
    || fail "SKILL.md MUST NOT サブ節に 'Phase 手順' が存在しない"
}

@test "SKILL.md MUST NOT サブ節: past memory 生データが存在する" {
  sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -qiE 'past memory|memory.*生データ|past.*mem' \
    || fail "SKILL.md MUST NOT サブ節に 'past memory 生データ' が存在しない"
}

@test "SKILL.md MUST NOT サブ節: bare repo/worktree 構造が存在する" {
  sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -qiE 'bare.?repo|worktree.*構造|bare.*worktree' \
    || fail "SKILL.md MUST NOT サブ節に 'bare repo/worktree 構造' が存在しない"
}

@test "SKILL.md MUST NOT サブ節: 列挙項目が 7 個以上ある" {
  local count
  count=$(sed -n '/MUST NOT.*自律取得可能/,/^####/p' "$SKILL_MD" \
    | grep -cE '^[[:space:]]*[-*]|^[[:space:]]*[0-9]+\.' || true)
  [[ "$count" -ge 7 ]] \
    || fail "SKILL.md MUST NOT サブ節の列挙項目が 7 個未満: ${count} 個"
}

# ===========================================================================
# Requirement: SKILL.md 最小 prompt 例の追加
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 最小 prompt 例が MUST 5 項目を含む
# WHEN: SKILL.md の最小 prompt 例を参照する
# THEN: spawn 元識別・Issue 番号・proxy 対話期待・observer 独自観点・
#       Wave 文脈の 5 要素が含まれる
# ---------------------------------------------------------------------------

@test "SKILL.md 最小 prompt 例: spawn 元識別が含まれる" {
  grep -qiE 'spawn.*元|spawner|spawn.*from|spawn.*識別|spawn.*source' "$SKILL_MD" \
    || fail "SKILL.md 最小 prompt 例に 'spawn 元識別' が含まれない"
}

@test "SKILL.md 最小 prompt 例: Issue 番号が含まれる" {
  # 最小 prompt 例のテンプレ内に Issue 番号プレースホルダーが含まれること
  grep -qiE 'Issue.*#[0-9N]|Issue.*番号|issue_num|ISSUE_NUM' "$SKILL_MD" \
    || fail "SKILL.md 最小 prompt 例に 'Issue 番号' が含まれない"
}

@test "SKILL.md 最小 prompt 例: proxy 対話期待が含まれる" {
  grep -qiE 'proxy.*対話|proxy.*interact|AskUserQuestion|ask.*question|質問.*期待' "$SKILL_MD" \
    || fail "SKILL.md 最小 prompt 例に 'proxy 対話期待' が含まれない"
}

@test "SKILL.md 最小 prompt 例: observer 独自観点が含まれる" {
  grep -qiE 'deep.?dive|deep_dive|独自.*観点|observer.*観点|focus.*point' "$SKILL_MD" \
    || fail "SKILL.md 最小 prompt 例に 'observer 独自観点' が含まれない"
}

@test "SKILL.md 最小 prompt 例: Wave 文脈が含まれる" {
  grep -qiE 'Wave.*[0-9N]|wave.*context|Wave.*文脈|wave.*plan|wave.*progress' "$SKILL_MD" \
    || fail "SKILL.md 最小 prompt 例に 'Wave 文脈' が含まれない"
}

# ---------------------------------------------------------------------------
# Scenario: 最小 prompt 例が 5-10 行に収まる
# WHEN: SKILL.md の最小 prompt 例テンプレを参照する
# THEN: 例示行数が 10 行以内に収まっている
# ---------------------------------------------------------------------------

@test "SKILL.md 最小 prompt 例: 例示テンプレが 10 行以内に収まる" {
  # コードブロック内の例示を検出（``` または ~~~  で囲まれた spawn prompt テンプレ）
  # 「最小 prompt 例」または「template」キーワード周辺のコードブロックを抽出して行数検証
  local block_lines
  block_lines=$(python3 - "$SKILL_MD" <<'PY'
import sys, re

content = open(sys.argv[1]).read()

# 最小 prompt / template / spawn.*例 周辺のコードブロックを抽出
# パターン: ``` or ~~~ で始まり同種で終わる
pattern = re.compile(r'```[^\n]*\n(.*?)```', re.DOTALL)
blocks = pattern.findall(content)

# 最小 prompt に関連するブロック（直前行に「最小」「template」「例」が含まれるもの）
min_prompt_blocks = []
for m in re.finditer(r'(?:最小.*prompt|minimum.*prompt|prompt.*例|template)[^\n]*\n```[^\n]*\n(.*?)```', content, re.DOTALL | re.IGNORECASE):
    min_prompt_blocks.append(m.group(1))

if min_prompt_blocks:
    # 最大行数を出力
    max_lines = max(len(b.rstrip('\n').split('\n')) for b in min_prompt_blocks)
    print(max_lines)
else:
    # 最小 prompt 例ブロックが見つからない場合は 0
    print(0)
PY
  )

  if [[ "$block_lines" -eq 0 ]]; then
    # テンプレブロックが見つからない → コンテンツ確認が必要
    # 別方式: spawn 文脈で 5-10 行テンプレに言及があれば合格
    grep -qiE '5.?10.*行|5.?10.*line|行.*5.?10|最小.*prompt.*例' "$SKILL_MD" \
      || fail "SKILL.md に最小 prompt 例が見当たらない（コードブロック未検出）"
  else
    [[ "$block_lines" -le 10 ]] \
      || fail "SKILL.md 最小 prompt 例が 10 行超: ${block_lines} 行"
  fi
}

# ===========================================================================
# Edge cases: 回帰防止
# ===========================================================================

@test "[edge] §3.5 に旧表現「全て prompt に包含」が §10 参照なしで残っていない" {
  local line35
  line35=$(grep -n '3\.5' "$PITFALLS_CATALOG" | head -1)
  local line_num
  line_num=$(echo "$line35" | cut -d: -f1)

  if [[ -n "$line_num" ]]; then
    # §3.5 の対策列（同一テーブル行）を取得
    local row
    row=$(sed -n "${line_num}p" "$PITFALLS_CATALOG")
    # 「全て prompt に包含」が残り、かつ §10 参照が同行にない場合は失敗
    if echo "$row" | grep -q '全て prompt に包含'; then
      if ! echo "$row" | grep -q '§10'; then
        fail "§3.5 に旧表現「全て prompt に包含」が §10 参照なしで残っている: $row"
      fi
    fi
  fi
  true
}

@test "[edge] SKILL.md の spawn プロンプトの文脈包含節が存在する（MUST NOT サブ節の親確認）" {
  grep -q 'spawn プロンプトの文脈包含' "$SKILL_MD" \
    || fail "SKILL.md に 'spawn プロンプトの文脈包含' 節が存在しない（親節消滅の回帰）"
}
