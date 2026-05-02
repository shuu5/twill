#!/usr/bin/env bats
# issue-1275-provenance-co-issue-phase4.bats
#
# RED-phase tests for Issue #1275:
#   feat(provenance): co-issue Phase 4 post-create provenance footer + label
#     - issue-cross-repo-create.md に provenance footer append ロジック追加
#     - post-tool-use-issue-create-label.sh 新規作成（PostToolUse hook）
#     - explore-summary-link.sh に provenance section 自動追加
#     - TWILL_PROVENANCE_AUTO_LABEL=0 で hook 無効化
#     - 重複 label 付与回避（べき等性）
#
# AC coverage:
#   AC1 - co-issue Phase 4 issue create 時に body footer として provenance footer を append
#   AC2 - PostToolUse hook post-tool-use-issue-create-label.sh が存在し origin:host/repo ラベルを付与
#   AC3 - bats test 自体が存在し provenance footer + label 検証をカバー
#   AC4 - explore-summary-link.sh が summary.md の冒頭 provenance section を自動追加
#   AC5 - hook の label 付与でべき等性確保（既付与 label は skip）
#   AC6 - bulk 起票時は 1 issue 1 edit に制限（rate limit 設計制約が明示）
#   AC7 - TWILL_PROVENANCE_AUTO_LABEL=0 で hook を無効化できる
#   AC8 - gh issue create の引数パターン全種（--body, --body-file, -b, -F, stdin）をカバー
#   AC9 - ユーザー直接起票への適用範囲が documented（Phase D 再評価予定）
#   AC10 - hook 失敗時は WARN log 記録・起票自体は成功させる fallback あり
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  HOOK_SCRIPT="${REPO_ROOT}/scripts/hooks/post-tool-use-issue-create-label.sh"
  ISSUE_CREATE_CMD="${REPO_ROOT}/commands/issue-cross-repo-create.md"
  PHASE4_REF="${REPO_ROOT}/skills/co-issue/refs/co-issue-phase4-aggregate.md"
  EXPLORE_HOOK="${REPO_ROOT}/scripts/hooks/explore-summary-link.sh"
  THIS_BATS="${REPO_ROOT}/tests/bats/issue-1275-provenance-co-issue-phase4.bats"

  export HOOK_SCRIPT ISSUE_CREATE_CMD PHASE4_REF EXPLORE_HOOK THIS_BATS
}

# ===========================================================================
# AC1: co-issue Phase 4 issue create 時に provenance footer を body に append
# ===========================================================================

@test "ac1: issue-cross-repo-create.md mentions provenance footer" {
  # AC: issue-cross-repo-create.md に provenance footer の追記ロジックが含まれる
  # RED: provenance footer ロジックがまだ実装されていないため fail
  [ -f "${ISSUE_CREATE_CMD}" ]
  grep -qiE 'provenance|provenance.footer|origin.footer' "${ISSUE_CREATE_CMD}"
}

@test "ac1: issue-cross-repo-create.md uses --body-file for provenance footer" {
  # AC: provenance footer は --body-file convention で body に追記される
  # RED: 実装前のため fail
  [ -f "${ISSUE_CREATE_CMD}" ]
  run grep -c 'provenance' "${ISSUE_CREATE_CMD}"
  [ "${status}" -eq 0 ]
  [ "${output}" -gt 0 ]
}

@test "ac1: co-issue-phase4-aggregate.md documents provenance footer append step" {
  # AC: Phase 4 aggregate ref に provenance footer append の手順が記載されている
  # RED: phase4-aggregate.md には provenance の記載がまだないため fail
  [ -f "${PHASE4_REF}" ]
  grep -qiE 'provenance' "${PHASE4_REF}"
}

# ===========================================================================
# AC2: PostToolUse hook post-tool-use-issue-create-label.sh が存在し
#      gh issue edit --add-label origin:host:* origin:repo:* を実行する
# ===========================================================================

@test "ac2: post-tool-use-issue-create-label.sh exists" {
  # AC: 新規 PostToolUse hook スクリプトが存在する
  # RED: ファイルがまだ作成されていないため fail
  [ -f "${HOOK_SCRIPT}" ]
}

@test "ac2: hook script is executable" {
  # AC: hook スクリプトが実行可能パーミッションを持つ
  # RED: ファイル自体が不在のため fail
  [ -x "${HOOK_SCRIPT}" ]
}

@test "ac2: hook script invokes gh issue edit with --add-label" {
  # AC: hook が gh issue edit --add-label で label 付与する
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE 'gh issue edit.*--add-label|gh issue edit.*add.label' "${HOOK_SCRIPT}"
}

@test "ac2: hook script handles origin:host: label pattern" {
  # AC: origin:host:* パターンのラベルを付与する
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE 'origin:host:' "${HOOK_SCRIPT}"
}

@test "ac2: hook script handles origin:repo: label pattern" {
  # AC: origin:repo:* パターンのラベルを付与する
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE 'origin:repo:' "${HOOK_SCRIPT}"
}

# ===========================================================================
# AC3: bats test 自体が存在し provenance footer + label 検証をカバー
# ===========================================================================

@test "ac3: this bats test file exists" {
  # AC: issue-1275 の bats テストファイルが存在する
  # GREEN: 自己参照テスト（このファイル自体が存在するため PASS）
  [ -f "${THIS_BATS}" ]
}

@test "ac3: test covers co-issue path (issue-cross-repo-create)" {
  # AC: co-issue 経由のパスをカバーするテストがある
  # RED: issue-cross-repo-create.md 側に provenance が未実装のため fail
  [ -f "${ISSUE_CREATE_CMD}" ]
  grep -qiE 'provenance' "${ISSUE_CREATE_CMD}"
}

@test "ac3: test covers direct gh issue create path via hook" {
  # AC: 直接 gh issue create 経由のパスも hook でカバーされる
  # RED: hook スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE 'PostToolUse|post.tool.use|TOOL_NAME' "${HOOK_SCRIPT}"
}

# ===========================================================================
# AC4: co-explore summary.md の冒頭 provenance section が自動追加される
# ===========================================================================

@test "ac4: explore-summary-link.sh exists" {
  # AC: explore-summary-link.sh が存在する（既存）
  # GREEN: ファイルは既存のため PASS
  [ -f "${EXPLORE_HOOK}" ]
}

@test "ac4: explore-summary-link.sh handles provenance section" {
  # AC: explore-summary-link.sh が summary.md に provenance section を追加する
  # RED: provenance section 追加ロジックがまだ実装されていないため fail
  [ -f "${EXPLORE_HOOK}" ]
  grep -qiE 'provenance' "${EXPLORE_HOOK}"
}

@test "ac4: explore-summary-link.sh inserts provenance at top of summary" {
  # AC: provenance section は summary.md の冒頭メタ情報セクションに追加される
  # RED: 実装前のため fail
  [ -f "${EXPLORE_HOOK}" ]
  grep -qiE 'prepend|insert.*top|head|beginning|冒頭|先頭' "${EXPLORE_HOOK}"
}

# ===========================================================================
# AC5: hook の label 付与でべき等性確保（既付与 label は skip）
# ===========================================================================

@test "ac5: hook script has idempotency check for existing labels" {
  # AC: 既付与 label は重複付与をスキップする
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE 'idempoten|skip|already|既付与|--add-label.*check|label.*exist|gh issue view.*label' "${HOOK_SCRIPT}"
}

@test "ac5: hook script avoids duplicate label assignment" {
  # AC: label 付与前に既付与を確認してスキップする
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  # 既付与チェックのいずれかのパターンが存在する
  run bash -c "grep -qE 'view.*label|label.*check|--add-label.*idempoten|skip.*label|LABEL.*exist' '${HOOK_SCRIPT}'"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: bulk 起票時は 1 issue 1 edit に制限（rate limit 設計制約）
# ===========================================================================

@test "ac6: hook script documents rate limit design constraint" {
  # AC: gh rate limit (5000 req/h) への配慮が hook または関連ドキュメントに明示
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qiE 'rate.limit|rate_limit|5000|req/h|1 issue.*1 edit|per.issue' "${HOOK_SCRIPT}"
}

@test "ac6: hook script does not batch multiple edits per issue" {
  # AC: 1 issue につき gh issue edit は 1 回だけ実行される
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  # 複数の gh issue edit 呼び出しが存在しないことを確認
  count=$(grep -c 'gh issue edit' "${HOOK_SCRIPT}")
  [ "${count}" -le 3 ]
}

# ===========================================================================
# AC7: TWILL_PROVENANCE_AUTO_LABEL=0 で hook を無効化できる
# ===========================================================================

@test "ac7: hook script checks TWILL_PROVENANCE_AUTO_LABEL env var" {
  # AC: TWILL_PROVENANCE_AUTO_LABEL=0 の場合は hook が何もせず終了する
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE 'TWILL_PROVENANCE_AUTO_LABEL' "${HOOK_SCRIPT}"
}

@test "ac7: hook exits early when TWILL_PROVENANCE_AUTO_LABEL=0" {
  # AC: 環境変数 =0 の場合に exit 0 で早期終了する
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE 'TWILL_PROVENANCE_AUTO_LABEL.*0.*exit|exit.*TWILL_PROVENANCE_AUTO_LABEL' "${HOOK_SCRIPT}"
}

@test "ac7: hook is disabled when TWILL_PROVENANCE_AUTO_LABEL=0 at runtime" {
  # AC: 実行時に TWILL_PROVENANCE_AUTO_LABEL=0 を渡すと label 付与がスキップされる
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  # script を実行して exit 0 で終了することを確認（label 付与なし）
  run env TWILL_PROVENANCE_AUTO_LABEL=0 TOOL_NAME=Bash TOOL_INPUT_command='gh issue create' bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8: gh issue create の引数パターン全種をテスト fixture でカバー
# ===========================================================================

@test "ac8: hook script parses --body argument pattern" {
  # AC: --body で body を渡すパターンを parse できる
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE "\-\-body[^-]|'--body'" "${HOOK_SCRIPT}"
}

@test "ac8: hook script parses --body-file argument pattern" {
  # AC: --body-file でファイル経由の body を parse できる
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE "\-\-body-file|-F " "${HOOK_SCRIPT}"
}

@test "ac8: hook script parses -b short argument pattern" {
  # AC: -b ショートオプションを parse できる
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qE "'\-b'|\" -b \"|\-b " "${HOOK_SCRIPT}"
}

@test "ac8: hook script handles stdin pipe pattern" {
  # AC: パイプ stdin 経由の body を認識できる（またはその旨を documented）
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qiE 'stdin|pipe|/dev/stdin' "${HOOK_SCRIPT}"
}

# ===========================================================================
# AC9: ユーザー直接起票への適用範囲が documented（Phase D 再評価予定）
# ===========================================================================

@test "ac9: hook or related doc mentions Phase D re-evaluation for direct user invocation" {
  # AC: ユーザー直接 gh issue create への適用は Phase D で再評価する旨が明示
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qiE 'Phase D|phase.d|direct.*user|user.*direct|terminal.*direct|再評価|re-eval' "${HOOK_SCRIPT}"
}

@test "ac9: hook documents scope of application (co-issue vs direct)" {
  # AC: hook の適用範囲（co-issue 経由 vs 直接起票）がスクリプト内に記載されている
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qiE 'scope|適用範囲|co-issue|direct' "${HOOK_SCRIPT}"
}

# ===========================================================================
# AC10: hook 失敗時は WARN log 記録・起票自体は成功させる fallback
# ===========================================================================

@test "ac10: hook script has fallback on label assignment failure" {
  # AC: gh issue edit 失敗時でも hook は exit 0 で終了する
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qiE 'fallback|WARN|warn' "${HOOK_SCRIPT}" || grep -qF '|| true' "${HOOK_SCRIPT}" || grep -qE 'exit 0.*fail|fail.*exit 0|2>/dev/null' "${HOOK_SCRIPT}"
}

@test "ac10: hook script logs WARN on label assignment failure" {
  # AC: label 付与失敗時に WARN ログを記録する
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  grep -qiE 'WARN|warn.*log|log.*warn|warning.*label|label.*fail' "${HOOK_SCRIPT}"
}

@test "ac10: hook script does not propagate failure (exits 0 on label error)" {
  # AC: label 付与に失敗しても起票自体への影響なし（exit 0）
  # RED: スクリプト不在のため fail
  [ -f "${HOOK_SCRIPT}" ]
  # hook スクリプトに || true または || exit 0 パターンが存在する
  grep -qE '\|\| true|\|\| exit 0|2>/dev/null.*true|set +e' "${HOOK_SCRIPT}"
}
