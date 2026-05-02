#!/usr/bin/env bats
# issue-1275-provenance-phase4.bats
#
# RED-phase static content tests for Issue #1275:
#   feat(provenance): co-issue Phase 4 + PostToolUse hook で provenance label 自動付与
#
# AC coverage:
#   AC1  - co-issue-phase4-aggregate.md に provenance footer append 記述が存在すること
#   AC2  - post-tool-use-issue-create-label.sh が新規作成され gh issue edit --add-label origin:host:* を実行すること
#   AC3  - provenance footer + label が co-issue 経由 / 直接 gh issue create 経由 両方で付与されること
#   AC4  - explore-summary-link.sh が summary.md 書き込み時に provenance section を自動追加すること
#   AC5  - label 重複付与回避: 既付与 label は skip (べき等性確保)
#   AC6  - bulk 起票時は 1 issue 1 edit に制限 (rate limit 設計)
#   AC7  - hook ON/OFF 切り替え機構: TWILL_PROVENANCE_AUTO_LABEL=0 で disable
#   AC8  - gh issue create の引数 parse: --body / --body-file / -b / -F / パイプ stdin 全パターン
#   AC9  - ユーザー直接起票への適用範囲が documented (Phase D 再評価旨の記述)
#   AC10 - hook 失敗時 fallback: label 付与失敗を WARN log に記録、起票は成功させること
#
# RED 状態の根拠:
#   AC1:  co-issue-phase4-aggregate.md に provenance footer append 記述が存在しない
#   AC2:  plugins/twl/scripts/hooks/post-tool-use-issue-create-label.sh が未存在
#   AC3:  hook が存在しないため label 付与テストも fail
#   AC4:  explore-summary-link.sh に provenance section 追加ロジックが存在しない
#   AC5:  hook が存在しないため重複付与回避ロジックも存在しない
#   AC6:  hook が存在しないため 1 issue 1 edit 制限も検証不能
#   AC7:  hook が存在しないため TWILL_PROVENANCE_AUTO_LABEL env var チェックも存在しない
#   AC8:  hook が存在しないため引数 parse テストも fail
#   AC9:  適用範囲ドキュメントが未存在
#   AC10: hook が存在しないため fallback ロジックも存在しない

load 'helpers/common'

PHASE4_AGGREGATE=""
HOOK_SCRIPT=""
EXPLORE_LINK_HOOK=""
ORCHESTRATOR=""

setup() {
  common_setup

  # REPO_ROOT は plugins/twl/ を指す（helpers/common.bash の定義に準拠）
  PHASE4_AGGREGATE="${REPO_ROOT}/skills/co-issue/refs/co-issue-phase4-aggregate.md"
  HOOK_SCRIPT="${REPO_ROOT}/scripts/hooks/post-tool-use-issue-create-label.sh"
  EXPLORE_LINK_HOOK="${REPO_ROOT}/scripts/hooks/explore-summary-link.sh"
  ORCHESTRATOR="${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"

  export PHASE4_AGGREGATE HOOK_SCRIPT EXPLORE_LINK_HOOK ORCHESTRATOR
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: co-issue Phase 4 issue create 時に provenance footer を append する記述があること
# ===========================================================================

@test "ac1: co-issue-phase4-aggregate.md が存在すること" {
  # 前提確認: ファイルが存在する
  [ -f "${PHASE4_AGGREGATE}" ]
}

@test "ac1: co-issue-phase4-aggregate.md に provenance footer append 記述が存在すること（RED: 現状は未実装）" {
  # AC: Phase 4 issue create 時に body footer として provenance footer を append する記述
  # RED: 現在 co-issue-phase4-aggregate.md に provenance footer の記述が存在しないため fail
  run grep -c 'provenance' "${PHASE4_AGGREGATE}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に provenance footer 記述が存在しない（AC1 未実装）" >&2
    return 1
  fi
}

@test "ac1: co-issue-phase4-aggregate.md に --body-file convention による provenance footer 記述が存在すること（RED）" {
  # AC: --body-file convention で provenance footer を append する実装指示
  # RED: 現状は --body-file に provenance footer append の記述がないため fail
  run grep -cE 'provenance.*(footer|append)|body.*(provenance|origin:|host:)' "${PHASE4_AGGREGATE}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に --body-file + provenance footer append 記述が存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC2: PostToolUse hook で gh issue edit --add-label origin:host:* origin:repo:* を実行すること
# ===========================================================================

@test "ac2: post-tool-use-issue-create-label.sh が存在すること（RED: 新規ファイル未存在）" {
  # AC: PostToolUse hook スクリプト新規作成
  # RED: 現在ファイルが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: ${HOOK_SCRIPT} が存在しない（AC2 未実装: 新規ファイル作成が必要）" >&2
    return 1
  fi
}

@test "ac2: post-tool-use-issue-create-label.sh に gh issue edit --add-label origin:host: 記述が存在すること（RED）" {
  # AC: hook スクリプトが gh issue edit --add-label origin:host:* を実行する
  # RED: スクリプトが存在しないため fail（ファイル存在チェックで先行 fail）
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（先行条件 AC2 未実装）" >&2
    return 1
  fi
  run grep -cE 'gh issue edit.*--add-label.*origin:host:|--add-label.*origin:host:' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に gh issue edit --add-label origin:host: 記述が存在しない" >&2
    return 1
  fi
}

@test "ac2: post-tool-use-issue-create-label.sh に origin:repo: label 付与記述が存在すること（RED）" {
  # AC: hook スクリプトが origin:repo:* label も付与する
  # RED: スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（先行条件 AC2 未実装）" >&2
    return 1
  fi
  run grep -cE 'origin:repo:' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に origin:repo: label 付与記述が存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC3: bats test で provenance footer + label が co-issue 経由 / 直接 gh issue create 経由 両方で付与されること
# ===========================================================================

@test "ac3: hook スクリプトが co-issue 経由の issue create を検知できること（RED）" {
  # AC: co-issue 経由での gh issue create に対して hook が適用される
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC3 co-issue 経由パス 未実装）" >&2
    return 1
  fi
  # hook が tool_output から issue URL / number を抽出するロジックを持つこと
  run grep -cE 'TOOL_RESULT|tool_result|tool_output|issue_url|issue_number|ISSUE_NUM|ISSUE_URL' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に tool_result/issue URL 抽出ロジックが存在しない（co-issue 経由検知不能）" >&2
    return 1
  fi
}

@test "ac3: hook スクリプトが直接 gh issue create 経由も処理できること（RED）" {
  # AC: 直接 gh issue create 経由の起票にも hook が適用される
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC3 直接 gh issue create 経由パス 未実装）" >&2
    return 1
  fi
  # hook が Bash ツール経由の gh issue create を検知するロジックを持つこと
  run grep -cE 'tool_name|TOOL_NAME|Bash|bash' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に Bash ツール経由の gh issue create 検知ロジックが存在しない" >&2
    return 1
  fi
}

@test "ac3: provenance footer テンプレートに origin:host: と origin:repo: が含まれること（RED）" {
  # AC: provenance footer に origin:host:* と origin:repo:* の記述が含まれる
  # RED: phase4-aggregate.md に provenance footer が存在しないため fail
  run grep -cE 'origin:host:|origin:repo:' "${PHASE4_AGGREGATE}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に origin:host: / origin:repo: の記述が存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC4: explore-summary-link.sh が summary.md 書き込み時に provenance section を自動追加すること
# ===========================================================================

@test "ac4: explore-summary-link.sh が存在すること" {
  # 前提確認: ファイルが存在する
  [ -f "${EXPLORE_LINK_HOOK}" ]
}

@test "ac4: explore-summary-link.sh に provenance section 追加ロジックが存在すること（RED: 現状は未実装）" {
  # AC: summary.md 書き込み後に provenance section が自動追加される
  # RED: 現在 explore-summary-link.sh に provenance section 追加ロジックが存在しないため fail
  run grep -cE 'provenance|origin:host:|origin:repo:|## Provenance' "${EXPLORE_LINK_HOOK}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: explore-summary-link.sh に provenance section 追加ロジックが存在しない（AC4 未実装）" >&2
    return 1
  fi
}

@test "ac4: explore-summary-link.sh で summary.md に provenance メタ情報セクションが書き込まれること（RED）" {
  # AC: summary.md 冒頭メタ情報セクションに provenance section が自動追加される
  # RED: 現在 explore-summary-link.sh に provenance section の書き込みコードが存在しないため fail
  run grep -cE 'summary\.md.*provenance|provenance.*summary\.md|write.*provenance|append.*provenance' "${EXPLORE_LINK_HOOK}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: explore-summary-link.sh に summary.md への provenance section 書き込みコードが存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC5: label 重複付与回避: 既付与 label は skip (べき等性確保)
# ===========================================================================

@test "ac5: hook スクリプトに既存 label チェックロジックが存在すること（RED）" {
  # AC: 既付与 label は skip してべき等性を確保する
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC5 重複付与回避 未実装）" >&2
    return 1
  fi
  # 既存 label を取得して重複チェックするロジック
  run grep -cE 'gh issue view.*label|existing.*label|label.*exist|skip.*label|idempotent|冪等' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に既存 label チェック（べき等性）ロジックが存在しない" >&2
    return 1
  fi
}

@test "ac5: hook スクリプトで origin:host: が既付与の場合は gh issue edit をスキップすること（RED）" {
  # AC: origin:host:* label が既に付与されている場合は re-attach をスキップする
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC5 skip ロジック 未実装）" >&2
    return 1
  fi
  # skip / continue / return 0 のパターン確認
  run grep -cE 'skip|already.*label|label.*already|continue|exit 0' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に重複時 skip ロジックが存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC6: bulk 起票時は 1 issue 1 edit に制限 (rate limit 5000 req/h 設計)
# ===========================================================================

@test "ac6: hook スクリプトで 1 issue につき 1 回の gh issue edit に制限されること（RED）" {
  # AC: bulk 起票時も 1 issue 1 edit に制限して rate limit に抵触しない設計
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC6 rate limit 設計 未実装）" >&2
    return 1
  fi
  # 複数 label を一括付与する設計: gh issue edit に --add-label を一度だけ呼ぶ
  # ループで複数回 gh issue edit を呼ばないことを確認（label を空白区切りで一括付与）
  local edit_count
  edit_count=$(grep -cE 'gh issue edit.*--add-label' "${HOOK_SCRIPT}" 2>/dev/null || echo "0")
  # 実装後は 1 箇所のみの gh issue edit コール（label は一括で渡す）
  if [ "${edit_count}" -gt 1 ]; then
    echo "FAIL: hook に gh issue edit --add-label が ${edit_count} 箇所存在する（1 issue 1 edit 制限違反）" >&2
    grep -nE 'gh issue edit.*--add-label' "${HOOK_SCRIPT}" >&2 || true
    return 1
  fi
  # edit_count=0 は未実装（hook が存在しない場合は上記チェックで先行 fail）
  if [ "${edit_count}" -eq 0 ]; then
    echo "FAIL: hook に gh issue edit --add-label が存在しない（AC6 未実装）" >&2
    return 1
  fi
}

@test "ac6: issue-lifecycle-orchestrator.sh に bulk 起票時の rate limit 考慮記述があること（RED）" {
  # AC: bulk 起票設計で rate limit コメントまたは制御ロジックが存在する
  # RED: orchestrator に rate limit / provenance 関連の記述が存在しないため fail
  run grep -cE 'rate.limit|provenance|origin:host:|origin:repo:|post-tool-use-issue-create-label' "${ORCHESTRATOR}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: issue-lifecycle-orchestrator.sh に rate limit / provenance 関連の記述が存在しない（AC6 未実装）" >&2
    return 1
  fi
}

# ===========================================================================
# AC7: hook ON/OFF 切り替え機構 (TWILL_PROVENANCE_AUTO_LABEL=0 で disable)
# ===========================================================================

@test "ac7: hook スクリプトに TWILL_PROVENANCE_AUTO_LABEL env var チェックが存在すること（RED）" {
  # AC: TWILL_PROVENANCE_AUTO_LABEL=0 で hook を disable できる機構
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC7 ON/OFF 切り替え機構 未実装）" >&2
    return 1
  fi
  run grep -cE 'TWILL_PROVENANCE_AUTO_LABEL' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に TWILL_PROVENANCE_AUTO_LABEL env var チェックが存在しない" >&2
    return 1
  fi
}

@test "ac7: TWILL_PROVENANCE_AUTO_LABEL=0 時に hook が exit 0 で即終了すること（RED）" {
  # AC: TWILL_PROVENANCE_AUTO_LABEL=0 の場合 hook は何もせず終了する
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC7 disable 機構 未実装）" >&2
    return 1
  fi
  # TWILL_PROVENANCE_AUTO_LABEL チェック後に exit 0 / return 0 があること
  run grep -A3 'TWILL_PROVENANCE_AUTO_LABEL' "${HOOK_SCRIPT}"
  if ! echo "${output}" | grep -qE 'exit 0|return 0|\[ .* \].*exit'; then
    echo "FAIL: TWILL_PROVENANCE_AUTO_LABEL=0 時の exit 0 ロジックが存在しない" >&2
    return 1
  fi
}

@test "ac7: stub で TWILL_PROVENANCE_AUTO_LABEL=0 を設定した場合 hook が label 付与をスキップすること（RED）" {
  # AC: 実際に env var 設定で hook の disable を確認
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC7 動作テスト 未実装）" >&2
    return 1
  fi

  # gh コマンド stub: 呼ばれたら fail（label 付与が呼ばれていないことを確認）
  stub_command "gh" 'echo "FAIL: gh was called despite TWILL_PROVENANCE_AUTO_LABEL=0" >&2; exit 1'

  # hook を TWILL_PROVENANCE_AUTO_LABEL=0 で実行
  export TWILL_PROVENANCE_AUTO_LABEL=0
  run bash "${HOOK_SCRIPT}" <<'EOF'
{}
EOF
  # gh が呼ばれていなければ成功（exit 0 で返るはず）
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8: gh issue create の引数 parse: --body / --body-file / -b / -F / パイプ stdin 全パターン
# ===========================================================================

@test "ac8: hook スクリプトに --body 引数 parse ロジックが存在すること（RED）" {
  # AC: gh issue create --body <text> パターンを parse できる
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC8 --body parse 未実装）" >&2
    return 1
  fi
  run grep -cE '\-\-body[^-]|parse.*\-\-body|body.*parse' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に --body 引数 parse ロジックが存在しない" >&2
    return 1
  fi
}

@test "ac8: hook スクリプトに --body-file / -F 引数 parse ロジックが存在すること（RED）" {
  # AC: gh issue create --body-file <path> / -F <path> パターンを parse できる
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC8 --body-file/-F parse 未実装）" >&2
    return 1
  fi
  run grep -cE '\-\-body-file|\-F[[:space:]]|body.file|body_file' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に --body-file/-F 引数 parse ロジックが存在しない" >&2
    return 1
  fi
}

@test "ac8: hook スクリプトに -b 短縮形 parse ロジックが存在すること（RED）" {
  # AC: gh issue create -b <text> の短縮形パターンを parse できる
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC8 -b parse 未実装）" >&2
    return 1
  fi
  run grep -cE "[[:space:]]-b[[:space:]]|parse.*'-b'|'-b'" "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に -b 短縮形 parse ロジックが存在しない" >&2
    return 1
  fi
}

@test "ac8: hook スクリプトにパイプ stdin parse ロジックが存在すること（RED）" {
  # AC: echo '<body>' | gh issue create --body - パターン（stdin パイプ）を parse できる
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC8 stdin parse 未実装）" >&2
    return 1
  fi
  run grep -cE 'stdin|/dev/stdin|\-\-body[[:space:]]+-|pipe' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook にパイプ stdin parse ロジックが存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC9: ユーザー直接起票への適用範囲が documented (Phase D 再評価予定の旨を明示)
# ===========================================================================

@test "ac9: hook スクリプトまたは関連ドキュメントに Phase D 再評価の記述が存在すること（RED）" {
  # AC: ユーザー直接起票 (terminal から直接 gh issue create) への適用範囲が documented
  #     Phase D で再評価予定の旨を明示する
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC9 Phase D ドキュメント 未実装）" >&2
    return 1
  fi
  # hook スクリプト内コメントまたは関連 docs に Phase D の記述があること
  run grep -cE 'Phase D|phase.d|phase-d|再評価|direct.*issue.*create|terminal.*gh issue' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook スクリプトに Phase D 再評価の旨の記述が存在しない（AC9 未実装）" >&2
    return 1
  fi
}

@test "ac9: post-tool-use-issue-create-label.sh に適用範囲コメント（ユーザー直接起票 Phase D）があること（RED）" {
  # AC: ファイル冒頭コメントに適用範囲 (Phase D 再評価予定) の記述
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC9 適用範囲コメント 未実装）" >&2
    return 1
  fi
  # 冒頭 20 行にコメントがあること
  local header_count
  header_count=$(head -20 "${HOOK_SCRIPT}" | grep -cE 'Phase D|phase.d|適用範囲|scope|direct' 2>/dev/null || echo "0")
  if [ "${header_count}" -lt 1 ]; then
    echo "FAIL: hook スクリプト冒頭 20 行に適用範囲 / Phase D コメントが存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC10: hook 失敗時 fallback: label 付与失敗を WARN log に記録、起票は成功させること
# ===========================================================================

@test "ac10: hook スクリプトに label 付与失敗時の WARN log 記録ロジックが存在すること（RED）" {
  # AC: label 付与失敗を WARN log に記録し、起票自体は成功させる
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC10 WARN log 未実装）" >&2
    return 1
  fi
  run grep -cE 'WARN|warn|WARNING|warning|log.*fail|fail.*log' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に WARN log 記録ロジックが存在しない（AC10 未実装）" >&2
    return 1
  fi
}

@test "ac10: hook スクリプトが label 付与失敗時に exit 0 で終了すること（RED）" {
  # AC: hook 失敗時も起票は成功させる (exit 0 で終了)
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC10 fallback exit 0 未実装）" >&2
    return 1
  fi
  # gh issue edit 失敗時のエラーハンドリングで exit 0 または || true が存在すること
  run grep -cE 'gh issue edit.*\|\||if.*!.*gh issue edit|fallback.*exit 0' "${HOOK_SCRIPT}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: hook に label 付与失敗時の exit 0 / fallback ロジックが存在しない" >&2
    return 1
  fi
}

@test "ac10: stub で gh issue edit 失敗時に hook が exit 0 で終了すること（RED）" {
  # AC: gh issue edit が失敗しても hook スクリプト自体は exit 0 で終了する
  # RED: hook スクリプトが存在しないため fail
  if [ ! -f "${HOOK_SCRIPT}" ]; then
    echo "FAIL: hook スクリプトが存在しない（AC10 動作テスト 未実装）" >&2
    return 1
  fi

  # gh コマンド stub: gh issue edit は fail、gh issue create はダミー URL を返す
  stub_command "gh" '
    if echo "$*" | grep -qE "issue edit"; then
      echo "ERROR: simulated gh issue edit failure" >&2
      exit 1
    elif echo "$*" | grep -qE "issue view"; then
      echo "{\"labels\":[]}"
      exit 0
    else
      exit 0
    fi
  '

  # PostToolUse JSON input: gh issue create の成功を模擬
  export TWILL_PROVENANCE_AUTO_LABEL=1
  run bash "${HOOK_SCRIPT}" <<'EOF'
{
  "tool_name": "Bash",
  "tool_input": {"command": "gh issue create --title 'test' --body 'test body'"},
  "tool_result": {"output": "https://github.com/owner/repo/issues/999"}
}
EOF
  # hook は exit 0 で終了するべき（起票自体は成功）
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# settings.json: PostToolUse hook entry が追加されること（AC2 補完）
# ===========================================================================

@test "settings: ~/.claude/settings.json に PostToolUse hook entry が追加されること（RED: 未追加）" {
  # AC: settings.json に post-tool-use-issue-create-label.sh の PostToolUse hook entry が存在する
  # RED: 現在 settings.json に hook entry が存在しないため fail
  local settings_file="${HOME}/.claude/settings.json"
  if [ ! -f "$settings_file" ]; then
    echo "FAIL: ~/.claude/settings.json が存在しない" >&2
    return 1
  fi
  run grep -c 'post-tool-use-issue-create-label' "$settings_file"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: settings.json に post-tool-use-issue-create-label.sh の hook entry が存在しない（AC2 未実装）" >&2
    return 1
  fi
}
