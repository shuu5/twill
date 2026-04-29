#!/usr/bin/env bats
# glossary-architecture-drift-1095.bats
#
# RED-phase tests for Issue #1095:
#   Tech-debt: glossary.md MUST 用語テーブルに architecture-drift を追加する
#
# AC coverage:
#   AC1 - glossary.md の MUST 用語テーブルに architecture-drift 行が存在する
#   AC2 - architecture-drift 行の Context 列が PR Cycle を含む
#   AC3 - architecture-drift 行の定義が ref-specialist-output-schema.md の
#          worker-architecture category 用途と整合する
#   AC4 - grep -nF 'architecture-drift' glossary.md の出力が 1 件以上
#   AC5 - SHOULD 用語 'architecture drift detection' が変わらず存在する（削除なし）
#   AC6 - twl check が PASS する
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  GLOSSARY="${REPO_ROOT}/architecture/domain/glossary.md"
  export GLOSSARY

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: MUST 用語テーブルに architecture-drift 行が追加されている
#
# ### MUST 用語 直下の | 用語 | 定義 | Context | テーブル（line 5-44 範囲）に
# architecture-drift 行が存在することを確認する
# ===========================================================================

@test "ac1: glossary.md MUST 用語テーブルに architecture-drift 行が存在する" {
  # AC: plugins/twl/architecture/domain/glossary.md の MUST 用語テーブル
  #     (### MUST 用語 直下の | 用語 | 定義 | Context | テーブル) に
  #     architecture-drift 行が追加されている
  # RED: 実装前は MUST テーブルに architecture-drift が存在しないため fail
  run bash -c "
    file='${GLOSSARY}'
    # ### MUST 用語 セクションの開始行を特定
    must_start=\$(grep -n '### MUST 用語' \"\${file}\" | head -1 | cut -d: -f1)
    [ -n \"\${must_start}\" ] || exit 1
    # ### SHOULD 用語 セクションの開始行を特定（MUST テーブルの終端として使用）
    should_start=\$(grep -n '### SHOULD 用語' \"\${file}\" | head -1 | cut -d: -f1)
    [ -n \"\${should_start}\" ] || exit 1
    # MUST テーブル内（must_start から should_start の間）に architecture-drift が存在するか
    awk -v s=\"\${must_start}\" -v e=\"\${should_start}\" \
      'NR > s && NR < e && /architecture-drift/ {found=1; exit} END {exit !found}' \
      \"\${file}\"
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: architecture-drift 行の Context 列が PR Cycle を含む
#
# worker-architecture specialist は merge-gate 配下のため Context = PR Cycle
# ===========================================================================

@test "ac2: architecture-drift 行の Context 列が PR Cycle を含む" {
  # AC: 追加行の Context 列が PR Cycle を含む
  # RED: 実装前は当該行自体が存在しないため fail
  run grep -F 'architecture-drift' "${GLOSSARY}"
  [ "${status}" -eq 0 ]
  # 取得した行が PR Cycle を含むことを確認
  [[ "${output}" == *"PR Cycle"* ]]
}

# ===========================================================================
# AC3: 定義が ref-specialist-output-schema.md の architecture-drift 用途と整合する
#
# ref-specialist-output-schema.md では:
#   architecture-drift → worker-architecture specialist が使用する category 値
# 定義文が worker-architecture または architecture spec に言及していることを確認
# ===========================================================================

@test "ac3: architecture-drift 行の定義が worker-architecture specialist の用途と整合する" {
  # AC: 追加行の定義が ref-specialist-output-schema.md の architecture-drift 用途
  #     （worker-architecture specialist の category 値）と整合する
  # RED: 実装前は当該行が存在しないため fail
  run grep -F 'architecture-drift' "${GLOSSARY}"
  [ "${status}" -eq 0 ]
  # 定義列に worker-architecture またはアーキテクチャ spec への言及が含まれること
  [[ "${output}" =~ worker.architecture || "${output}" =~ architecture.*spec || "${output}" =~ specialist ]]
}

# ===========================================================================
# AC4: grep -nF 'architecture-drift' glossary.md の出力が 1 件以上
# ===========================================================================

@test "ac4: grep -nF architecture-drift glossary.md の出力が 1 件以上" {
  # AC: grep -nF 'architecture-drift' plugins/twl/architecture/domain/glossary.md の
  #     出力が 1 件以上（MUST 用語テーブル内に新規行が出現）
  # RED: 実装前は architecture-drift（ハイフン付き）が MUST テーブルに存在しないため fail
  run grep -nF 'architecture-drift' "${GLOSSARY}"
  [ "${status}" -eq 0 ]
  # 少なくとも 1 件マッチしていること
  local count
  count="$(echo "${output}" | grep -c 'architecture-drift')"
  [ "${count}" -ge 1 ]
}

# ===========================================================================
# AC5: SHOULD 用語 'architecture drift detection' が削除・変更されていない
#
# grep -c 'architecture drift detection' の結果が変わらない（= 1 を維持）
# ===========================================================================

@test "ac5: SHOULD 用語 'architecture drift detection' が削除・変更されていない" {
  # AC: grep -c 'architecture drift detection' plugins/twl/architecture/domain/glossary.md
  #     が変わらない（既存 SHOULD 用語の rename・削除を行わないことの確認）
  # PASS 基準: 現在 line 75 に存在するため、count >= 1 で PASS
  # RED: 本 AC のみ実装前でも PASS 可能だが、他 AC の実装で誤って削除された場合に
  #      regression を検知するためテストを含める
  run grep -c 'architecture drift detection' "${GLOSSARY}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

# ===========================================================================
# AC6: twl check が PASS する
# ===========================================================================

@test "ac6: twl check が PASS する" {
  # AC: twl check が PASS する（glossary.md 追加後の整合性検証）
  # RED: 実装前は architecture-drift が MUST テーブルに存在しないため
  #      glossary 照合ルールによって fail する可能性がある
  #      （または twl check 自体が glossary 追加後の状態を要求する場合）
  run bash -c "cd '${REPO_ROOT}' && twl check"
  [ "${status}" -eq 0 ]
}
