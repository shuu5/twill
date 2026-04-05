#!/usr/bin/env bash
# resolve-project.sh - リポジトリにリンクされた Project を GraphQL で検出する共通関数
#
# 使用方法:
#   source "${SCRIPT_DIR}/lib/resolve-project.sh"
#   if ! resolve_project; then
#     echo "Project not found" >&2; exit 1
#   fi
#   read -r project_num project_id owner repo_name repo_fullname < <(resolve_project)
#
# 出力（stdout）: "project_num project_id owner repo_name repo_fullname"
# 失敗時: stderr にエラーメッセージを出力し、非ゼロ終了コードで返る

# resolve_project - リポジトリにリンクされた Project を検出する
# stdout: "project_num project_id owner repo_name repo_fullname"
resolve_project() {
  local repo owner repo_name
  repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null) || {
    echo "Error: リポジトリ情報を取得できません。git リポジトリ内で実行してください" >&2
    return 1
  }
  owner="${repo%%/*}"
  repo_name="${repo##*/}"

  local projects
  projects=$(gh project list --owner "$owner" --format json 2>/dev/null) || {
    echo "Error: Project 一覧を取得できません。gh auth refresh -s project を実行してください" >&2
    return 1
  }

  local project_nums
  mapfile -t project_nums < <(echo "$projects" | jq -r '.projects[].number')

  if [[ ${#project_nums[@]} -eq 0 ]]; then
    echo "Error: owner $owner に Project が存在しません" >&2
    return 1
  fi

  local graphql_user='
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
  local graphql_org='
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

  local matched_num="" matched_id="" title_match_num="" title_match_id=""
  local result project_data linked project_title pid

  for pnum in "${project_nums[@]}"; do
    [[ ! "$pnum" =~ ^[0-9]+$ ]] && continue

    result=$(gh api graphql -f query="$graphql_user" -f owner="$owner" -F num="$pnum" 2>/dev/null) || true
    project_data=$(echo "$result" | jq -r '.data.user.projectV2 // empty' 2>/dev/null)

    if [[ -z "$project_data" ]]; then
      result=$(gh api graphql -f query="$graphql_org" -f owner="$owner" -F num="$pnum" 2>/dev/null) || true
      project_data=$(echo "$result" | jq -r '.data.organization.projectV2 // empty' 2>/dev/null)
    fi

    [[ -z "$project_data" ]] && continue

    linked=$(echo "$project_data" | jq -r '.repositories.nodes[].nameWithOwner' 2>/dev/null)
    project_title=$(echo "$project_data" | jq -r '.title // empty' 2>/dev/null)

    if echo "$linked" | grep -qxF "$repo"; then
      pid=$(echo "$project_data" | jq -r '.id')

      if [[ -z "$matched_num" ]]; then
        matched_num="$pnum"
        matched_id="$pid"
      fi

      if [[ "$project_title" == *"$repo_name"* && -z "$title_match_num" ]]; then
        title_match_num="$pnum"
        title_match_id="$pid"
      fi
    fi
  done

  # タイトルマッチ優先
  local final_num="${title_match_num:-$matched_num}"
  local final_id="${title_match_id:-$matched_id}"

  if [[ -z "$final_num" ]]; then
    echo "Error: リポジトリにリンクされた Project Board が見つかりません" >&2
    return 1
  fi

  echo "$final_num $final_id $owner $repo_name $repo"
  return 0
}
