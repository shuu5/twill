#!/usr/bin/env bats
# issue-1294-phase-b-migration-open-is.bats
#
# RED-phase tests for Issue #1294:
#   feat(adr-024): Phase B migration - open is:refined Issues を Status=Refined に移行
#
# AC coverage:
#   AC1 - PR description に Status=Todo の refined Issue 一覧が記載されている
#         (プロセス AC; migration script が --dry-run で対象を列挙できることを検証)
#   AC2 - project-board-refined-migrate.sh --force を実行すると対象 Issue が Status=Refined になる
#         (mock gh で実行ログが出力されることを検証)
#   AC3 - --force 実行後 Status=Todo / no-board の件数が 0 になっている
#         (mock gh で 0 件出力を検証)
#   AC4 - CI に --force 実行 step を含む workflow が存在する
#         (workflow ファイルの存在と内容を grep で確認)
#   AC5 - set_status_refined() 関数が migration script に組み込まれているか、
#         既存 GraphQL mutation で代替されている (重複排除)
#   AC6 - プロセス AC (epic #1 の AC1-AC7 達成); テストは false で skip
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  MIGRATE_SCRIPT="${REPO_ROOT}/scripts/project-board-refined-migrate.sh"
  export MIGRATE_SCRIPT

  # REPO_ROOT は plugins/twl; git root は 2 階層上（plugins/twl → plugins → worktree root）
  GIT_ROOT="$(cd "${REPO_ROOT}/../.." && pwd)"
  WORKFLOW_DIR="${GIT_ROOT}/.github/workflows"
  export WORKFLOW_DIR GIT_ROOT

  # stub bin: gh / jq のモックを配置する
  STUB_BIN="$(mktemp -d)"
  export STUB_BIN
  _ORIGINAL_PATH="$PATH"
  export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
  export PATH="$_ORIGINAL_PATH"
  if [[ -n "${STUB_BIN:-}" && -d "$STUB_BIN" ]]; then
    rm -rf "$STUB_BIN"
  fi
}

# ---------------------------------------------------------------------------
# gh stub helpers
# ---------------------------------------------------------------------------

# gh stub: refined label 付き OPEN Issue が存在するシナリオ
_stub_gh_with_refined_open_issues() {
  cat > "${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"project field-list"*)
    echo '{"fields":[{"name":"Status","options":[{"id":"3d983780","name":"Refined"}]}]}'
    ;;
  *"issue list"*"--json number,title"*)
    echo '[{"number":100,"title":"Issue A"},{"number":200,"title":"Issue B"}]'
    ;;
  *"project item-list"*)
    echo '{"items":[
      {"id":"PVTI_A","status":"Todo","content":{"number":100,"type":"Issue"}},
      {"id":"PVTI_B","status":"Todo","content":{"number":200,"type":"Issue"}}
    ]}'
    ;;
  *"api graphql"*"projectV2"*)
    echo '"PVT_kwtest123"'
    ;;
  *"project item-edit"*)
    echo "updated"
    ;;
  *)
    echo "gh stub: unmatched: $*" >&2
    exit 0
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"
}

# gh stub: refined label 付き OPEN Issue が 0 件のシナリオ (post-force 状態)
_stub_gh_no_remaining_issues() {
  cat > "${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"project field-list"*)
    echo '{"fields":[{"name":"Status","options":[{"id":"3d983780","name":"Refined"}]}]}'
    ;;
  *"issue list"*"--json number,title"*)
    echo '[]'
    ;;
  *"project item-list"*)
    echo '{"items":[]}'
    ;;
  *"api graphql"*"projectV2"*)
    echo '"PVT_kwtest123"'
    ;;
  *)
    echo "gh stub: unmatched: $*" >&2
    exit 0
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"
}

# ===========================================================================
# AC1: --dry-run で対象 Issue 一覧が列挙される
#      (PR description に記載するための情報が script から取得できる)
# ===========================================================================

@test "ac1: --dry-run mode lists target Issues without updating Status" {
  # AC: migration script の --dry-run モードが対象 Issue を stdout に列挙する
  # RED: 実装前は fail する
  _stub_gh_with_refined_open_issues
  run bash "${MIGRATE_SCRIPT}" --dry-run
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '#100|Issue A'
}

@test "ac1: --dry-run output contains 'dry-run' mode indicator" {
  # AC: --dry-run モード時に dry-run である旨の表示がある
  # RED: 実装前は fail する
  _stub_gh_with_refined_open_issues
  run bash "${MIGRATE_SCRIPT}" --dry-run
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qi 'dry.run'
}

@test "ac1: --dry-run does not call gh project item-edit" {
  # AC: --dry-run では item-edit が呼ばれない (Status 変更なし)
  # RED: 実装前は fail する
  local edit_log="${STUB_BIN}/item-edit.log"
  cat > "${STUB_BIN}/gh" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"project field-list"*)
    echo '{"fields":[{"name":"Status","options":[{"id":"3d983780","name":"Refined"}]}]}'
    ;;
  *"issue list"*"--json number,title"*)
    echo '[{"number":100,"title":"Issue A"}]'
    ;;
  *"project item-list"*)
    echo '{"items":[{"id":"PVTI_A","status":"Todo","content":{"number":100,"type":"Issue"}}]}'
    ;;
  *"api graphql"*"projectV2"*)
    echo '"PVT_kwtest123"'
    ;;
  *"project item-edit"*)
    echo "item-edit called" >> "${edit_log}"
    echo "updated"
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"

  run bash "${MIGRATE_SCRIPT}" --dry-run
  [ "${status}" -eq 0 ]
  # item-edit が呼ばれていないこと
  [ ! -f "${edit_log}" ]
}

# ===========================================================================
# AC2: --force で対象 Issue 全件が Status=Refined に更新される
# ===========================================================================

@test "ac2: --force mode exits 0 with refined issues present" {
  # AC: --force 実行時に exit 0 で完了する
  # RED: 実装前は fail する
  _stub_gh_with_refined_open_issues
  run bash "${MIGRATE_SCRIPT}" --force
  [ "${status}" -eq 0 ]
}

@test "ac2: --force mode output shows issues updated to Refined" {
  # AC: --force 実行ログに「Refined」への更新が記録されている
  # RED: 実装前は fail する
  _stub_gh_with_refined_open_issues
  run bash "${MIGRATE_SCRIPT}" --force
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qiE 'Refined|refined'
}

@test "ac2: --force mode calls gh project item-edit for each target issue" {
  # AC: --force 実行時に gh project item-edit が対象件数分呼ばれる
  # RED: 実装前は fail する
  local edit_log="${STUB_BIN}/item-edit.log"
  cat > "${STUB_BIN}/gh" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"project field-list"*)
    echo '{"fields":[{"name":"Status","options":[{"id":"3d983780","name":"Refined"}]}]}'
    ;;
  *"issue list"*"--json number,title"*)
    echo '[{"number":100,"title":"Issue A"},{"number":200,"title":"Issue B"}]'
    ;;
  *"project item-list"*)
    echo '{"items":[
      {"id":"PVTI_A","status":"Todo","content":{"number":100,"type":"Issue"}},
      {"id":"PVTI_B","status":"Todo","content":{"number":200,"type":"Issue"}}
    ]}'
    ;;
  *"api graphql"*"projectV2"*)
    echo '"PVT_kwtest123"'
    ;;
  *"project item-edit"*)
    echo "item-edit called" >> "${edit_log}"
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"

  run bash "${MIGRATE_SCRIPT}" --force
  [ "${status}" -eq 0 ]
  # 2 件の item-edit が呼ばれていること
  local edit_count
  edit_count=$(wc -l < "${edit_log}" 2>/dev/null || echo 0)
  [ "${edit_count}" -ge 2 ]
}

@test "ac2: --force mode passes REFINED_OPTION_ID to item-edit" {
  # AC: item-edit 呼び出しに Refined option ID (3d983780) が渡される
  # RED: 実装前は fail する
  local edit_args_log="${STUB_BIN}/item-edit-args.log"
  cat > "${STUB_BIN}/gh" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"project field-list"*)
    echo '{"fields":[{"name":"Status","options":[{"id":"3d983780","name":"Refined"}]}]}'
    ;;
  *"issue list"*"--json number,title"*)
    echo '[{"number":100,"title":"Issue A"}]'
    ;;
  *"project item-list"*)
    echo '{"items":[{"id":"PVTI_A","status":"Todo","content":{"number":100,"type":"Issue"}}]}'
    ;;
  *"api graphql"*"projectV2"*)
    echo '"PVT_kwtest123"'
    ;;
  *"project item-edit"*)
    echo "\$@" >> "${edit_args_log}"
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"

  run bash "${MIGRATE_SCRIPT}" --force
  [ "${status}" -eq 0 ]
  grep -q "3d983780" "${edit_args_log}"
}

# ===========================================================================
# AC3: --force 実行後 Status=Todo / no-board の件数が 0 になっている
# ===========================================================================

@test "ac3: after --force, migration script reports 0 remaining non-refined issues" {
  # AC: --force 実行後に再確認すると 0 件
  # RED: 実装前は fail する (no-board 件数が 0 であることの確認が未実装)
  _stub_gh_no_remaining_issues
  run bash "${MIGRATE_SCRIPT}" --force
  [ "${status}" -eq 0 ]
  # 対象 0 件で正常終了すること
  echo "${output}" | grep -qiE '0 件|migration scope = 0|正常終了'
}

@test "ac3: script is idempotent - already-Refined issues are skipped" {
  # AC: 既に Status=Refined の Issue は冪等にスキップされる
  # RED: 実装前は fail する
  cat > "${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"project field-list"*)
    echo '{"fields":[{"name":"Status","options":[{"id":"3d983780","name":"Refined"}]}]}'
    ;;
  *"issue list"*"--json number,title"*)
    echo '[{"number":100,"title":"Issue A"}]'
    ;;
  *"project item-list"*)
    echo '{"items":[{"id":"PVTI_A","status":"Refined","content":{"number":100,"type":"Issue"}}]}'
    ;;
  *"api graphql"*"projectV2"*)
    echo '"PVT_kwtest123"'
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"

  run bash "${MIGRATE_SCRIPT}" --force
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qiE 'スキップ|skip'
}

@test "ac3: script handles no-board issues gracefully without error" {
  # AC: Board 未登録の Issue がある場合も exit 0 で完了する
  # RED: 実装前は fail する
  cat > "${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"project field-list"*)
    echo '{"fields":[{"name":"Status","options":[{"id":"3d983780","name":"Refined"}]}]}'
    ;;
  *"issue list"*"--json number,title"*)
    echo '[{"number":999,"title":"Not on board"}]'
    ;;
  *"project item-list"*)
    # 999 は board に存在しない
    echo '{"items":[]}'
    ;;
  *"api graphql"*"projectV2"*)
    echo '"PVT_kwtest123"'
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"

  run bash "${MIGRATE_SCRIPT}" --force
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qiE 'Board 未登録|not.*board|no.*board'
}

# ===========================================================================
# AC4: CI に --force 実行 step を含む workflow が存在する
# ===========================================================================

@test "ac4: CI workflow file for phase-b-migration exists" {
  # AC: .github/workflows/ 配下に phase-b-migration 関連の workflow が存在する
  # RED: 実装前は fail する (workflow ファイルが未作成)
  local found
  found=$(find "${WORKFLOW_DIR}" -name "*.yml" -o -name "*.yaml" 2>/dev/null \
    | xargs grep -l "project-board-refined-migrate" 2>/dev/null | head -1)
  [ -n "${found}" ]
}

@test "ac4: CI workflow contains --force flag invocation" {
  # AC: workflow に --force フラグ付きの migration script 実行 step が含まれる
  # RED: 実装前は fail する
  local found
  found=$(find "${WORKFLOW_DIR}" -name "*.yml" -o -name "*.yaml" 2>/dev/null \
    | xargs grep -l "project-board-refined-migrate" 2>/dev/null | head -1)
  [ -n "${found}" ]
  grep -q "\-\-force" "${found}"
}

@test "ac4: CI workflow is triggered on pull_request or push events" {
  # AC: workflow が PR merge 時に発火するトリガー (pull_request, push, workflow_run 等) を持つ
  # RED: 実装前は fail する
  local found
  found=$(find "${WORKFLOW_DIR}" -name "*.yml" -o -name "*.yaml" 2>/dev/null \
    | xargs grep -l "project-board-refined-migrate" 2>/dev/null | head -1)
  [ -n "${found}" ]
  grep -qE "pull_request|push:|workflow_run" "${found}"
}

# ===========================================================================
# AC5: set_status_refined() 関数が migration script に組み込まれているか、
#      既存 GraphQL mutation で代替されている (重複排除)
# ===========================================================================

@test "ac5: migration script contains set_status_refined function (explore 7.1 formalized)" {
  # AC: explore section 7.1 の set_status_refined() 関数が migration script に組み込まれている
  # RED: 実装前は fail する (現状スクリプトに set_status_refined 関数が未定義)
  grep -qE 'set_status_refined\(\)' "${MIGRATE_SCRIPT}"
}

@test "ac5: set_status_refined function is not duplicated elsewhere in plugin scripts" {
  # AC: set_status_refined() が migration script 以外の場所で重複定義されていない
  # RED: 実装前は fail する (探索対象ファイルが増えた場合に重複が検出される)
  local dup_count
  dup_count=$(grep -rl "set_status_refined" "${REPO_ROOT}/scripts/" 2>/dev/null | wc -l || echo 0)
  # 0 件 (未定義) または 1 件 (migration script のみ) であれば OK
  [ "${dup_count}" -le 1 ]
}

@test "ac5: jq validation query uses REFINED_OPTION_ID variable not hardcoded string" {
  # AC: jq の option ID 検証が $REFINED_OPTION_ID を参照し、リテラル "3d983780" を直接 jq 式に埋め込まない
  # RED: 実装前は fail する (現状は jq 式内にリテラルが残っている)
  # 現状: select(.id=="3d983780") → 修正後: $refined_id 等の変数参照になること
  local jq_hardcoded
  jq_hardcoded=$(grep -c 'select(.id=="3d983780")' "${MIGRATE_SCRIPT}" 2>/dev/null || true)
  [ "${jq_hardcoded:-1}" -eq 0 ]
}

# ===========================================================================
# AC6: epic #1 (Parent) の AC1-AC7 が全て満たされている
#      プロセス AC のため、機械的テストは不可。RED で skip する。
# ===========================================================================

@test "ac6: epic parent AC1-AC7 all satisfied (process AC - skipped)" {
  # AC: epic #1 の AC1-AC7 が全て満たされている
  # プロセス AC: 実装で検証できないため false で RED を維持
  false  # RED: プロセス AC のため自動検証不可
}
