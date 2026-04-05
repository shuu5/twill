#!/bin/bash
# =============================================================================
# autopilot-plan-board.sh - --board モードの関数群
#
# autopilot-plan.sh から source される。単独実行不可。
# 依存: CROSS_REPO, REPO_OWNERS, REPO_NAMES, REPO_PATHS, REPOS_JSON（親スクリプトのグローバル変数）
# =============================================================================

# --- Project Board 自動検出 ---
# リポジトリにリンクされた Project を GraphQL で検出し、project number を返す。
# 出力（stdout）: "project_num repo_owner repo_name repo_fullname" （スペース区切り）
# 失敗時: stderr にエラーメッセージを出力し exit 1。
_detect_project_board() {
    local _script_dir
    _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=./lib/resolve-project.sh
    source "${_script_dir}/lib/resolve-project.sh"

    local project_num project_id repo_owner repo_name repo_fullname
    if ! read -r project_num project_id repo_owner repo_name repo_fullname < <(resolve_project); then
        exit 1
    fi

    # project_id は呼び出し元 fetch_board_issues では不要のため出力しない
    # resolve_project の5値出力から4値にアダプト
    echo "$project_num $repo_owner $repo_name $repo_fullname"
}

# --- Board items 取得 + フィルタリング ---
# 指定 Project の非 Done Issue をフィルタリングして返す。
# 引数: project_num, repo_owner
# 出力（stdout）: フィルタ済み JSON 配列
# 失敗時: stderr にエラーメッセージを出力し exit 1。
_fetch_filtered_items() {
    local project_num="$1" repo_owner="$2"

    local items_json
    if ! items_json=$(gh project item-list "$project_num" --owner "$repo_owner" --format json --limit 200 2>/dev/null); then
        echo "Error: Project #${project_num} の item-list 取得に失敗しました" >&2
        exit 1
    fi

    local filtered
    filtered=$(echo "$items_json" | jq -r '
        [.items[]
         | select(.content.type == "Issue")
         | select(.status != "Done")
        ]')

    local item_count
    item_count=$(echo "$filtered" | jq 'length')

    if [[ "$item_count" -eq 0 ]]; then
        echo "Error: Board に未完了の Issue がありません" >&2
        exit 1
    fi

    echo "$filtered"
}

# --- クロスリポジトリ JSON 構築 ---
# フィルタ済み Board items からクロスリポジトリ設定を構築し、
# parse_issues() 用の issue_list を返す。
# 引数: filtered_json, current_repo（owner/name 形式）
# 出力: BUILD_RESULT グローバル変数（例: "42 43 loom#56"）
# 副作用: CROSS_REPO, REPO_OWNERS, REPO_NAMES, REPO_PATHS, REPOS_JSON を更新
_build_cross_repo_json() {
    local filtered="$1" current_repo="$2"

    local issue_list=""
    local -A cross_repos=()

    while IFS=$'\t' read -r item_repo item_number; do
        if [[ ! "$item_number" =~ ^[0-9]+$ ]]; then
            echo "⚠ スキップ: 不正な Issue 番号: $item_number" >&2
            continue
        fi

        if [[ "$item_repo" == "$current_repo" ]]; then
            issue_list="${issue_list} ${item_number}"
        else
            local cross_owner cross_name
            cross_owner="${item_repo%%/*}"
            cross_name="${item_repo##*/}"
            if [[ ! "$cross_owner" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "⚠ スキップ: 不正な owner 形式: $cross_owner ($item_repo)" >&2
                continue
            fi
            # defense-in-depth: 下記 regex でも弾かれるが、パストラバーサルリスクを明示的に排除
            if [[ "$cross_name" == ".." || "$cross_name" == "." ]]; then
                echo "⚠ スキップ: 不正な name 形式: $cross_name ($item_repo)" >&2
                continue
            fi
            if [[ ! "$cross_name" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]]; then
                echo "⚠ スキップ: 不正な name 形式: $cross_name ($item_repo)" >&2
                continue
            fi
            local rid="$cross_name"
            cross_repos[$rid]="${cross_owner}:${cross_name}"
            issue_list="${issue_list} ${rid}#${item_number}"
        fi
    done < <(echo "$filtered" | jq -r '.[] | [.content.repository, (.content.number | tostring)] | @tsv')

    # クロスリポジトリ設定を構築（jq で安全に JSON 生成）
    if [[ ${#cross_repos[@]} -gt 0 ]]; then
        CROSS_REPO=true
        local repos_json="{}"
        local parent_dir
        parent_dir="$(dirname "$PROJECT_DIR")"
        for rid in "${!cross_repos[@]}"; do
            local cr_owner cr_name cr_path
            cr_owner="${cross_repos[$rid]%%:*}"
            cr_name="${cross_repos[$rid]#*:}"
            # PROJECT_DIR の兄弟ディレクトリからクロスリポジトリのローカルパスを探索
            cr_path=""
            if [[ -d "${parent_dir}/${cr_name}" ]]; then
                cr_path="${parent_dir}/${cr_name}"
            fi
            if [[ -z "$cr_path" ]]; then
                echo "⚠ クロスリポジトリ ${cr_owner}/${cr_name} のローカルパスが見つかりません（${parent_dir}/${cr_name} を検索）" >&2
            fi
            repos_json=$(echo "$repos_json" | jq --arg rid "$rid" --arg owner "$cr_owner" --arg name "$cr_name" --arg path "$cr_path" \
                '. + {($rid): {owner: $owner, name: $name, path: $path}}')
            REPO_OWNERS[$rid]="$cr_owner"
            REPO_NAMES[$rid]="$cr_name"
            REPO_PATHS[$rid]="$cr_path"
        done
        REPOS_JSON="$repos_json"
    fi

    BUILD_RESULT="${issue_list# }"
}

# --- エントリポイント ---
# Project Board から非 Done Issue を取得し、parse_issues() に渡す。
fetch_board_issues() {
    local detect_result
    detect_result=$(_detect_project_board)
    local project_num repo_owner repo_name current_repo
    read -r project_num repo_owner repo_name current_repo <<< "$detect_result"

    local filtered
    filtered=$(_fetch_filtered_items "$project_num" "$repo_owner")

    BUILD_RESULT=""
    _build_cross_repo_json "$filtered" "$current_repo"
    local issue_list="$BUILD_RESULT"

    parse_issues "$issue_list"
}
