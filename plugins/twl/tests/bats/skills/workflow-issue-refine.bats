#!/usr/bin/env bats
# workflow-issue-refine.bats — TDD RED phase tests for Issue #1209
#
# 検証対象: refined label dual-write 保護 + spec doc 更新
#   - AC1: refine-processing-flow.md Step 6' label ループに || true guard が存在すること
#   - AC2: refine-processing-flow.md Step 6' Status update が label 失敗と独立することを明記
#   - AC3: lifecycle-processing-flow.md Step 6 に auto-create + || true guard + 独立 Status update が明記
#   - AC4: co-issue-phase4-aggregate.md の --add-label refined 直前に gh label create refined が存在すること
#
# RED フェーズ: 実装前は全テストが FAIL する。
#   - AC1: refine-processing-flow.md の label ループに || true guard が存在しない → FAIL
#   - AC2: Status update 独立性の明示文言が存在しない → FAIL
#   - AC3: lifecycle-processing-flow.md に auto-create + || true guard + 独立 Status update の明示がない → FAIL
#   - AC4: co-issue-phase4-aggregate.md に gh label create refined の行が --add-label refined 直前にない → FAIL

load '../helpers/common'

REFINE_FLOW_MD=""
LIFECYCLE_FLOW_MD=""
CO_ISSUE_PHASE4_MD=""

setup() {
  common_setup
  REFINE_FLOW_MD="$REPO_ROOT/refs/refine-processing-flow.md"
  LIFECYCLE_FLOW_MD="$REPO_ROOT/refs/lifecycle-processing-flow.md"
  CO_ISSUE_PHASE4_MD="$REPO_ROOT/skills/co-issue/refs/co-issue-phase4-aggregate.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: refine-processing-flow.md Step 6' — label ループに || true guard が存在すること
# RED: 現在の spec doc の label ループに || true guard がないため FAIL
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: refine-processing-flow.md の label 付与ループが || true で保護されていること
# WHEN refine-processing-flow.md の Step 6' を読む
# THEN gh issue edit --add-label を含む行に || true guard が付いていること
# RED: 現在は付いていないため FAIL
# ---------------------------------------------------------------------------
@test "ac1: refine-processing-flow.md Step 6' の label ループに || true guard が存在する" {
  # AC: labels_hint ループ内の gh issue edit --add-label 行が || true で保護されている
  # RED: 実装前は guard なし → grep 0 件 → FAIL
  run grep -E -- '--add-label.*\|\|.*true|--add-label[^$]*\|\| *true' "$REFINE_FLOW_MD"
  [ "$status" -eq 0 ]
}

@test "ac1: refine-processing-flow.md Step 6' の spec 本文に dual-write パターンの || true guard が明記されている" {
  # AC: spec 本文（コードブロック外の説明文）に || true guard の明記がある
  # RED: 実装前は記述なし → FAIL
  run grep -E '\|\|.*true.*guard|\|\| *true.*label|label.*\|\| *true.*guard' "$REFINE_FLOW_MD"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC2: refine-processing-flow.md Step 6' — Status update が label 失敗と独立することを明記
# RED: 現在の spec doc に独立性の明示文言がないため FAIL
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: refine-processing-flow.md の Status update が label 結果に無関係であることが明記されていること
# WHEN refine-processing-flow.md の Step 6' Status update block を読む
# THEN "ラベル付与の成否に関わらず" または "label 失敗と独立" または相当の文言が存在すること
# RED: 現在は独立性の明示なし → FAIL
# ---------------------------------------------------------------------------
@test "ac2: refine-processing-flow.md Step 6' に Status update の独立性が明記されている" {
  # AC: label 付与 loop の結果（成功/失敗/部分失敗）と無関係に Status update が実行されることを明記
  # RED: 実装前は記述なし → FAIL
  run grep -E '独立|無関係|label.*成否|label.*失敗.*Status|label.*失敗.*独立|regardless.*label|label.*result.*independ|独立して実行' "$REFINE_FLOW_MD"
  [ "$status" -eq 0 ]
}

@test "ac2: refine-processing-flow.md Step 6' の Status update block に独立実行の説明がある" {
  # AC: Status update が label loop の後に独立したブロックとして記述されていることが明示されている
  # 「label 付与 loop の結果（成功/失敗/部分失敗）と無関係に Status update が実行される」旨
  # RED: 実装前は記述なし → FAIL
  run grep -qE '部分失敗.*無関係|成功.*(失敗|部分失敗).*無関係|label.*loop.*独立|Status.*独立' "$REFINE_FLOW_MD"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC3: lifecycle-processing-flow.md Step 6 — auto-create + || true guard + 独立 Status update を明記
# RED: 現在の spec doc にこれらの記述がないため FAIL
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: lifecycle-processing-flow.md Step 6 に gh label create refined --color が存在すること
# WHEN lifecycle-processing-flow.md の Step 6 を読む
# THEN gh label create refined に相当する auto-create コマンドが記述されていること
# RED: 実装前は記述なし → FAIL
# ---------------------------------------------------------------------------
@test "ac3: lifecycle-processing-flow.md Step 6 に gh label create refined が明記されている" {
  # AC: gh label create refined --color ... による auto-create が Step 6 に記述されている
  # RED: 実装前は記述なし → FAIL
  run grep -E 'gh label create refined' "$LIFECYCLE_FLOW_MD"
  [ "$status" -eq 0 ]
}

@test "ac3: lifecycle-processing-flow.md Step 6 の label 付与ループに || true guard が明記されている" {
  # AC: add-label または label create コマンドが || true で保護されていること
  # Step 7 の audit snapshot の || true ではなく、label 付与に特化した guard が必要
  # RED: 実装前は label 付与に対する || true guard が存在しない → FAIL
  run grep -E '(add-label|label create).*\|\|.*true|\|\|.*true.*(add-label|label create)' "$LIFECYCLE_FLOW_MD"
  [ "$status" -eq 0 ]
}

@test "ac3: lifecycle-processing-flow.md Step 6 に Status update の独立性が明記されている" {
  # AC: label 付与結果に無関係に Status update が実行されることが Step 6 に明記されている
  # RED: 実装前は記述なし → FAIL
  run grep -E '独立|無関係|label.*成否.*Status|label.*失敗.*Status|Status.*独立' "$LIFECYCLE_FLOW_MD"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC4: co-issue-phase4-aggregate.md — --add-label refined 直前に gh label create refined が存在すること
# RED: 現在は --add-label refined の直前に gh label create refined がないため FAIL
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: co-issue-phase4-aggregate.md の [B] manual fix path に gh label create refined が存在すること
# WHEN co-issue-phase4-aggregate.md の [B] manual fix セクションを読む
# THEN gh label create refined --color C2E0C6 のコマンド行が存在すること
# RED: 実装前は記述なし → FAIL
# ---------------------------------------------------------------------------
@test "ac4: co-issue-phase4-aggregate.md に gh label create refined が存在する" {
  # AC: [B] manual fix path に gh label create refined --color C2E0C6 --description が追加されている
  # RED: 実装前は記述なし → FAIL
  run grep -E 'gh label create refined' "$CO_ISSUE_PHASE4_MD"
  [ "$status" -eq 0 ]
}

@test "ac4: co-issue-phase4-aggregate.md の gh label create refined に --color オプションが付いている" {
  # AC: gh label create refined --color C2E0C6 の形式であること
  # RED: 実装前は記述なし → FAIL
  run grep -E 'gh label create refined.*--color' "$CO_ISSUE_PHASE4_MD"
  [ "$status" -eq 0 ]
}

@test "ac4: co-issue-phase4-aggregate.md の gh label create refined が --add-label refined より前に位置する" {
  # AC: gh label create refined の行番号 < gh issue edit --add-label refined の行番号
  # RED: 実装前は gh label create refined が存在しないため FAIL
  local create_line add_label_line
  create_line=$(grep -n 'gh label create refined' "$CO_ISSUE_PHASE4_MD" | head -1 | cut -d: -f1)
  add_label_line=$(grep -n -- '--add-label refined' "$CO_ISSUE_PHASE4_MD" | head -1 | cut -d: -f1)

  # gh label create refined が存在すること
  [ -n "$create_line" ]
  # --add-label refined が存在すること
  [ -n "$add_label_line" ]
  # create が add-label より先（行番号が小さい）であること
  [ "$create_line" -lt "$add_label_line" ]
}

@test "ac4: co-issue-phase4-aggregate.md の gh label create refined に || true guard が付いている" {
  # AC: gh label create refined ... || true の形式で保護されていること
  # RED: 実装前は記述なし → FAIL
  run grep -E 'gh label create refined.*\|\|.*true' "$CO_ISSUE_PHASE4_MD"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC1+AC2 結合: dual-write パターンの完全性確認
# refine-processing-flow.md Step 6' の dual-write 記述が以下を全て含むこと:
#   (1) label ループに || true guard
#   (2) Status update 独立性の明示
# ===========================================================================

@test "ac1+ac2: refine-processing-flow.md Step 6' に dual-write パターン全要素が揃っている" {
  # AC: (1) || true guard と (2) Status 独立性の両方が存在すること
  # RED: いずれかが欠けているため FAIL

  # (1) || true guard
  local has_guard
  has_guard=$(grep -cE -- '--add-label.*\|\|.*true|\|\| *true.*label' "$REFINE_FLOW_MD" || true)

  # (2) 独立性の記述
  local has_independent
  has_independent=$(grep -cE '独立|無関係|label.*成否|部分失敗.*無関係' "$REFINE_FLOW_MD" || true)

  # 両方 1 以上であること
  [ "$has_guard" -ge 1 ]
  [ "$has_independent" -ge 1 ]
}

# ===========================================================================
# AC5(i): gh label create が gh issue edit --add-label の前に呼ばれることを verify
# co-issue-phase4-aggregate.md における呼び出し順序（spec doc line ordering）
# ===========================================================================

@test "ac5(i): co-issue-phase4-aggregate.md で gh label create refined が --add-label refined より前に存在する" {
  # AC5(i): calls log assertion — label create が add-label より先（行番号が小さい）
  # (ac4 のラインオーダーテストと同等だが AC5 として明示的に分類)
  local create_line add_label_line
  create_line=$(grep -n 'gh label create refined' "$CO_ISSUE_PHASE4_MD" | head -1 | cut -d: -f1)
  add_label_line=$(grep -n -- '--add-label refined' "$CO_ISSUE_PHASE4_MD" | head -1 | cut -d: -f1)
  [ -n "$create_line" ]
  [ -n "$add_label_line" ]
  [ "$create_line" -lt "$add_label_line" ]
}

# ===========================================================================
# AC5(ii): add-label refined の後に board-status-update Refined が出現することを verify（順序保持）
# refine-processing-flow.md Step 6' における dual-write 順序を verify
# ===========================================================================

@test "ac5(ii): refine-processing-flow.md で --add-label の後に board-status-update Refined が存在する" {
  # AC5(ii): 次行順序 — add-label ループ後に board-status-update Refined が出現すること
  local add_label_line board_status_line
  add_label_line=$(grep -n -- '--add-label' "$REFINE_FLOW_MD" | head -1 | cut -d: -f1)
  board_status_line=$(grep -n 'board-status-update.*Refined' "$REFINE_FLOW_MD" | head -1 | cut -d: -f1)
  [ -n "$add_label_line" ]
  [ -n "$board_status_line" ]
  [ "$add_label_line" -lt "$board_status_line" ]
}

# ===========================================================================
# AC5(iii): label add 失敗時でも board-status-update Refined が実行されることを verify（独立性）
# spec doc に「|| true guard + Status update 独立性」が両方明記されていることを確認
# ===========================================================================

@test "ac5(iii): refine-processing-flow.md に label add 失敗でも Status update が実行される独立性保証がある" {
  # AC5(iii): label add 失敗 mock injection の等価 — spec doc に || true guard と独立性が明記されていること
  # シェルレベルの || true guard（label add 失敗でも loop が継続）
  run grep -E -- '--add-label.*\|\|.*true' "$REFINE_FLOW_MD"
  [ "$status" -eq 0 ]

  # Status update が label 結果と独立して実行されることの明示（独立性保証テキスト）
  run grep -qE '独立|無関係|label.*成否|部分失敗' "$REFINE_FLOW_MD"
  [ "$status" -eq 0 ]
}
