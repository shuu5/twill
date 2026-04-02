#!/usr/bin/env bash
# chain-runner.sh - 機械的 chain ステップを bash で直接実行
# Usage: bash chain-runner.sh <step-name> [args...]
#
# Worker のトークン消費を削減するため、LLM 判断不要なステップを
# bash で直接実行する。手動実行パスは既存 command.md が担当。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =====================================================================
# Compaction Recovery: chain ステップ順序定義（SSOT: scripts/chain-steps.sh）
# =====================================================================
# shellcheck source=./chain-steps.sh
source "${SCRIPT_DIR}/chain-steps.sh"

# =====================================================================
# 共通ユーティリティ関数
# =====================================================================

# ブランチ名から Issue 番号を抽出
# e.g. feat/119-chain-runner → 119
extract_issue_num() {
  git branch --show-current 2>/dev/null \
    | grep -oP '^\w+/\K\d+(?=-)' 2>/dev/null || echo ""
}

# worktree のプロジェクトルートを解決
resolve_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# 成功出力
ok() {
  local step="$1"; shift
  echo "✓ ${step}: $*"
}

# スキップ出力
skip() {
  local step="$1"; shift
  echo "⚠️ ${step}: $*"
}

# エラー出力（stderr）
err() {
  local step="$1"; shift
  echo "✗ ${step}: $*" >&2
}

# Compaction Recovery: current_step を issue-{N}.json に記録
# 引数: step_id（記録するステップ名）
# issue_num はブランチ名から自動抽出。取得できない場合はサイレントスキップ
record_current_step() {
  local step_id="${1:-}"
  [[ -z "$step_id" ]] && return 0
  # step_id の形式を検証（英数字とハイフンのみ許可）
  [[ "$step_id" =~ ^[a-z0-9-]+$ ]] || return 0
  local issue_num
  issue_num="$(extract_issue_num)"
  [[ -z "$issue_num" ]] && return 0
  # record current_step in state-write.sh
  bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$issue_num" --role worker --set "current_step=${step_id}" 2>/dev/null || true
}

# =====================================================================
# Step 実装
# =====================================================================

# Issue の quick ラベルを検出する（Issue 番号が正の整数の場合のみ）
detect_quick_label() {
  local issue_num="${1:-}"
  [[ -n "$issue_num" ]] && [[ "$issue_num" =~ ^[0-9]+$ ]] || { echo "false"; return 0; }
  local labels
  labels=$(gh issue view "$issue_num" --json labels --jq '.labels[].name' 2>/dev/null || echo "")
  if echo "$labels" | grep -qxF "quick"; then
    echo "true"
  else
    echo "false"
  fi
}

# --- init: 開発状態判定 ---
# Usage: step_init [issue_num]
step_init() {
  record_current_step "init"
  local issue_num="${1:-}"
  local root
  root="$(resolve_project_root)"
  local branch
  branch="$(git branch --show-current 2>/dev/null || echo "detached")"
  local is_quick
  is_quick="$(detect_quick_label "$issue_num")"

  # ブランチ判定
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    jq -n --arg branch "$branch" --argjson is_quick "$is_quick" '{"recommended_action":"worktree","branch":$branch,"is_quick":$is_quick}'
    ok "init" "recommended_action=worktree (branch=$branch, is_quick=$is_quick)"
    return 0
  fi

  # openspec 判定
  if [[ ! -d "$root/openspec" ]]; then
    jq -n --arg branch "$branch" --argjson is_quick "$is_quick" '{"recommended_action":"direct","branch":$branch,"openspec":false,"is_quick":$is_quick}'
    ok "init" "recommended_action=direct (no openspec, is_quick=$is_quick)"
    return 0
  fi

  # changes 判定
  local changes_dir="$root/openspec/changes"
  if [[ ! -d "$changes_dir" ]] || [[ -z "$(ls -A "$changes_dir" 2>/dev/null)" ]]; then
    jq -n --arg branch "$branch" --argjson is_quick "$is_quick" '{"recommended_action":"propose","branch":$branch,"openspec":true,"change_exists":false,"is_quick":$is_quick}'
    ok "init" "recommended_action=propose (no changes, is_quick=$is_quick)"
    return 0
  fi

  # 最新 change の proposal 状態
  local latest_change
  latest_change="$(ls -td "$changes_dir"/*/ 2>/dev/null | head -1 | xargs -r basename)"
  local proposal="$changes_dir/$latest_change/proposal.md"

  if [[ -f "$proposal" ]]; then
    # approved 判定: .openspec.yaml の status を確認
    local yaml="$changes_dir/$latest_change/.openspec.yaml"
    if [[ -f "$yaml" ]] && grep -q 'status:.*approved' "$yaml" 2>/dev/null; then
      jq -n --arg branch "$branch" --arg cid "$latest_change" --argjson is_quick "$is_quick" '{"recommended_action":"apply","branch":$branch,"openspec":true,"change_id":$cid,"proposal_status":"approved","is_quick":$is_quick}'
      ok "init" "recommended_action=apply (change=$latest_change, approved, is_quick=$is_quick)"
    else
      jq -n --arg branch "$branch" --arg cid "$latest_change" --argjson is_quick "$is_quick" '{"recommended_action":"propose","branch":$branch,"openspec":true,"change_id":$cid,"proposal_status":"pending","is_quick":$is_quick}'
      ok "init" "recommended_action=propose (change=$latest_change, pending, is_quick=$is_quick)"
    fi
  else
    jq -n --arg branch "$branch" --argjson is_quick "$is_quick" '{"recommended_action":"propose","branch":$branch,"openspec":true,"change_exists":true,"is_quick":$is_quick}'
    ok "init" "recommended_action=propose (no proposal, is_quick=$is_quick)"
  fi
}

# --- worktree-create: worktree-create.sh ラッパー ---
step_worktree_create() {
  record_current_step "worktree-create"
  bash "$SCRIPT_DIR/worktree-create.sh" "$@"
  ok "worktree-create" "完了"
}

# --- board-status-update: Project Board Status 更新 ---
step_board_status_update() {
  record_current_step "board-status-update"
  local issue_num="${1:-}"

  # 引数なし or 空 → スキップ
  if [[ -z "$issue_num" ]]; then
    return 0
  fi

  # 正の整数チェック
  if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  # project スコープ確認
  if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
    skip "board-status-update" "gh auth refresh -s project が必要"
    return 0
  fi

  local repo owner repo_name
  repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null) || {
    skip "board-status-update" "リポジトリ情報取得失敗"
    return 0
  }
  owner="${repo%%/*}"
  repo_name="${repo##*/}"

  local projects
  projects=$(gh project list --owner "$owner" --format json 2>/dev/null) || {
    skip "board-status-update" "Project 一覧取得失敗"
    return 0
  }

  local graphql_query='
    query($owner: String!, $num: Int!) {
      user(login: $owner) {
        projectV2(number: $num) {
          id
          title
          repositories(first: 20) { nodes { nameWithOwner } }
        }
      }
    }
  '
  local graphql_query_org='
    query($owner: String!, $num: Int!) {
      organization(login: $owner) {
        projectV2(number: $num) {
          id
          title
          repositories(first: 20) { nodes { nameWithOwner } }
        }
      }
    }
  '

  local matched_project_num="" matched_project_id="" title_match_num="" title_match_id=""
  local project_numbers
  project_numbers=$(echo "$projects" | jq -r '.projects[].number')

  for pnum in $project_numbers; do
    local result project_data
    result=$(gh api graphql -f query="$graphql_query" -f owner="$owner" -F num="$pnum" 2>/dev/null) || true
    project_data=$(echo "$result" | jq -r '.data.user.projectV2 // empty' 2>/dev/null)

    if [[ -z "$project_data" ]]; then
      result=$(gh api graphql -f query="$graphql_query_org" -f owner="$owner" -F num="$pnum" 2>/dev/null) || true
      project_data=$(echo "$result" | jq -r '.data.organization.projectV2 // empty' 2>/dev/null)
    fi

    [[ -z "$project_data" ]] && continue

    local linked project_title
    linked=$(echo "$project_data" | jq -r '.repositories.nodes[].nameWithOwner' 2>/dev/null)
    project_title=$(echo "$project_data" | jq -r '.title // empty' 2>/dev/null)

    if echo "$linked" | grep -qxF "$repo"; then
      local pid
      pid=$(echo "$project_data" | jq -r '.id')

      if [[ -z "$matched_project_num" ]]; then
        matched_project_num="$pnum"
        matched_project_id="$pid"
      fi

      if [[ "$project_title" == *"$repo_name"* ]] && [[ -z "$title_match_num" ]]; then
        title_match_num="$pnum"
        title_match_id="$pid"
      fi
    fi
  done

  # 優先: タイトルマッチ > 最初のマッチ
  local final_num="${title_match_num:-$matched_project_num}"
  local final_id="${title_match_id:-$matched_project_id}"

  if [[ -z "$final_num" ]]; then
    skip "board-status-update" "リンクされた Project なし"
    return 0
  fi

  # Issue を Project に追加
  local item_id
  item_id=$(gh project item-add "$final_num" --owner "$owner" \
    --url "https://github.com/$repo/issues/$issue_num" --format json 2>/dev/null \
    | jq -r '.id') || {
    skip "board-status-update" "Issue 追加失敗"
    return 0
  }

  # Status フィールドの "In Progress" オプション ID を取得
  local fields status_field_id in_progress_option_id
  fields=$(gh project field-list "$final_num" --owner "$owner" --format json 2>/dev/null) || {
    skip "board-status-update" "フィールド取得失敗"
    return 0
  }
  status_field_id=$(echo "$fields" | jq -r '.fields[] | select(.name == "Status") | .id')
  in_progress_option_id=$(echo "$fields" | jq -r '.fields[] | select(.name == "Status") | .options[] | select(.name == "In Progress") | .id')

  if [[ -z "$status_field_id" || -z "$in_progress_option_id" ]]; then
    skip "board-status-update" "Status フィールドまたは In Progress オプションが見つからない"
    return 0
  fi

  gh project item-edit --id "$item_id" --project-id "$final_id" \
    --field-id "$status_field_id" --single-select-option-id "$in_progress_option_id" 2>/dev/null || {
    skip "board-status-update" "Status 更新失敗"
    return 0
  }

  ok "board-status-update" "Project Board Status → In Progress (#$issue_num)"
}

# --- ac-extract: AC 抽出 ---
step_ac_extract() {
  record_current_step "ac-extract"
  local snapshot_dir="${1:-}"
  local issue_num
  issue_num="$(extract_issue_num)"

  if [[ -z "$issue_num" ]]; then
    skip "ac-extract" "Issue 番号なし — スキップ"
    return 0
  fi

  if [[ -z "$snapshot_dir" ]]; then
    local root
    root="$(resolve_project_root)"
    snapshot_dir="$root/.dev-session"
  fi
  mkdir -p "$snapshot_dir"

  local output_file="$snapshot_dir/01.5-ac-checklist.md"

  # 冪等: 既存なら skip
  if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
    ok "ac-extract" "既存 AC チェックリストを使用"
    return 0
  fi

  local ac_output
  ac_output=$(bash "$SCRIPT_DIR/parse-issue-ac.sh" "$issue_num" 2>/dev/null) && {
    printf '%s\n\n%s\n' "## 受け入れ基準（Issue #${issue_num}）" "$ac_output" > "$output_file"
    ok "ac-extract" "AC 抽出完了 (Issue #$issue_num)"
  } || {
    echo "AC セクションなし — スキップ" > "$output_file"
    skip "ac-extract" "AC セクションなし — スキップ"
  }
}

# --- arch-ref: architecture/ コンテキスト抽出 ---
step_arch_ref() {
  record_current_step "arch-ref"
  local issue_num="${1:-}"
  if [[ -z "$issue_num" ]]; then
    issue_num="$(extract_issue_num)"
  fi

  if [[ -z "$issue_num" ]]; then
    skip "arch-ref" "Issue 番号なし — スキップ"
    return 0
  fi

  # 数値検証（インジェクション防止）
  if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    err "arch-ref" "不正な Issue 番号: $issue_num"
    return 1
  fi

  # Issue body + comments から arch-ref タグを検索
  local body comments combined
  body=$(gh issue view "$issue_num" --json body --jq '.body' 2>/dev/null || echo "")
  comments=$(gh api "repos/{owner}/{repo}/issues/${issue_num}/comments" --jq '.[].body' 2>/dev/null || echo "")
  combined="${body}${comments}"

  if ! echo "$combined" | grep -q '<!-- arch-ref-start -->'; then
    skip "arch-ref" "タグなし — スキップ"
    return 0
  fi

  # タグ間のパスを抽出
  local paths
  paths=$(echo "$combined" \
    | sed -n '/<!-- arch-ref-start -->/,/<!-- arch-ref-end -->/p' \
    | grep -oP 'architecture/[^\s<]+' \
    | head -5)

  local count=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue

    # パストラバーサル拒否
    if echo "$path" | grep -q '\.\.'; then
      echo "⚠️ パストラバーサル拒否: $path" >&2
      continue
    fi

    local root
    root="$(resolve_project_root)"
    if [[ -f "$root/$path" ]]; then
      echo "$path"
      ((count++))
    else
      echo "⚠️ ファイル不在: $path" >&2
    fi
  done <<< "$paths"

  if [[ $count -gt 0 ]]; then
    ok "arch-ref" "${count} 件のパスを抽出"
  else
    skip "arch-ref" "有効なパスなし"
  fi
}

# --- change-id-resolve: openspec change-id 解決 ---
step_change_id_resolve() {
  record_current_step "change-id-resolve"
  local root
  root="$(resolve_project_root)"
  local changes_dir="$root/openspec/changes"

  if [[ ! -d "$changes_dir" ]]; then
    err "change-id-resolve" "openspec/changes/ が存在しない"
    return 1
  fi

  local latest
  latest=$(ls -td "$changes_dir"/*/ 2>/dev/null | head -1 | xargs -r basename)

  if [[ -z "$latest" ]]; then
    err "change-id-resolve" "changes/ が空"
    return 1
  fi

  echo "$latest"
  ok "change-id-resolve" "$latest"
}

# --- ts-preflight: TypeScript 機械的検証 ---
step_ts_preflight() {
  record_current_step "ts-preflight"
  local root
  root="$(resolve_project_root)"

  if [[ ! -f "$root/tsconfig.json" ]]; then
    ok "ts-preflight" "PASS (TypeScript プロジェクトではない — スキップ)"
    return 0
  fi

  local failed=false results=""

  # 型チェック
  if ! (cd "$root" && npx tsc --noEmit 2>&1); then
    failed=true
    results+="tsc FAIL; "
  fi

  # lint（eslint 設定がある場合のみ）
  if [[ -f "$root/.eslintrc" || -f "$root/.eslintrc.js" || -f "$root/.eslintrc.json" || -f "$root/eslint.config.js" ]]; then
    if ! (cd "$root" && npx eslint . 2>&1); then
      failed=true
      results+="eslint FAIL; "
    fi
  fi

  # ビルド（build スクリプトがある場合のみ）
  if [[ -f "$root/package.json" ]] && jq -e '.scripts.build' "$root/package.json" >/dev/null 2>&1; then
    if ! (cd "$root" && npm run build 2>&1); then
      failed=true
      results+="build FAIL; "
    fi
  fi

  if $failed; then
    skip "ts-preflight" "FAIL ($results)"
    return 1
  else
    ok "ts-preflight" "PASS"
  fi
}

# --- pr-test: テスト実行 ---
step_pr_test() {
  record_current_step "pr-test"
  local root
  root="$(resolve_project_root)"
  local exit_code=0

  # テストランナー検出 + 実行
  if [[ -f "$root/tests/run-all.sh" ]]; then
    (cd "$root" && bash tests/run-all.sh 2>&1) || exit_code=$?
  elif [[ -f "$root/package.json" ]] && jq -e '.scripts.test' "$root/package.json" >/dev/null 2>&1; then
    if command -v pnpm &>/dev/null; then
      (cd "$root" && pnpm test 2>&1) || exit_code=$?
    else
      (cd "$root" && npm test 2>&1) || exit_code=$?
    fi
  elif [[ -f "$root/pytest.ini" || -f "$root/pyproject.toml" ]]; then
    (cd "$root" && pytest 2>&1) || exit_code=$?
  elif ls "$root/tests/scenarios/"*.test.sh >/dev/null 2>&1; then
    for test_file in "$root/tests/scenarios/"*.test.sh; do
      (cd "$root" && bash "$test_file" 2>&1) || exit_code=$?
    done
  else
    skip "pr-test" "WARN (テストファイルなし)"
    return 0
  fi

  if [[ $exit_code -eq 0 ]]; then
    ok "pr-test" "PASS"
  else
    skip "pr-test" "FAIL (exit code: $exit_code)"
    return 1
  fi
}

# --- all-pass-check: 全パス判定 ---
step_all_pass_check() {
  record_current_step "all-pass-check"
  # 引数: step_results を JSON 形式で受け取る（stdin or 引数）
  local issue_num
  issue_num="$(extract_issue_num)"

  # 結果は呼び出し側（SKILL.md）が判定して引数で渡す
  local overall_result="${1:-PASS}"

  if [[ -z "$issue_num" ]]; then
    if [[ "$overall_result" == "PASS" ]]; then
      ok "all-pass-check" "PASS (non-autopilot)"
    else
      skip "all-pass-check" "FAIL (non-autopilot)"
    fi
    return 0
  fi

  # autopilot 配下判定
  local autopilot_status
  autopilot_status=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$issue_num" --field status 2>/dev/null || echo "")
  local is_autopilot=false
  [[ "$autopilot_status" == "running" ]] && is_autopilot=true

  if [[ "$overall_result" == "PASS" ]]; then
    bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$issue_num" --role worker --set "status=merge-ready" 2>/dev/null || true
    if $is_autopilot; then
      ok "all-pass-check" "PASS — autopilot 配下: merge-ready 宣言。Pilot による merge-gate を待機"
    else
      ok "all-pass-check" "PASS — merge-ready"
    fi
  else
    bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$issue_num" --role worker --set "status=failed" 2>/dev/null || true
    skip "all-pass-check" "FAIL — status=failed"
    return 1
  fi
}

# --- pr-cycle-report: 結果レポート構造化集約 ---
step_pr_cycle_report() {
  record_current_step "pr-cycle-report"
  # 引数: PR_NUM, レポート内容は stdin から受け取る
  local pr_num="${1:-}"

  if [[ -z "$pr_num" ]]; then
    pr_num=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  fi

  if [[ -z "$pr_num" ]]; then
    skip "pr-cycle-report" "PR 番号なし — スキップ"
    return 0
  fi

  # 数値検証（引数注入防止）
  if ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
    err "pr-cycle-report" "不正な PR 番号: $pr_num"
    return 1
  fi

  # stdin からレポート本文を読み取り
  local report=""
  if [[ ! -t 0 ]]; then
    report=$(cat)
  fi

  if [[ -z "$report" ]]; then
    skip "pr-cycle-report" "レポート内容なし"
    return 0
  fi

  gh pr comment "$pr_num" --body "$report" 2>/dev/null || {
    skip "pr-cycle-report" "PR コメント投稿失敗"
    return 0
  }

  ok "pr-cycle-report" "PR #$pr_num にレポート投稿"
}

# --- check: 準備確認 ---
step_check() {
  record_current_step "check"
  local root
  root="$(resolve_project_root)"
  local has_fail=false

  # OpenSpec
  if [[ -d "$root/openspec" ]]; then
    if ls "$root/openspec/changes/"*/proposal.md >/dev/null 2>&1; then
      echo "OpenSpec: PASS"
    else
      echo "OpenSpec: FAIL (proposal.md なし)"
      has_fail=true
    fi
  else
    echo "OpenSpec: N/A"
  fi

  # テスト
  if find "$root/tests/" \( -name "*.sh" -o -name "*.bats" -o -name "*.test.*" -o -name "*.R" -o -name "*.py" \) 2>/dev/null | head -1 | grep -q .; then
    echo "Tests: PASS"
  else
    echo "Tests: FAIL (テストファイルなし)"
    has_fail=true
  fi

  # CI/CD
  if ls "$root/.github/workflows/"*.yml >/dev/null 2>&1; then
    echo "CI/CD: PASS"
  else
    echo "CI/CD: WARN (ワークフローなし)"
  fi

  # 変更ファイル
  local changes
  changes=$(cd "$root" && git status --porcelain | wc -l)
  echo "Changes: $changes files"

  if $has_fail; then
    skip "check" "FAIL 項目あり"
    return 1
  else
    ok "check" "準備完了"
  fi
}

# =====================================================================
# ディスパッチャ
# =====================================================================

main() {
  local step="${1:-}"
  if [[ -z "$step" ]]; then
    echo "Usage: chain-runner.sh <step-name> [args...]" >&2
    echo "Steps: init, worktree-create, board-status-update, ac-extract, arch-ref," >&2
    echo "       change-id-resolve, ts-preflight, pr-test, all-pass-check," >&2
    echo "       pr-cycle-report, check" >&2
    exit 1
  fi
  shift

  case "$step" in
    init)                step_init "$@" ;;
    worktree-create)     step_worktree_create "$@" ;;
    board-status-update) step_board_status_update "$@" ;;
    ac-extract)          step_ac_extract "$@" ;;
    arch-ref)            step_arch_ref "$@" ;;
    change-id-resolve)   step_change_id_resolve "$@" ;;
    ts-preflight)        step_ts_preflight "$@" ;;
    pr-test)             step_pr_test "$@" ;;
    all-pass-check)      step_all_pass_check "$@" ;;
    pr-cycle-report)     step_pr_cycle_report "$@" ;;
    check)               step_check "$@" ;;
    *)
      echo "ERROR: 未知のステップ: $step" >&2
      echo "利用可能: init, worktree-create, board-status-update, ac-extract, arch-ref," >&2
      echo "         change-id-resolve, ts-preflight, pr-test, all-pass-check," >&2
      echo "         pr-cycle-report, check" >&2
      exit 1
      ;;
  esac
}

main "$@"
