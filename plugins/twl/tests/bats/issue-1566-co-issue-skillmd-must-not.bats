#!/usr/bin/env bats
# issue-1566-co-issue-skillmd-must-not.bats
#
# Issue #1566: docs(co-issue): SKILL.md MUST NOT に board-status-update 外部呼び出し禁止 bullet 追加
#
# AC1: plugins/twl/skills/co-issue/SKILL.md の ## 禁止事項（MUST NOT）セクション（現 L81-91）に
#      新規 bullet が 1 件追加され、bullet 数が 9 → 10 になる
# AC2: 新 bullet の文言は以下の 5 要素を全て含む:
#      (a) 主文: 「co-issue 外から chain-runner.sh board-status-update <N> Refined を
#          呼び出してはならない」を太字で明示
#      (b) bypass 番号と ADR 参照: 「bypass #2、ADR-024 / epic #1557」
#      (c) 認可 caller の列挙: co-issue Phase 4 [B] および migration script のみ、と明示
#      (d) 違反検出方法: #1567 で実装される caller verify の説明
#      (e) 代替手段の案内: /twl:co-issue refine #N を呼び出すこと
# AC3: 新 bullet が既存 L91 bullet（Status=Refined 遷移 MUST）の直後に挿入され
#      論理的に矛盾しない配置
# AC4: 既存 MUST NOT bullet の体裁に整合（太字主文 + 括弧内の根拠/制約番号）
#      Markdown lint で新規 warning が増えない（既存 lint 基準内）
# AC5: SKILL.md 末尾の正典参照リンクが破壊されない
#      （「Issue Management 制約の正典は」行が残存）
# AC6: PR diff の変更が SKILL.md 1 ファイルに限定され、行追加数 <= 15、行削除数 = 0
#
# RED: 全テストは実装前に fail する（新 bullet が未追加のため）
# GREEN: 新 bullet 追加後に PASS する

load 'helpers/common'

SKILL_FILE=""

setup() {
  common_setup
  # REPO_ROOT は plugins/twl を指す（common.bash の定義に従う）
  SKILL_FILE="${REPO_ROOT}/skills/co-issue/SKILL.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: ## 禁止事項（MUST NOT）セクションの bullet 数が 9 → 10 になる
#
# 現在の bullet 数は 9 件。新 bullet 追加後は 10 件になる。
#
# RED: 現在 bullet 数が 9 件のため count=10 の検証が fail する
# ===========================================================================

@test "ac1: SKILL.md ## 禁止事項 セクションの bullet 数が 10 件である" {
  # AC: 新規 bullet が 1 件追加され、bullet 数が 9 → 10 になる
  # RED: 現在 bullet 数が 9 件のため [ "$count" -eq 10 ] が fail する
  [ -f "$SKILL_FILE" ]

  local count
  count="$(awk '/^## 禁止事項/,/^Issue Management/' "$SKILL_FILE" | grep -c '^-')"
  [ "$count" -eq 10 ]
}

# ===========================================================================
# AC2a: 新 bullet の主文が太字で「board-status-update」外部呼び出し禁止を明示
#
# RED: 新 bullet が未追加のため grep が match しない → fail
# ===========================================================================

@test "ac2a: 新 bullet に board-status-update 外部呼び出し禁止の太字主文が存在する" {
  # AC2(a): 「co-issue 外から chain-runner.sh board-status-update <N> Refined を
  #         呼び出してはならない」を太字で明示
  # RED: 新 bullet が未追加のため grep fail
  [ -f "$SKILL_FILE" ]

  run grep -qF 'board-status-update' "$SKILL_FILE"
  assert_success

  # 太字（**...**）で包まれた主文が存在すること
  run grep -qE '\*\*.*board-status-update.*\*\*' "$SKILL_FILE"
  assert_success
}

# ===========================================================================
# AC2b: 新 bullet に bypass 番号と ADR 参照が含まれる
#
# RED: 新 bullet が未追加のため grep fail
# ===========================================================================

@test "ac2b: 新 bullet に bypass 番号と ADR 参照（bypass #2、ADR-024 / epic #1557）が含まれる" {
  # AC2(b): bypass #2、ADR-024 / epic #1557 の記述
  # RED: 新 bullet が未追加のため grep fail
  [ -f "$SKILL_FILE" ]

  run grep -qF 'bypass #2' "$SKILL_FILE"
  assert_success

  run grep -qF 'ADR-024' "$SKILL_FILE"
  assert_success

  run grep -qF '#1557' "$SKILL_FILE"
  assert_success
}

# ===========================================================================
# AC2c: 新 bullet に認可 caller の列挙が含まれる
#
# 正規 caller は co-issue Phase 4 [B] と migration script のみ。
#
# RED: 新 bullet が未追加のため grep fail
# ===========================================================================

@test "ac2c: 新 bullet に認可 caller（co-issue Phase 4 [B] と migration script）の列挙がある" {
  # AC2(c): 正規 caller は co-issue Phase 4 [B] および migration script のみ
  # RED: 新 bullet が未追加のため grep fail
  [ -f "$SKILL_FILE" ]

  # co-issue Phase 4 [B] への参照
  run grep -qE 'Phase 4 \[B\]' "$SKILL_FILE"
  assert_success

  # migration script への参照
  run grep -qF 'project-board-refined-migrate.sh' "$SKILL_FILE"
  assert_success
}

# ===========================================================================
# AC2d: 新 bullet に違反検出方法（#1567 caller verify）の説明が含まれる
#
# RED: 新 bullet が未追加のため grep fail
# ===========================================================================

@test "ac2d: 新 bullet に違反検出方法（#1567 caller verify / TWL_CALLER_AUTHZ）の記述がある" {
  # AC2(d): #1567 で実装される caller verify の env marker TWL_CALLER_AUTHZ チェックで
  #         技術的に deny される旨の記述
  # RED: 新 bullet が未追加のため grep fail
  [ -f "$SKILL_FILE" ]

  run grep -qF '#1567' "$SKILL_FILE"
  assert_success

  run grep -qF 'TWL_CALLER_AUTHZ' "$SKILL_FILE"
  assert_success
}

# ===========================================================================
# AC2e: 新 bullet に代替手段の案内（/twl:co-issue refine #N）が含まれる
#
# RED: 新 bullet が未追加のため grep fail
# ===========================================================================

@test "ac2e: 新 bullet に代替手段の案内（co-issue 外で Refined を設定したい場合は /twl:co-issue refine #N）が含まれる" {
  # AC2(e): co-issue 外で Status=Refined を設定したい場合は /twl:co-issue refine #N を呼び出すこと
  # RED: 新 bullet が未追加のため、「co-issue 外で」と「refine」を同じ bullet 行で
  #      言及するパターンが存在しないため fail
  # NOTE: L35 の「例: /twl:co-issue refine #513」では「co-issue 外で」という文脈がないため
  #       偽陽性 PASS を防ぐため「co-issue 外」と「refine」の組み合わせで検証する
  [ -f "$SKILL_FILE" ]

  # 代替手段として「refine」コマンドを案内する bullet が存在すること
  # 「co-issue 外」という文脈を含む行に refine 案内があること
  run grep -qE 'co-issue 外.*refine|refine.*co-issue 外' "$SKILL_FILE"
  assert_success
}

# ===========================================================================
# AC3: 新 bullet が Status=Refined 遷移 MUST bullet の直後に挿入されている
#
# 既存 L91 bullet「**Status=Refined 遷移 MUST**」の直後に新 bullet が配置されること。
#
# RED: 新 bullet が未追加のため awk での順序確認が fail する
# ===========================================================================

@test "ac3: 新 bullet が Status=Refined 遷移 MUST bullet の直後に配置されている" {
  # AC3: 新 bullet が既存 L91 bullet の直後への挿入で読み取れる
  # RED: 新 bullet が未追加のため board-status-update が Refined MUST の後に来ない
  [ -f "$SKILL_FILE" ]

  # Status=Refined 遷移 MUST bullet の行番号を取得
  local refined_line
  refined_line="$(grep -n 'Status=Refined 遷移 MUST' "$SKILL_FILE" | head -1 | cut -d: -f1)"
  [ -n "$refined_line" ]

  # 新 bullet（bypass #2 を含む、L91 とは別行）の行番号を取得
  # NOTE: board-status-update は L91 にも存在するため bypass #2（新 bullet 固有）で特定する
  local new_bullet_line
  new_bullet_line="$(grep -n 'bypass #2' "$SKILL_FILE" | head -1 | cut -d: -f1)"
  [ -n "$new_bullet_line" ]

  # 新 bullet は Status=Refined MUST の後であること
  [ "$new_bullet_line" -gt "$refined_line" ]

  # 新 bullet と Status=Refined MUST は近接（5 行以内）であること
  local diff
  diff=$(( new_bullet_line - refined_line ))
  [ "$diff" -le 5 ]
}

# ===========================================================================
# AC4: 既存 MUST NOT bullet の体裁に整合した記法
#
# 新 bullet も太字主文 + 括弧内の根拠記述を持つこと。
#
# RED: 新 bullet が未追加のため体裁確認の grep が fail する
# ===========================================================================

@test "ac4: 新 bullet の行は太字主文（**...**）の禁止文で始まり括弧内根拠記述の体裁に整合する" {
  # AC4: 既存 MUST NOT bullet の体裁（太字主文 + 括弧内の根拠/制約番号）に整合
  # RED: 新 bullet が未追加のため、「呼び出してはならない」を太字で含む bullet 行が
  #      存在しないため grep fail
  # NOTE: 既存 L91「**Status=Refined 遷移 MUST**」には board-status-update が含まれるが、
  #       「呼び出してはならない」という禁止主文を太字で持たないため偽陽性 PASS しない
  [ -f "$SKILL_FILE" ]

  # 禁止文（呼び出してはならない）を太字で含む bullet 行が存在すること
  # 体裁: - **...呼び出してはならない**（または - **... MUST NOT ...**）
  run grep -qE '^-[[:space:]]+\*\*.*呼び出してはならない' "$SKILL_FILE"
  assert_success
}

# ===========================================================================
# AC5: SKILL.md 末尾の正典参照リンクが破壊されない
#
# 「Issue Management 制約の正典は」行が残存していること。
#
# RED: この AC は現在も PASS する可能性があるが、実装後に破壊されていないことを
#      回帰ガードとして確認する（現在の SKILL.md には正典参照行が存在する）
# NOTE: 新 bullet 追加前から存在する正典参照行を確認する回帰テスト
# ===========================================================================

@test "ac5: SKILL.md に正典参照リンク行（Issue Management 制約の正典は）が残存する" {
  # AC5: 正典参照リンクが破壊されない
  # RED: 新 bullet 挿入時に誤って正典参照行を削除した場合に fail する
  #      (現状は GREEN だが、実装後に回帰ガードとして機能する)
  # NOTE: このテストは現在 PASS する可能性があるが、実装後の回帰防止に必要
  [ -f "$SKILL_FILE" ]

  run grep -qF 'Issue Management 制約の正典は' "$SKILL_FILE"
  assert_success
}

# ===========================================================================
# AC6: PR diff が SKILL.md 1 ファイルに限定され、行追加数 <= 15、行削除数 = 0
#
# git diff を使って変更行数を検証する。
#
# RED: 新 bullet が未追加のため行追加数が 0 → [ "$added" -ge 1 ] が fail する
# ===========================================================================

@test "ac6a: SKILL.md に対して 1 行以上 15 行以下の行追加がある（diff 確認）" {
  # AC6: 行追加数 >= 1 かつ <= 15
  # RED: 新 bullet が未追加のため追加行数 = 0 → [ "$added" -ge 1 ] が fail する
  [ -f "$SKILL_FILE" ]

  # git diff で追加行数を取得（repo root から絶対パス指定）
  local added repo_root
  repo_root="$(cd "$(dirname "$SKILL_FILE")" && git rev-parse --show-toplevel 2>/dev/null)"
  added="$(git -C "$repo_root" diff HEAD -- "plugins/twl/skills/co-issue/SKILL.md" 2>/dev/null | \
    grep '^+' | grep -v '^+++' | wc -l || echo 0)"

  # 追加が 1 行以上であること（新 bullet 追加の証拠）
  [ "$added" -ge 1 ]

  # 追加が 15 行以下であること
  [ "$added" -le 15 ]
}

@test "ac6b: SKILL.md の diff に行削除がない（行削除数 = 0）" {
  # AC6: 行削除数 = 0
  # RED: 新 bullet が未追加の場合、削除 0 でも追加 0 → ac6a で fail。
  #      このテストは追加実装後に行削除が生じていないことを保証する。
  [ -f "$SKILL_FILE" ]

  local deleted repo_root
  repo_root="$(cd "$(dirname "$SKILL_FILE")" && git rev-parse --show-toplevel 2>/dev/null)"
  deleted="$(git -C "$repo_root" diff HEAD -- "plugins/twl/skills/co-issue/SKILL.md" 2>/dev/null | \
    grep '^-' | grep -v '^---' | wc -l || echo 0)"

  [ "$deleted" -eq 0 ]
}
