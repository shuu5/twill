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
    local repo repo_owner repo_name
    if ! repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null); then
        echo "Error: リポジトリ情報を取得できません。git リポジトリ内で実行してください" >&2
        exit 1
    fi
    repo_owner="${repo%%/*}"
    repo_name="${repo##*/}"

    local projects project_numbers
    if ! projects=$(gh project list --owner "$repo_owner" --format json 2>/dev/null); then
        echo "Error: Project 一覧を取得できません。gh auth refresh -s project を実行してください" >&2
        exit 1
    fi
    project_numbers=$(echo "$projects" | jq -r '.projects[].number')

    if [[ -z "$project_numbers" ]]; then
        echo "Error: owner $repo_owner に Project が存在しません" >&2
        exit 1
    fi

    local graphql_user='query($owner: String!, $num: Int!) { user(login: $owner) { projectV2(number: $num) { id title repositories(first: 20) { nodes { nameWithOwner } } } } }'
    local graphql_org='query($owner: String!, $num: Int!) { organization(login: $owner) { projectV2(number: $num) { id title repositories(first: 20) { nodes { nameWithOwner } } } } }'

    local matched_project_num="" title_match_num=""

    for pnum in $project_numbers; do
        if [[ ! "$pnum" =~ ^[0-9]+$ ]]; then
            continue
        fi
        local result project_data
        result=$(gh api graphql -f query="$graphql_user" -f owner="$repo_owner" -F num="$pnum" 2>/dev/null || true)
        project_data=$(echo "$result" | jq -r '.data.user.projectV2 // empty' 2>/dev/null)

        if [[ -z "$project_data" ]]; then
            result=$(gh api graphql -f query="$graphql_org" -f owner="$repo_owner" -F num="$pnum" 2>/dev/null || true)
            project_data=$(echo "$result" | jq -r '.data.organization.projectV2 // empty' 2>/dev/null)
        fi

        [[ -z "$project_data" ]] && continue

        local linked project_title
        linked=$(echo "$project_data" | jq -r '.repositories.nodes[].nameWithOwner')
        project_title=$(echo "$project_data" | jq -r '.title // empty')

        if echo "$linked" | grep -qxF "$repo"; then
            if [[ -z "$matched_project_num" ]]; then
                matched_project_num="$pnum"
            fi
            if [[ "$project_title" == *"$repo_name"* && -z "$title_match_num" ]]; then
                title_match_num="$pnum"
            fi
        fi
    done

    # タイトルマッチ優先
    if [[ -n "$title_match_num" ]]; then
        matched_project_num="$title_match_num"
    fi

    if [[ -z "$matched_project_num" ]]; then
        echo "Error: リポジトリにリンクされた Project Board が見つかりません" >&2
        exit 1
    fi

    echo "$matched_project_num $repo_owner $repo_name $repo"
}

# --- Board items 取得 + フィルタリング ---
# 指定 Project の非 Done Issue をフィルタリングして返す。
# 引数: project_num, repo_owner
# 出力（stdout）: フィルタ済み JSON 配列
# 失敗時: stderr にエラーメッセージを出力し exit 1。
_fetch_filtered_items() {
    local project_num="$1" repo_owner="$2"

    local items_json
    if ! items_json=$(gh project item-list "$project_num" --owner "$repo_owner" --format json 2>/dev/null); then
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
            if [[ ! "$cross_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
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
        for rid in "${!cross_repos[@]}"; do
            local cr_owner cr_name
            cr_owner="${cross_repos[$rid]%%:*}"
            cr_name="${cross_repos[$rid]#*:}"
            repos_json=$(echo "$repos_json" | jq --arg rid "$rid" --arg owner "$cr_owner" --arg name "$cr_name" \
                '. + {($rid): {owner: $owner, name: $name, path: ""}}')
            REPO_OWNERS[$rid]="$cr_owner"
            REPO_NAMES[$rid]="$cr_name"
            REPO_PATHS[$rid]=""
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
