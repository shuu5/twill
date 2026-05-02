#!/usr/bin/env bats
# ac-scaffold-tests-1266.bats
#
# Issue #1266: co-architect --type=value / DDD skip 対応
#
# AC coverage:
#   AC1  - --type=generic 起動時 domain/* 不在で WARNING 出さない (INFO 降格)
#   AC2  - ref-architecture-spec.md に Project Type 概念と type 別必須テーブル (DDD/Generic 列)
#   AC3  - --type 未指定時デフォルト ddd、既存 architecture/ は影響なし (後方互換)
#   AC4  - architect-completeness-check が --type=<value> を受け取り動的選択
#   AC5  - --type 未指定時 .architecture-type → vision.md frontmatter → ddd の解決順序
#   AC6  - 未知 type は明示エラーで停止
#   AC7  - co-architect Step 2 メッセージに選択 type 名を表示
#   AC8  - --type=generic 時 Step 2 が DDD フローではなく vision.md + phases/*.md フローに切り替わる
#   AC9  - --group と --type 同時指定時 --group 優先、--type は --group 処理内に引き継がれる
#   AC10 - lib type の予約（実装は将来、定義のみ）
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  COMPLETENESS_CHECK_CMD="${REPO_ROOT}/commands/architect-completeness-check.md"
  CO_ARCHITECT_SKILL="${REPO_ROOT}/skills/co-architect/SKILL.md"
  REF_ARCH_SPEC="${REPO_ROOT}/refs/ref-architecture-spec.md"
  export COMPLETENESS_CHECK_CMD CO_ARCHITECT_SKILL REF_ARCH_SPEC

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: --type=generic 時 domain/* 不在で WARNING が出ない (INFO 降格)
# ===========================================================================

@test "ac1-generic-domain-no-warning: architect-completeness-check.md が generic type 時 domain/* を WARNING しない旨を記述している" {
  # AC: co-architect --type=generic 起動時、domain/model.md / domain/glossary.md /
  #     domain/contexts/*.md 不在で architect-completeness-check が WARNING を出さない (INFO 降格)
  # RED: 現在 architect-completeness-check.md に --type=generic の分岐が存在しないため fail
  run bash -c "
    grep -qE 'generic.*INFO|INFO.*generic|type.*generic.*domain|generic.*domain.*INFO' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: ref-architecture-spec.md に Project Type 概念と type 別必須テーブル (DDD/Generic 列)
# ===========================================================================

@test "ac2-project-type-concept: ref-architecture-spec.md に Project Type または type 概念の定義がある" {
  # AC: ref-architecture-spec.md に Project Type 概念が定義されている
  # RED: 現在 ref-architecture-spec.md に Project Type 概念が存在しないため fail
  run bash -c "
    grep -qE 'Project Type|project.type|プロジェクト.*タイプ|ProjectType' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-type-table-ddd-col: ref-architecture-spec.md の必須テーブルに DDD 列がある" {
  # AC: ref-architecture-spec.md の必須テーブルに DDD 列が含まれる
  # RED: 現在必須テーブルに DDD 列が存在しないため fail
  run bash -c "
    grep -qE '^\|.*DDD' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-type-table-generic-col: ref-architecture-spec.md の必須テーブルに Generic 列がある" {
  # AC: ref-architecture-spec.md の必須テーブルに Generic 列が含まれる
  # RED: 現在必須テーブルに Generic 列が存在しないため fail
  run bash -c "
    grep -qE '^\|.*Generic|^\|.*GENERIC' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: --type 未指定時デフォルト ddd、後方互換
# ===========================================================================

@test "ac3-default-type-ddd: co-architect SKILL.md に --type 未指定時のデフォルトが ddd である旨が記述されている" {
  # AC: --type 未指定時のデフォルトが ddd で既存 architecture/ を持つプロジェクトは影響なし
  # RED: 現在 SKILL.md に --type デフォルト値の記述が存在しないため fail
  run bash -c "
    grep -qE 'default.*ddd|ddd.*default|未指定.*ddd|ddd.*未指定' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3-backward-compat: architect-completeness-check.md に --type 未指定時の後方互換動作が記述されている" {
  # AC: --type 未指定時は ddd として動作し、既存プロジェクトに影響しない
  # RED: 現在 architect-completeness-check.md に後方互換の記述が存在しないため fail
  run bash -c "
    grep -qE '後方互換|backward.compat|backward_compat|既存.*影響なし|影響なし.*既存' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: architect-completeness-check が --type=<value> を受け取り動的列選択
# ===========================================================================

@test "ac4-type-argument: architect-completeness-check.md に --type 引数の記述がある" {
  # AC: architect-completeness-check が --type=<value> 引数を受け取り、
  #     ref-architecture-spec.md の対応列を動的に選択する
  # RED: 現在 architect-completeness-check.md に --type 引数の記述が存在しないため fail
  run bash -c "
    grep -qE '\-\-type|--type=|type.*引数|type.*argument' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4-dynamic-column-selection: architect-completeness-check.md が type に応じて ref-architecture-spec.md の列を動的選択する記述がある" {
  # AC: ADR-032 のテーブル駆動拡張として type 対応列を動的に選択する
  # RED: 現在動的列選択の記述が存在しないため fail
  run bash -c "
    grep -qE '動的.*選択|select.*column|column.*select|type.*列|列.*type|対応列' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: --type 未指定時 .architecture-type → vision.md frontmatter → ddd の解決順序
# ===========================================================================

@test "ac5-resolution-architecture-type-file: architect-completeness-check.md に .architecture-type ファイル参照が記述されている" {
  # AC: --type 未指定時 .architecture-type ファイルから type を解決する (第1優先)
  # RED: 現在 .architecture-type ファイル参照の記述が存在しないため fail
  run bash -c "
    grep -qE '\.architecture-type|architecture.type.*ファイル|architecture-type' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac5-resolution-frontmatter: architect-completeness-check.md に vision.md frontmatter 参照が記述されている" {
  # AC: --type 未指定時 vision.md frontmatter から type を解決する (第2優先)
  # RED: 現在 vision.md frontmatter 参照の記述が存在しないため fail
  run bash -c "
    grep -qE 'frontmatter|vision\.md.*type|front.matter' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac5-resolution-order: architect-completeness-check.md の type 解決順序が .architecture-type → frontmatter → ddd になっている" {
  # AC: 解決優先順位 .architecture-type > vision.md frontmatter > ddd が明記されている
  # RED: 現在解決順序の記述が存在しないため fail
  run bash -c "
    grep -qE '1.*\.architecture-type|第1.*\.architecture-type|\.architecture-type.*第1|architecture-type.*→|architecture-type.*first' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: 未知 type は明示エラーで停止
# ===========================================================================

@test "ac6-unknown-type-error: architect-completeness-check.md に未知 type のエラー停止が記述されている" {
  # AC: 未知の type (--type=foo) は明示エラーで停止する
  # RED: 現在未知 type のエラー処理記述が存在しないため fail
  run bash -c "
    grep -qE '未知.*type|unknown.*type|type.*unknown|invalid.*type|type.*invalid|エラー.*停止|停止.*エラー' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac6-valid-type-values: ref-architecture-spec.md に有効な type 値の定義がある" {
  # AC: 有効な type 値 (ddd, generic 等) が ref-architecture-spec.md で定義されている
  # RED: 現在有効 type 値の定義が存在しないため fail
  run bash -c "
    grep -qE 'ddd.*generic|generic.*ddd|有効.*type|type.*値域|valid.*type' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: co-architect Step 2 メッセージに選択 type 名を表示
# ===========================================================================

@test "ac7-step2-type-display: co-architect SKILL.md の Step 2 に type 名表示の記述がある" {
  # AC: co-architect Step 2 のメッセージに選択された type 名を表示する
  # RED: 現在 SKILL.md の Step 2 に type 名表示の記述が存在しないため fail
  run bash -c "
    awk '/## Step 2:/{found=1} found && /## Step 3:/{exit} found{print}' '${CO_ARCHITECT_SKILL}' \
      | grep -qE 'type.*名|type.*name|選択.*type|type.*表示|display.*type'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8: --type=generic 時 Step 2 が DDD フローではなく vision.md + phases フローに切り替わる
# ===========================================================================

@test "ac8-generic-flow-switch: co-architect SKILL.md に --type=generic 時の Step 2 フロー切り替えが記述されている" {
  # AC: --type=generic 時 Step 2 の対話プロンプトが Bounded Context / ユビキタス言語ではなく
  #     vision.md + phases/*.md 設計フローに切り替わる
  # RED: 現在 SKILL.md に generic type の分岐が存在しないため fail
  run bash -c "
    grep -qE 'generic.*phases|phases.*generic|type.*generic.*flow|generic.*フロー|generic.*vision' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac8-generic-no-bounded-context: co-architect SKILL.md に --type=generic 時は Bounded Context を省略する記述がある" {
  # AC: generic type では Bounded Context / ユビキタス言語の対話が行われない
  # RED: 現在 SKILL.md に generic フローの Bounded Context スキップ記述が存在しないため fail
  run bash -c "
    grep -qE 'generic.*Bounded Context.*省略|generic.*skip.*Bounded|Bounded.*generic.*not required|generic.*不要.*Bounded' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC9: --group と --type 同時指定時 --group 優先、--type は --group 処理に引き継がれる
# ===========================================================================

@test "ac9-group-takes-precedence: co-architect SKILL.md に --group と --type 同時指定時 --group 優先の記述がある" {
  # AC: --group と --type 同時指定時は --group 優先で動作し、--type は --group 処理内に引き継がれる
  # RED: 現在 SKILL.md の Step 0 に --group + --type の優先順位記述が存在しないため fail
  run bash -c "
    grep -qE '\-\-group.*\-\-type|\-\-type.*\-\-group|group.*優先|group.*priority|group.*type.*引き継' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac9-type-passed-to-group: co-architect SKILL.md の --group 呼び出しに --type を引き継ぐ記述がある" {
  # AC: architect-group-refine 呼び出し時に --type が引き継がれる
  # RED: 現在 architect-group-refine 呼び出しに --type の引き渡し記述が存在しないため fail
  run bash -c "
    # Step 0 の group-refine 呼び出し行に --type の引き継ぎが含まれること
    awk '/## Step 0/{found=1} found && /## Step 1/{exit} found{print}' '${CO_ARCHITECT_SKILL}' \
      | grep -qE 'type.*引き継|--type.*group.refine|group.refine.*--type|pass.*type'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC10: lib type の予約（実装は将来、定義のみ）
# ===========================================================================

@test "ac10-lib-type-reserved: ref-architecture-spec.md に lib type が予約済みとして定義されている" {
  # AC: lib type の予約 (実装は将来、定義のみ)
  # RED: 現在 ref-architecture-spec.md に lib type の予約定義が存在しないため fail
  run bash -c "
    grep -qE 'lib.*予約|lib.*reserved|reserved.*lib|type.*lib' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac10-lib-type-not-implemented: ref-architecture-spec.md の lib type が「将来実装」または未実装として明記されている" {
  # AC: lib type は将来の実装予定として定義されており、現時点では動作しない
  # RED: 現在 lib type の予約定義が存在しないため fail
  run bash -c "
    grep -qE 'lib.*将来|lib.*future|future.*lib|lib.*TBD|TBD.*lib|lib.*未実装|lib.*not.yet' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}
