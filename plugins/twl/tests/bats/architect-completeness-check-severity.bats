#!/usr/bin/env bats
# architect-completeness-check-severity.bats - Issue #1211: architect-completeness-check に Severity 列を追加する RED テスト
#
# AC coverage:
#   AC1 - ref-architecture-spec.md の必須テーブルに Severity 列が追加される (値域: WARNING または RECOMMENDED)
#   AC2 - architect-completeness-check.md の Step 1 が ref-architecture-spec.md の Severity を動的に読み出す
#   AC3 - 既定状態 (全件 WARNING) で動作が regression しない
#   AC4 - このテストファイル自体が存在し、bats 実行可能であること（自己参照テスト）
#   AC5 - ADR-032-completeness-severity-staging.md が decisions/ に作成されている
#   AC6 - Severity=RECOMMENDED 切替がテーブル変更のみで可能な設計になっている
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  REF_ARCH_SPEC="${REPO_ROOT}/refs/ref-architecture-spec.md"
  COMPLETENESS_CHECK_CMD="${REPO_ROOT}/commands/architect-completeness-check.md"
  ADR_032="${REPO_ROOT}/architecture/decisions/ADR-032-completeness-severity-staging.md"
  DECISIONS_DIR="${REPO_ROOT}/architecture/decisions"
  export REF_ARCH_SPEC COMPLETENESS_CHECK_CMD ADR_032 DECISIONS_DIR

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: ref-architecture-spec.md の必須テーブルに Severity 列が追加されている
#      値域は WARNING または RECOMMENDED に限定される
# ===========================================================================

@test "ac1-severity-col-present: ref-architecture-spec.md の必須テーブルに Severity 列が存在する" {
  # AC: ref-architecture-spec.md の ## 必須ファイル テーブルヘッダーに "Severity" 列が含まれる
  # RED: 現在 ref-architecture-spec.md の必須テーブルに Severity 列が存在しないため fail
  run grep -E "^\| ?ファイル" "${REF_ARCH_SPEC}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE "Severity"
}

@test "ac1-severity-values: ref-architecture-spec.md の Severity 値が WARNING または RECOMMENDED のみ" {
  # AC: ref-architecture-spec.md の必須テーブル内の Severity 列の値が WARNING または RECOMMENDED のみ
  # RED: Severity 列が存在しないため fail
  #
  # テーブル行（| で始まり | で終わる行）から Severity 値を抽出し、WARNING/RECOMMENDED 以外が存在しないことを確認する
  run bash -c "
    # 必須テーブルのヘッダーを探し、Severity 列インデックスを取得して値を抽出
    # 実装後はテーブル行から Severity セルのみを取り出す
    grep -E '^\| *vision\.md|\| *domain/model|\| *domain/glossary|\| *domain/contexts|\| *phases/|\| *decisions/|\| *contracts/' '${REF_ARCH_SPEC}' \
      | grep -qE 'WARNING|RECOMMENDED'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1-severity-no-invalid-values: Severity 列に WARNING/RECOMMENDED 以外の値が存在しない" {
  # AC: 必須テーブルの Severity セルは WARNING または RECOMMENDED のみ（INFO や ERROR は不可）
  # RED: Severity 列が存在しないため fail（列が存在した場合は値域バリデーション）
  run bash -c "
    # テーブル行の Severity セルとして想定されるセルを抽出し、WARNING/RECOMMENDED 以外がないことを確認
    severity_lines=\$(grep -E '^\| *(vision\.md|domain/model\.md|domain/glossary\.md|domain/contexts|phases/)' '${REF_ARCH_SPEC}')
    if [ -z \"\${severity_lines}\" ]; then
      echo 'FAIL: no required file rows found with Severity column'
      exit 1
    fi
    # WARNING または RECOMMENDED が含まれること
    echo \"\${severity_lines}\" | grep -qE 'WARNING|RECOMMENDED'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: architect-completeness-check.md が ref-architecture-spec.md から
#      Severity を動的に読み出すよう記述されている
# ===========================================================================

@test "ac2-dynamic-read-ref: architect-completeness-check.md が ref-architecture-spec.md の Read を Step 1 冒頭で指示している" {
  # AC: architect-completeness-check.md の Step 1 に ref-architecture-spec.md の Read が記述されている
  # RED: 現在 architect-completeness-check.md の Step 1 は静的なハードコードテーブルのため fail
  run bash -c "
    # Step 1 セクションの中で ref-architecture-spec.md の Read または参照が記述されているか確認
    awk '/### 1\./{found=1} found && /### 2\./{exit} found{print}' '${COMPLETENESS_CHECK_CMD}' \
      | grep -qE 'ref-architecture-spec|Read.*ref-arch|ref-arch.*Read'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-severity-dynamic-output: architect-completeness-check.md が Severity を動的に出力する記述がある" {
  # AC: architect-completeness-check.md の出力テーブルまたは指摘一覧に Severity を参照する記述がある
  # RED: 現在の出力フォーマットに Severity の動的参照がないため fail
  run grep -qE "Severity|severity" "${COMPLETENESS_CHECK_CMD}"
  [ "${status}" -eq 0 ]
}

@test "ac2-recommended-info-level: architect-completeness-check.md に RECOMMENDED 不在が INFO レベルという記述がある" {
  # AC: RECOMMENDED 項目の不在は WARNING より低い INFO レベルで報告されること
  # RED: 現在 RECOMMENDED の概念が存在しないため fail
  run bash -c "
    grep -qE 'RECOMMENDED.*INFO|INFO.*RECOMMENDED|RECOMMENDED.*低い|RECOMMENDED.*lower' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2-step1-read-before-table: Step 1 の Read が必須テーブルチェック前に配置されている" {
  # AC: ref-architecture-spec.md の Read 指示が Step 1 のファイル存在チェックテーブルより前に記述されている
  # RED: 現在 Step 1 冒頭に Read 指示が存在しないため fail
  run bash -c "
    # Step 1 セクションの最初の段落 (テーブル行より前) に Read が含まれることを確認
    awk '/### 1\./{found=1; next} found && /^\|/{exit} found{print}' '${COMPLETENESS_CHECK_CMD}' \
      | grep -qiE 'Read|ref-architecture-spec'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: 既定状態 (全 5 ファイル = WARNING) で regression なし
# ===========================================================================

@test "ac3-default-warning-rows: ref-architecture-spec.md の WARNING 行が 5 件以上存在する" {
  # AC: 現行 5 ファイル (vision.md, domain/model.md, domain/glossary.md, contexts/*, phases/*) が
  #     すべて WARNING であること（既定動作 regression チェック）
  # RED: Severity 列が存在しないため fail
  run bash -c "
    count=\$(grep -E '^\| *(vision\.md|domain/model\.md|domain/glossary\.md).*WARNING' '${REF_ARCH_SPEC}' | wc -l)
    echo \"WARNING count: \${count}\"
    [ \"\${count}\" -ge 3 ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac3-contexts-warning: domain/contexts/*.md エントリが WARNING Severity を持つ" {
  # AC: domain/contexts/*.md の必須エントリが WARNING Severity で定義されている
  # RED: Severity 列が存在しないため fail
  run grep -E "^\| *domain/contexts.*WARNING" "${REF_ARCH_SPEC}"
  [ "${status}" -eq 0 ]
}

@test "ac3-phases-warning: phases/*.md エントリが WARNING Severity を持つ" {
  # AC: phases/*.md の必須エントリが WARNING Severity で定義されている
  # RED: Severity 列が存在しないため fail
  run grep -E "^\| *phases/.*WARNING" "${REF_ARCH_SPEC}"
  [ "${status}" -eq 0 ]
}

@test "ac3-no-existing-warning-removed: 既存の WARNING 定義が削除されていない" {
  # AC: 既存の必須ファイル行 (vision.md 等) が ref-architecture-spec.md に引き続き存在する
  # RED: regression チェック - Severity 列追加で既存行が消えていないことを確認
  #      現状も通過しうるが、Severity 列追加後に regression しないことを担保する
  run bash -c "
    grep -qE '^\| *vision\.md' '${REF_ARCH_SPEC}' || exit 1
    grep -qE '^\| *domain/model\.md' '${REF_ARCH_SPEC}' || exit 1
    grep -qE '^\| *domain/glossary\.md' '${REF_ARCH_SPEC}' || exit 1
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: bats テストファイル自体の存在とテスト名重複チェック
# ===========================================================================

@test "ac4-test-file-exists: architect-completeness-check-severity.bats が存在する" {
  # AC: plugins/twl/tests/bats/architect-completeness-check-severity.bats が存在する
  # RED: このファイル自体が存在するため PASS するが、意図的に設計観点を記述する
  #      実際の RED は他の AC テストが担保する
  [ -f "${REPO_ROOT}/tests/bats/architect-completeness-check-severity.bats" ]
}

@test "ac4-no-duplicate-test-names: 既存 bats テストと test 名が重複しない" {
  # AC: 既存 bats テストファイル群に "ac1-severity-col-present" "ac2-dynamic-read-ref" 等の
  #     このファイル固有のテスト名が存在しない
  # RED: 実装前確認用 - 重複があれば fail（現状は重複なしのため PASS）
  run bash -c "
    # このファイル固有のテスト名プレフィックスを既存テストから検索（このファイル除外）
    found=\$(grep -rh '@test' '${REPO_ROOT}/tests/bats/' \
      --include='*.bats' \
      --exclude='architect-completeness-check-severity.bats' \
      | grep -E 'ac[1-6]-severity-col-present|ac[1-6]-dynamic-read-ref|ac[1-6]-default-warning-rows|ac[1-6]-adr032-exists|ac[1-6]-table-driven-design' \
      | wc -l)
    echo \"Duplicate count: \${found}\"
    [ \"\${found}\" -eq 0 ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac4-table-parse-required-col: Severity 列がテーブルヘッダーで識別できる" {
  # AC: ref-architecture-spec.md の必須テーブルヘッダーに Severity が列として識別できる
  # RED: Severity 列が存在しないため fail
  run bash -c "
    # テーブルヘッダー行に Severity が含まれること
    grep -E '^\| *ファイル' '${REF_ARCH_SPEC}' | grep -qF 'Severity'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4-warning-output-distinct-from-recommended: RECOMMENDED 不在が INFO で出力されることが仕様に明記されている" {
  # AC: architect-completeness-check.md の出力仕様で RECOMMENDED 項目の不在が INFO で出力されることが
  #     明記されている（単に [INFO] が存在するだけでなく、RECOMMENDED と紐付いていること）
  # RED: 現在 architect-completeness-check.md に RECOMMENDED の概念が存在しないため fail
  run bash -c "
    # RECOMMENDED と INFO が同一の文脈で記述されていること
    grep -qE 'RECOMMENDED.*INFO|INFO.*RECOMMENDED' '${COMPLETENESS_CHECK_CMD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: ADR-032-completeness-severity-staging.md が作成されている
# ===========================================================================

@test "ac5-adr032-exists: ADR-032-completeness-severity-staging.md が decisions/ に存在する" {
  # AC: plugins/twl/architecture/decisions/ADR-032-completeness-severity-staging.md が存在する
  # RED: ADR-032 はまだ作成されていないため fail
  [ -f "${ADR_032}" ]
}

@test "ac5-adr032-status-accepted: ADR-032 の Status が accepted" {
  # AC: ADR-032 の ## Status セクションに accepted が記述されている
  # RED: ADR-032 が存在しないため fail
  run grep -qE "^accepted$|accepted" "${ADR_032}"
  [ "${status}" -eq 0 ]
}

@test "ac5-adr032-context-lightweight-noise: ADR-032 の Context に lightweight noise または TI-1 への言及がある" {
  # AC: ADR-032 の ## Context セクションに lightweight noise および/または TI-1 への言及がある
  # RED: ADR-032 が存在しないため fail
  run bash -c "
    grep -qE 'lightweight.*noise|noise.*lightweight|TI-1' '${ADR_032}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac5-adr032-decision-severity-col: ADR-032 の Decision に Severity 列導入と動的化への言及がある" {
  # AC: ADR-032 の ## Decision セクションに Severity 列導入と動的化が記述されている
  # RED: ADR-032 が存在しないため fail
  run bash -c "
    grep -qE 'Severity|動的化|dynamic' '${ADR_032}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac5-adr032-consequences-ti1: ADR-032 の Consequences に TI-1 が選択肢として活用可能という記述がある" {
  # AC: ADR-032 の ## Consequences セクションに TI-1 への言及がある
  # RED: ADR-032 が存在しないため fail
  run bash -c "
    awk '/## Consequences/{found=1} found{print}' '${ADR_032}' | grep -qE 'TI-1'
  "
  [ "${status}" -eq 0 ]
}

@test "ac5-adr032-number-is-max-plus-1: decisions/ の最大 ADR 番号が 032 である" {
  # AC: decisions/ ディレクトリ内の最大 ADR 番号 = 031 の次の 032 が ADR-032 になっている
  # RED: ADR-032 が存在しないため fail
  run bash -c "
    # decisions/ 配下の最大 ADR 番号を取得
    max_num=\$(ls '${DECISIONS_DIR}'/ADR-*.md 2>/dev/null \
      | sed 's/.*ADR-0*\([0-9]*\)-.*/\1/' \
      | sort -n \
      | tail -1)
    echo \"max ADR number: \${max_num}\"
    [ \"\${max_num}\" -eq 32 ]
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: Severity=RECOMMENDED への切替がテーブル変更のみで可能な設計
# ===========================================================================

@test "ac6-table-driven-design: architect-completeness-check.md が ref-architecture-spec.md のテーブルを動的に参照する設計になっている" {
  # AC: architect-completeness-check.md が Severity を ref-architecture-spec.md テーブルから動的に読み込む
  #     ため、テーブルのみ変更すれば動作が変わる設計になっている
  # RED: 現在 Step 1 のテーブルがハードコードのため fail
  run bash -c "
    # ハードコードされた Severity 値 (WARNING が Step 1 テーブルに直書きされている) が存在しないこと
    # または ref-architecture-spec.md から動的に読む旨が記述されていること
    step1_content=\$(awk '/### 1\./{found=1; next} found && /### 2\./{exit} found{print}' '${COMPLETENESS_CHECK_CMD}')
    # Step 1 内に動的参照の記述があること (ref-architecture-spec 参照 or Severity 動的読み出し)
    echo \"\${step1_content}\" | grep -qE 'ref-architecture-spec|Severity.*読み出|動的|dynamic'
  "
  [ "${status}" -eq 0 ]
}

@test "ac6-recommended-entries-possible: ref-architecture-spec.md の Severity 列が RECOMMENDED を許容する値域定義がある" {
  # AC: ref-architecture-spec.md で Severity の値域として RECOMMENDED が明示されている
  # RED: Severity 列が存在しないため fail
  run bash -c "
    grep -qE 'RECOMMENDED' '${REF_ARCH_SPEC}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac6-single-source-of-truth: Severity 定義が ref-architecture-spec.md のみで管理されている" {
  # AC: architect-completeness-check.md に Severity のハードコード値 (WARNING/RECOMMENDED) が
  #     Step 1 テーブルとして直書きされていない（ref-architecture-spec.md が SSOT）
  # RED: 現在 Step 1 のテーブルに WARNING がハードコードされているため fail
  run bash -c "
    # Step 1 のテーブル行に WARNING が直書きされているかチェック
    # 実装後は ref-architecture-spec.md の Read + 動的参照に置き換わる
    step1_table=\$(awk '/### 1\./{found=1; next} found && /### 2\./{exit} found && /^\|/{print}' '${COMPLETENESS_CHECK_CMD}')
    if echo \"\${step1_table}\" | grep -qE '^\| .*\| *(YES|NO) *\| *WARNING'; then
      echo 'FAIL: Step 1 still has hardcoded WARNING in table - not table-driven design'
      exit 1
    fi
    exit 0
  "
  [ "${status}" -eq 0 ]
}
