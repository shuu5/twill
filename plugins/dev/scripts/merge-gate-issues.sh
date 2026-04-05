#!/bin/bash
# merge-gate-issues.sh
# merge-gate の Issue 起票: tech-debt + self-improve
#
# 必須環境変数:
#   ISSUE      - Issue番号（数値）
#   PR_NUMBER  - PR番号
#
# オプション環境変数:
#   FINDINGS_FILE       - tech-debt findings の JSON ファイルパス（jq配列形式）
#   SELF_IMPROVE_FILE   - self-improve findings の JSON ファイルパス（jq配列形式）
#
# findings JSON 形式:
#   [{"message":"...", "severity":"...", "file":"...", "line":"...", "category":"..."}]
# self-improve JSON 形式:
#   [{"message":"...", "missed_by":"...", "improvement_suggestion":"...", "dev_repo":"..."}]
#
# 出力: 起票された Issue URL を stdout に出力

set -euo pipefail

# 必須環境変数バリデーション
if ! [[ "${ISSUE:-}" =~ ^[0-9]+$ ]]; then
  echo "[merge-gate-issues] Error: 不正なISSUE番号: ${ISSUE:-}" >&2
  exit 1
fi
if ! [[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]]; then
  echo "[merge-gate-issues] Error: 不正なPR_NUMBER: ${PR_NUMBER:-}" >&2
  exit 1
fi

FINDINGS_FILE="${FINDINGS_FILE:-}"
SELF_IMPROVE_FILE="${SELF_IMPROVE_FILE:-}"

# パス検証: /tmp/ 配下のみ許可
if [ -n "$FINDINGS_FILE" ]; then
  FINDINGS_FILE_REAL=$(realpath "$FINDINGS_FILE" 2>/dev/null || echo "$FINDINGS_FILE")
  if [[ "$FINDINGS_FILE_REAL" != /tmp/* ]]; then
    echo "[merge-gate-issues] Warning: FINDINGS_FILE は /tmp/ 配下のみ許可: $FINDINGS_FILE" >&2
    FINDINGS_FILE=""
  fi
fi
if [ -n "$SELF_IMPROVE_FILE" ]; then
  SELF_IMPROVE_FILE_REAL=$(realpath "$SELF_IMPROVE_FILE" 2>/dev/null || echo "$SELF_IMPROVE_FILE")
  if [[ "$SELF_IMPROVE_FILE_REAL" != /tmp/* ]]; then
    echo "[merge-gate-issues] Warning: SELF_IMPROVE_FILE は /tmp/ 配下のみ許可: $SELF_IMPROVE_FILE" >&2
    SELF_IMPROVE_FILE=""
  fi
fi

TECH_DEBT_URLS=""
SELF_IMPROVE_URLS=""

# --- Project Board 登録ヘルパー ---
# Usage: add_to_project_board <issue_url> <repo>
add_to_project_board() {
  local issue_url="$1"
  local repo="$2"
  local owner="${repo%%/*}"

  # Issue番号を URL から抽出
  local issue_num
  issue_num=$(echo "$issue_url" | grep -oP '/issues/\K[0-9]+$' || true)
  if [ -z "$issue_num" ]; then
    echo "[merge-gate-issues] Warning: Issue番号を抽出できません: $issue_url" >&2
    return 0
  fi

  # Project 一覧取得
  local projects
  projects=$(gh project list --owner "$owner" --format json 2>/dev/null || true)
  if [ -z "$projects" ] || [ "$(echo "$projects" | jq '.projects | length')" = "0" ]; then
    return 0  # Project なし → サイレントスキップ
  fi

  local graphql_user='query($owner: String!, $num: Int!) { user(login: $owner) { projectV2(number: $num) { id repositories(first: 20) { nodes { nameWithOwner } } } } }'
  local graphql_org='query($owner: String!, $num: Int!) { organization(login: $owner) { projectV2(number: $num) { id repositories(first: 20) { nodes { nameWithOwner } } } } }'

  local project_nums
  project_nums=$(echo "$projects" | jq -r '.projects[].number')

  for pnum in $project_nums; do
    [[ "$pnum" =~ ^[0-9]+$ ]] || continue
    local result project_data linked
    result=$(gh api graphql -f query="$graphql_user" -f owner="$owner" -F num="$pnum" 2>/dev/null || true)
    project_data=$(echo "$result" | jq -r '.data.user.projectV2 // empty' 2>/dev/null)
    if [ -z "$project_data" ]; then
      result=$(gh api graphql -f query="$graphql_org" -f owner="$owner" -F num="$pnum" 2>/dev/null || true)
      project_data=$(echo "$result" | jq -r '.data.organization.projectV2 // empty' 2>/dev/null)
    fi
    [ -z "$project_data" ] && continue

    linked=$(echo "$project_data" | jq -r '.repositories.nodes[].nameWithOwner' 2>/dev/null)
    if echo "$linked" | grep -qxF "$repo"; then
      gh project item-add "$pnum" --owner "$owner" \
        --url "https://github.com/$repo/issues/$issue_num" 2>/dev/null || true
      return 0
    fi
  done
}

# --- DEV_REPO の特定 ---
DEV_REPO=$(gh pr view "$PR_NUMBER" --json headRepository -q '.headRepository.nameWithOwner' 2>/dev/null || true)
# フォールバック: git remote から取得
if [ -z "$DEV_REPO" ]; then
  DEV_REPO=$(git remote get-url origin 2>/dev/null | grep -oP '(?<=github.com[:/])[^.]+' || true)
fi
# DEV_REPO バリデーション（owner/repo 形式のみ許可）
if [ -n "$DEV_REPO" ] && ! [[ "$DEV_REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
  echo "[merge-gate] Warning: DEV_REPO 形式不正 '${DEV_REPO}' — tech-debt Issue 起票をスキップ" >&2
  DEV_REPO=""
fi

# --- tech-debt Issue 起票 ---
if [ -n "$FINDINGS_FILE" ] && [ -f "$FINDINGS_FILE" ] && [ -n "$DEV_REPO" ]; then
  FINDING_COUNT=$(jq 'length' "$FINDINGS_FILE")
  for i in $(seq 0 $((FINDING_COUNT - 1))); do
    MSG=$(jq -r ".[$i].message" "$FINDINGS_FILE")
    SEVERITY=$(jq -r ".[$i].severity" "$FINDINGS_FILE" | tr -d '`$"' | head -c 50)
    FILE=$(jq -r ".[$i].file" "$FINDINGS_FILE" | tr -d '`$"' | head -c 200)
    LINE=$(jq -r ".[$i].line" "$FINDINGS_FILE" | tr -d '`$"' | head -c 20)

    SAFE_TITLE=$(printf '%s' "$MSG" | tr -d '`$"' | head -c 200)

    BODY_FILE="/tmp/merge-gate-issue-body-${ISSUE}-${i}.md"
    cat > "$BODY_FILE" <<ISSUE_BODY
## 概要

${SAFE_TITLE}

## 詳細
- **Severity**: ${SEVERITY}
- **File**: ${FILE}:${LINE}
- **検出元PR**: #${PR_NUMBER}
- **検出フェーズ**: merge-gate review
ISSUE_BODY

    if ! ISSUE_URL=$(gh issue create -R "$DEV_REPO" \
      --title "[Tech Debt] ${SAFE_TITLE}" \
      --label "tech-debt" \
      --body-file "$BODY_FILE" \
      2>/dev/null); then
      echo "[merge-gate] Warning: tech-debt Issue 起票失敗（続行）" >&2
      ISSUE_URL=""
    fi
    rm -f "$BODY_FILE"

    if [ -n "$ISSUE_URL" ]; then
      TECH_DEBT_URLS="${TECH_DEBT_URLS:+$TECH_DEBT_URLS }${ISSUE_URL}"
      add_to_project_board "$ISSUE_URL" "$DEV_REPO"
    fi
  done
fi

# --- self-improve Issue 起票 ---
if [ -n "$SELF_IMPROVE_FILE" ] && [ -f "$SELF_IMPROVE_FILE" ]; then
  SI_COUNT=$(jq 'length' "$SELF_IMPROVE_FILE")
  for i in $(seq 0 $((SI_COUNT - 1))); do
    MSG=$(jq -r ".[$i].message" "$SELF_IMPROVE_FILE")
    MISSED_BY=$(jq -r ".[$i].missed_by" "$SELF_IMPROVE_FILE" | tr -d '`$"' | head -c 200)
    SUGGESTION=$(jq -r ".[$i].improvement_suggestion" "$SELF_IMPROVE_FILE" | tr -d '`$"' | head -c 500)
    SI_DEV_REPO=$(jq -r ".[$i].dev_repo // \"\"" "$SELF_IMPROVE_FILE")
    # SI_DEV_REPO バリデーション（owner/repo 形式のみ許可、不正時はフォールバック）
    if ! [[ "$SI_DEV_REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
      SI_DEV_REPO="${DEV_REPO}"
    fi

    SAFE_TITLE=$(printf '%s' "$MSG" | tr -d '`$"' | head -c 200)

    BODY_FILE="/tmp/merge-gate-self-improve-${ISSUE}-${i}.md"
    cat > "$BODY_FILE" <<ISSUE_BODY
## 概要

${SAFE_TITLE}

## 詳細
- **検出元PR**: ${SI_DEV_REPO}#${PR_NUMBER}
- **見逃した specialist**: ${MISSED_BY}
- **検出フェーズ**: merge-gate review

## 改善提案
${SUGGESTION}
ISSUE_BODY

    if ! ISSUE_URL=$(gh issue create -R "shuu5/ubuntu-note-system" \
      --title "[Self-Improve] ${SAFE_TITLE}" \
      --label "self-improve" \
      --body-file "$BODY_FILE" \
      2>/dev/null); then
      echo "[merge-gate] Warning: self-improve Issue 起票失敗（続行）" >&2
      ISSUE_URL=""
    fi
    rm -f "$BODY_FILE"

    if [ -n "$ISSUE_URL" ]; then
      SELF_IMPROVE_URLS="${SELF_IMPROVE_URLS:+$SELF_IMPROVE_URLS }${ISSUE_URL}"
      add_to_project_board "$ISSUE_URL" "${SI_DEV_REPO:-shuu5/ubuntu-note-system}"
    fi
  done
fi

# 結果出力（printf %q で安全にエスケープ）
printf 'TECH_DEBT_ISSUES=%q\n' "$TECH_DEBT_URLS"
printf 'SELF_IMPROVE_ISSUES=%q\n' "$SELF_IMPROVE_URLS"
