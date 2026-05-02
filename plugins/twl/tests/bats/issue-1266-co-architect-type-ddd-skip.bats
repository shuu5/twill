#!/usr/bin/env bats
# issue-1266-co-architect-type-ddd-skip.bats - Issue #1266: co-architect --type=generic で DDD ファイルを skip する RED テスト
#
# AC coverage:
#   AC1 - --type=generic 起動時、domain/*.md / contexts/* 不在が WARNING ではなく INFO に降格
#   AC2 - ref-architecture-spec.md に Project Type 概念と DDD/Generic 列を持つ type 別必須テーブルが定義されている
#   AC3 - --type 未指定時のデフォルトが ddd で、既存 architecture/ は影響なし（後方互換）
#   AC4 - architect-completeness-check.md が --type=<value> 引数を受け取り、対応列を動的選択する記述がある
#   AC5 - architect-completeness-check の --type 未指定時は .architecture-type → vision.md frontmatter → ddd の順で解決
#   AC6 - 未知の type (--type=foo) は明示エラーで停止することが記述されている
#   AC7 - co-architect Step 2 メッセージに選択 type 名を表示する記述がある
#   AC8 - --type=generic 時の Step 2 プロンプトが vision.md + phases/*.md フローに切り替わる記述がある
#   AC9 - --group と --type 同時指定時は --group 優先で動作し --type は引き継がれる
#   AC10 - lib type の予約定義が ref-architecture-spec.md または co-architect/SKILL.md に存在する
#
# 全テストは実装前（RED）状態で fail する（現行コードには --type 対応が存在しない）。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  REF_ARCH_SPEC="${REPO_ROOT}/refs/ref-architecture-spec.md"
  COMPLETENESS_CHECK_CMD="${REPO_ROOT}/commands/architect-completeness-check.md"
  CO_ARCHITECT_SKILL="${REPO_ROOT}/skills/co-architect/SKILL.md"
  export REF_ARCH_SPEC COMPLETENESS_CHECK_CMD CO_ARCHITECT_SKILL

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: --type=generic 時、domain/*.md / contexts/* 不在が WARNING ではなく INFO に降格
# ===========================================================================

@test "ac1-generic-type-domain-demote: architect-completeness-check.md に --type=generic で domain/* が INFO 降格する記述がある" {
  # RED: 現行 architect-completeness-check.md に --type 引数の記述が存在しないため fail
  run bash -c "
    grep -qE '\-\-type.*generic|generic.*INFO|generic.*demote|generic.*降格|type.*generic' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1-generic-domain-model-info: generic type 時 domain/model.md の不在が INFO レベルになることが記述されている" {
  # RED: --type=generic の概念が存在しないため fail
  run bash -c "
    grep -qE 'generic.*domain.*INFO|domain.*generic.*INFO|INFO.*降格.*generic|generic.*INFO.*demote' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1-generic-contexts-not-warning: --type=generic 時に domain/contexts/*.md が WARNING にならない設計が記述されている" {
  # RED: 現在 --type パラメータが存在しないため fail
  run bash -c "
    grep -qE 'generic|--type' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: ref-architecture-spec.md に Project Type 概念と DDD/Generic 列を持つ type 別テーブルが定義されている
# ===========================================================================

@test "ac2-project-type-concept: ref-architecture-spec.md に Project Type の概念が記述されている" {
  # RED: 現在 ref-architecture-spec.md に Project Type の概念が存在しないため fail
  run bash -c "
    grep -qE 'Project Type|project.type|プロジェクトタイプ|ProjectType' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-ddd-generic-columns: ref-architecture-spec.md の必須テーブルに DDD 列と Generic 列が存在する" {
  # RED: 現在 type 別テーブルが存在しないため fail
  run bash -c "
    grep -qiE '\| *DDD *\|' '${REF_ARCH_SPEC}' && grep -qiE '\| *Generic *\|' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-type-table-header: ref-architecture-spec.md の type 別テーブルヘッダーに DDD と Generic が含まれる" {
  # RED: type 別テーブルが存在しないため fail
  run bash -c "
    grep -E '^\| *ファイル' '${REF_ARCH_SPEC}' | grep -qiE 'DDD' || \
    grep -E '^\|.*\|.*\|' '${REF_ARCH_SPEC}' | grep -qiE 'DDD.*Generic|Generic.*DDD'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-generic-type-domain-optional: ref-architecture-spec.md で generic type 時 domain/* が optional（非必須）と定義されている" {
  # RED: type 別定義が存在しないため fail
  run bash -c "
    grep -qiE 'generic.*optional|generic.*不要|generic.*-|domain.*generic.*optional' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-ddd-type-domain-required: ref-architecture-spec.md で ddd type 時 domain/* が必須と定義されている" {
  # RED: type 別テーブルが存在しないため fail（既存の必須定義とは別に type 別定義が必要）
  run bash -c "
    grep -qiE 'DDD.*domain.*YES|ddd.*domain.*必須|DDD.*WARNING' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: --type 未指定時のデフォルトが ddd（後方互換）
# ===========================================================================

@test "ac3-default-type-ddd: architect-completeness-check.md に --type 未指定時のデフォルト ddd の記述がある" {
  # RED: --type パラメータが存在しないため fail
  run bash -c "
    grep -qE 'default.*ddd|ddd.*default|--type.*ddd|未指定.*ddd|ddd.*フォールバック' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3-backward-compat-no-type-break: co-architect SKILL.md に --type 未指定時の後方互換保証の記述がある" {
  # RED: --type パラメータが SKILL.md にまだ記述されていないため fail
  run bash -c "
    grep -qE 'default.*ddd|ddd.*default|後方互換|backward.*compat|--type.*省略' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3-ddd-default-in-ref-spec: ref-architecture-spec.md に ddd がデフォルト type として記述されている" {
  # RED: type 概念が存在しないため fail
  run bash -c "
    grep -qE 'ddd.*デフォルト|デフォルト.*ddd|default.*type.*ddd|ddd.*default' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: architect-completeness-check が --type=<value> 引数を受け取り対応列を動的選択
# ===========================================================================

@test "ac4-type-argument-defined: architect-completeness-check.md の入力に --type=<value> 引数が定義されている" {
  # RED: 現在 --type 引数が入力仕様に存在しないため fail
  run bash -c "
    grep -qE '\-\-type|type.*引数|type.*パラメータ|type.*parameter' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4-dynamic-column-selection: architect-completeness-check.md に type 別対応列の動的選択が記述されている" {
  # RED: 動的列選択の仕様が存在しないため fail
  run bash -c "
    grep -qE '動的.*選択|dynamic.*select|type.*列|対応列|column.*type' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4-adr032-table-driven-extension: architect-completeness-check.md に ADR-032 テーブル駆動拡張への言及がある" {
  # RED: ADR-032 テーブル駆動拡張の --type 対応が記述されていないため fail
  run bash -c "
    grep -qE 'ADR-032|テーブル駆動.*拡張|table-driven.*extension|--type.*ADR' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: --type 未指定時の解決順序: .architecture-type → vision.md frontmatter → ddd
# ===========================================================================

@test "ac5-resolve-order-architecture-type-file: architect-completeness-check.md に .architecture-type ファイルからの解決が記述されている" {
  # RED: type 解決順序の仕様が存在しないため fail
  run bash -c "
    grep -qE '\.architecture-type|architecture-type.*file|type.*file.*resolve' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac5-resolve-order-vision-frontmatter: architect-completeness-check.md に vision.md frontmatter からの解決が記述されている" {
  # RED: vision.md frontmatter からの type 解決が存在しないため fail
  run bash -c "
    grep -qE 'vision\.md.*frontmatter|frontmatter.*vision\.md|vision.*front.matter' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac5-resolve-priority-order: architect-completeness-check.md に .architecture-type → vision.md → ddd の解決順序が記述されている" {
  # RED: 解決順序の仕様が存在しないため fail
  run bash -c "
    grep -qE '\.architecture-type.*vision|vision.*ddd|解決.*順|priority.*order|フォールバック.*ddd' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: 未知の type (--type=foo) は明示エラーで停止
# ===========================================================================

@test "ac6-unknown-type-error: architect-completeness-check.md に未知の type が明示エラーで停止する記述がある" {
  # RED: type バリデーションの仕様が存在しないため fail
  run bash -c "
    grep -qE '未知.*type|unknown.*type|type.*不正|invalid.*type|type.*エラー|type.*error' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac6-unknown-type-error-in-spec: ref-architecture-spec.md に type 値の検証（値域定義）が記述されている" {
  # RED: type の値域定義が存在しないため fail
  run bash -c "
    grep -qE 'ddd|generic|lib' '${REF_ARCH_SPEC}' && \
    grep -qE '値域|allowed.*type|type.*valid|許容.*type' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: co-architect Step 2 メッセージに選択 type 名を表示
# ===========================================================================

@test "ac7-step2-type-display: co-architect SKILL.md の Step 2 に選択された type 名を表示する記述がある" {
  # RED: Step 2 の type 表示が SKILL.md に記述されていないため fail（現在の SKILL.md には --type 名表示がない）
  run bash -c "
    awk '/## Step 2/{found=1} found && /## Step 3/{exit} found{print}' '${CO_ARCHITECT_SKILL}' \
      | grep -qE 'type.*名.*表示|選択.*type|type.*選択.*表示|display.*type|type name.*shown|type.*メッセージ'
  "
  [ "${status}" -eq 0 ]
}

@test "ac7-step2-type-message-format: co-architect SKILL.md の Step 2 に type 名を含むメッセージフォーマット例がある" {
  # RED: type 名表示のフォーマット例が存在しないため fail
  run bash -c "
    awk '/## Step 2/{found=1} found && /## Step 3/{exit} found{print}' '${CO_ARCHITECT_SKILL}' \
      | grep -qE '\\$.*type|<type>|type_name|TYPE_NAME'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8: --type=generic 時の Step 2 プロンプトが vision.md + phases/*.md フローに切り替わる
# ===========================================================================

@test "ac8-generic-step2-phases-flow: co-architect SKILL.md に --type=generic 時の phases/*.md 設計フロー記述がある" {
  # RED: generic type の設計フロー分岐が SKILL.md に存在しないため fail
  run bash -c "
    grep -qE 'generic.*phases|phases.*generic|type.*generic.*phases|generic.*設計フロー' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac8-generic-no-bounded-context: co-architect SKILL.md に --type=generic 時は Bounded Context を使わない旨の記述がある" {
  # RED: generic type の DDD 非使用フロー分岐が存在しないため fail
  run bash -c "
    grep -qE 'generic.*Bounded Context.*使わ|generic.*スキップ.*DDD|DDD.*非使用.*generic|generic.*not.*DDD' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac8-generic-vision-phases-design: co-architect SKILL.md に --type=generic 時は vision.md + phases/*.md を中心とした設計の記述がある" {
  # RED: generic type 専用フローが存在しないため fail
  run bash -c "
    grep -qE 'generic.*vision\.md.*phases|vision.*phases.*generic' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC9: --group と --type 同時指定時は --group 優先、--type は --group 処理に引き継がれる
# ===========================================================================

@test "ac9-group-priority-over-type: co-architect SKILL.md の Step 0 に --group 優先の記述がある" {
  # RED: --type が Step 0 の --group 分岐に言及されていないため fail
  run bash -c "
    awk '/## Step 0/{found=1} found && /## Step 1/{exit} found{print}' '${CO_ARCHITECT_SKILL}' \
      | grep -qE '--group.*優先|--type.*引き継|--group.*--type|type.*group.*propagate'
  "
  [ "${status}" -eq 0 ]
}

@test "ac9-type-propagated-to-group: co-architect SKILL.md に --type が --group 処理内に引き継がれる記述がある" {
  # RED: --type の --group への引き継ぎ仕様が存在しないため fail
  run bash -c "
    grep -qE '\-\-type.*group.*refine|group.*refine.*type|--type.*引き継|type.*propagat' '${CO_ARCHITECT_SKILL}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC10: lib type の予約定義
# ===========================================================================

@test "ac10-lib-type-reserved: ref-architecture-spec.md に lib type の予約定義がある" {
  # RED: lib type の予約が存在しないため fail
  run bash -c "
    grep -qE '\blib\b.*予約|予約.*\blib\b|lib.*reserved|reserved.*lib|lib.*type.*future' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac10-lib-type-no-impl-yet: lib type の実装は将来予定として定義のみ（実装なし）" {
  # RED: lib type の予約が存在しないため fail
  run bash -c "
    grep -qE 'lib.*将来|lib.*future|lib.*実装.*予定|lib.*TBD|lib.*not.*impl' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac10-lib-not-in-validator: architect-completeness-check.md に lib type が実装済みとして扱われていない" {
  # RED: lib type 言及が現時点でなければ PASS（実装後に lib が完全実装として誤記録されていないことを確認）
  # このテストは「lib が実装されていないこと」を確認するため、lib が有効な type として処理されていないことを検証
  run bash -c "
    # lib が有効な type として --type=lib で実行可能と記述されていないこと
    if grep -qE '\-\-type=lib|lib.*type.*valid|lib.*許可' '${COMPLETENESS_CHECK_CMD}' 2>/dev/null; then
      echo 'FAIL: lib is implemented as valid type, but should be reserved only'
      exit 1
    fi
    exit 0
  "
  [ "${status}" -eq 0 ]
}
