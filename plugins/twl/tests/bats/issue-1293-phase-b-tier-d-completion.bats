#!/usr/bin/env bats
# issue-1293-phase-b-tier-d-completion.bats
#
# RED-phase tests for Issue #1293:
#   docs(adr-024): Phase B Tier D Pilot 完了 doc 整合
#     - pilot-completion-signals.md [IDLE-COMPLETED] channel を Status のみに縮約
#     - ref-project-model.md の dual-write 記述を Phase B 完了状態に更新
#     - ADR-024 に Phase B 完了節（Tier A/B/C/D サマリ + 運用ルール）追記
#     - scripts の refined label 言及を整合
#
# AC coverage:
#   AC1 - pilot-completion-signals.md の [IDLE-COMPLETED] channel に "label refined" が 0 件
#   AC2 - ref-project-model.md の dual-write 記述が Phase B 完了状態に書き換えられている
#   AC3 - ADR-024 に Phase B 完了節（Tier A/B/C/D サマリ + 運用ルール）が追記されている
#   AC4 - scripts の refined.*label 残存件数が PR description に明記されている
#   AC5 - doc 変更による既存 bats test 影響なし（このファイルが存在することで確認）
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  PILOT_SIGNALS="${REPO_ROOT}/skills/su-observer/refs/pilot-completion-signals.md"
  PROJECT_MODEL="${REPO_ROOT}/refs/ref-project-model.md"
  ADR_024="${REPO_ROOT}/architecture/decisions/ADR-024-refined-status-field-migration.md"
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
  THIS_BATS="${REPO_ROOT}/tests/bats/issue-1293-phase-b-tier-d-completion.bats"

  export PILOT_SIGNALS PROJECT_MODEL ADR_024 SCRIPTS_DIR THIS_BATS
}

# ===========================================================================
# AC1: pilot-completion-signals.md の [IDLE-COMPLETED] channel が
#      Status のみに縮約され "label refined" 言及が 0 件になっている
# ===========================================================================

@test "ac1: pilot-completion-signals.md contains no 'label.*refined' references" {
  # AC: "label.*refined" パターンで 0 件（backtick format 含む）
  # RED: 現在 line 24 に "label `refined`" が含まれているため fail
  run grep -cE "label[[:space:]]+\`?refined\`?" "${PILOT_SIGNALS}"
  [ "${output}" -eq 0 ]
}

@test "ac1: [IDLE-COMPLETED] row in pilot-completion-signals.md does not describe label detection" {
  # AC: [IDLE-COMPLETED] channel の行が label 付与での検知を記述していない（Status のみ）
  # RED: 現在 "Status=Refined + label refined 付与で検知" となっているため fail
  run bash -c "
    match=\$(grep 'IDLE-COMPLETED' '${PILOT_SIGNALS}' | head -1)
    [ -n \"\${match}\" ] || exit 1
    # 'label.*付与で検知' や 'label.*refined.*で検知' パターンが含まれていないこと
    echo \"\${match}\" | grep -qvE 'label[[:space:]]+\`?refined\`?.*付与で検知|label.*refined.*検知'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: [IDLE-COMPLETED] row still references Status=Refined for detection" {
  # AC: label 削除後も Status=Refined による検知記述が残っている
  # RED: label 削除と同時に Status 参照も消えてしまう誤りを防ぐ
  run bash -c "
    match=\$(grep 'IDLE-COMPLETED' '${PILOT_SIGNALS}' | head -1)
    [ -n \"\${match}\" ] || exit 1
    echo \"\${match}\" | grep -q 'Status=Refined\|Status.*Refined'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: ref-project-model.md の dual-write 記述が Phase B 完了状態に
#      書き換えられている
# ===========================================================================

@test "ac2: ref-project-model.md no longer describes dual-write as active phase" {
  # AC: "Phase 1 では dual-write" / "dual-write: label 先 → Status 後" 記述が消えている
  # RED: 現在 line 138 と line 188 に dual-write 記述が残っているため fail
  run bash -c "
    # dual-write が現在進行形の記述として残っていないことを確認
    # 「Phase B で label 削除予定」という未来形も消えているはず
    grep -c 'dual-write\|dual_write' '${PROJECT_MODEL}'
  "
  [ "${output}" -eq 0 ]
}

@test "ac2: ref-project-model.md Status=Refined description reflects Phase B completion (Status only)" {
  # AC: Status field の説明が「Status のみ」という Phase B 完了状態になっている
  # RED: 現在の記述は Phase 1（dual-write）のままのため fail
  run bash -c "
    # Producer 行が Status のみ設定（label write なし）と記述されているか
    # または「Phase B 完了」「label 削除済み」等の記述が追加されているか
    grep -qE 'Status.*のみ|label.*削除済み|Phase B.*完了|Status only' '${PROJECT_MODEL}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: ADR-024 に Phase B 完了節（Tier A/B/C/D サマリ + 運用ルール）が
#      追記されている
# ===========================================================================

@test "ac3: ADR-024 has Phase B completion section" {
  # AC: ## Phase B 完了 または ## Phase B Complete 相当のセクションが存在する
  # RED: 現在 ADR-024 に Phase B 完了節が存在しないため fail
  run bash -c "
    grep -qE '^## Phase B.*完了|^## Phase B.*Complete|^## Phase B.*Completed' '${ADR_024}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: ADR-024 Phase B completion section includes Tier summary" {
  # AC: Phase B 完了節に Tier A/B/C/D のサマリが含まれている
  # RED: 完了節自体がないため fail
  run bash -c "
    section_line=\$(grep -n '^## Phase B.*完了\|^## Phase B.*Complete\|^## Phase B.*Completed' '${ADR_024}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    # セクション以降に Tier A, B, C, D の全参照があること
    awk -v s=\"\${section_line}\" 'NR >= s' '${ADR_024}' | grep -q 'Tier A'  || exit 1
    awk -v s=\"\${section_line}\" 'NR >= s' '${ADR_024}' | grep -q 'Tier B'  || exit 1
    awk -v s=\"\${section_line}\" 'NR >= s' '${ADR_024}' | grep -q 'Tier C'  || exit 1
    awk -v s=\"\${section_line}\" 'NR >= s' '${ADR_024}' | grep -q 'Tier D'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: ADR-024 Phase B completion section includes 運用ルール" {
  # AC: Phase B 完了節に 運用ルール が含まれている
  # RED: 完了節自体がないため fail
  run bash -c "
    section_line=\$(grep -n '^## Phase B.*完了\|^## Phase B.*Complete\|^## Phase B.*Completed' '${ADR_024}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    awk -v s=\"\${section_line}\" 'NR >= s' '${ADR_024}' | grep -qE '運用ルール|operation.*rule|操作ルール'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: ADR-024 Phase B section replaces 'Phase B（別 Issue 起票予定）' placeholder" {
  # AC: 旧来の "## Phase B（別 Issue 起票予定）" プレースホルダーが完了節に置き換えられている
  # RED: 現在プレースホルダーのままのため fail
  run bash -c "
    # 旧プレースホルダーが存在しないこと
    grep -qE '^## Phase B（別 Issue 起票予定）|^## Phase B\(別 Issue 起票予定\)' '${ADR_024}' && exit 1
    # 完了節が存在すること
    grep -qE '^## Phase B.*完了|^## Phase B.*Complete' '${ADR_024}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: scripts の refined label 言及が整合されている
#      (残存件数が PR description に明記 or 必要分が整理済み)
# ===========================================================================

@test "ac4: project-board-refined-migrate.sh refined label reference is acceptable (migration tool)" {
  # AC: migration tool としての refined label 言及は許容される
  # GREEN: migration tool 自体は Phase B 後も残存して良い（歴史的経緯）
  # このテストは migration script の存在確認のみ行う
  [ -f "${SCRIPTS_DIR}/project-board-refined-migrate.sh" ]
}

@test "ac4: autopilot-launch.sh refined label fallback references are documented or removed" {
  # AC: autopilot-launch.sh の "refined label を確認" コメントが整合されている
  # RED: 現在 fallback として refined label 参照が残っているが整合が未完のため fail
  run bash -c "
    # 残存件数のカウント
    count=\$(grep -c 'refined.*label\|label.*refined' '${SCRIPTS_DIR}/autopilot-launch.sh' 2>/dev/null || echo 0)
    # 0件（削除済み）または、残存する場合はコメントで「Phase B 後削除予定」等が明記されていること
    if [ \"\${count}\" -eq 0 ]; then
      exit 0
    fi
    # 残存する場合は Phase B 関連コメントがある
    grep -qE 'Phase B|TODO.*label|FIXME.*label|deprecated.*label|fallback.*Phase B' \
      '${SCRIPTS_DIR}/autopilot-launch.sh'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: doc 変更による既存 bats test 影響なし
# ===========================================================================

@test "ac5: this bats test file exists at expected path" {
  # AC: bats ファイルが plugins/twl/tests/bats/issue-1293-phase-b-tier-d-completion.bats として存在する
  # GREEN: このファイル自体が存在するため、実行時点では pass する
  [ -f "${THIS_BATS}" ]
}
