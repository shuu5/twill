#!/bin/bash
# ecc-monitor.sh
# ECCリポジトリの変更検知・カテゴリ分類スクリプト
# Usage: ecc-monitor.sh [check|save-checkpoint]

set -euo pipefail

ECC_CACHE_DIR="${HOME}/.claude/cache/ecc"
ECC_REPO_URL="https://github.com/hesreallygood/everything-claude-code.git"
CHECKPOINT_FILE="${ECC_CACHE_DIR}/last-check.json"
FALLBACK_DAYS=7

# --- カテゴリ分類 ---
classify_path() {
    local path="$1"
    case "$path" in
        agents/*)   echo "agents" ;;
        skills/*)   echo "skills" ;;
        rules/*)    echo "rules" ;;
        hooks/*)    echo "hooks" ;;
        commands/*) echo "commands" ;;
        contexts/*) echo "contexts" ;;
        docs/*)     echo "docs" ;;
        */*)        echo "other" ;;
        *)          echo "root" ;;
    esac
}

# --- clone/pull ---
ensure_repo() {
    if [ ! -d "${ECC_CACHE_DIR}/.git" ]; then
        echo "ECCリポジトリをclone中..." >&2
        mkdir -p "${ECC_CACHE_DIR}"
        git clone --depth 100 "${ECC_REPO_URL}" "${ECC_CACHE_DIR}" >/dev/null 2>&1
    else
        echo "ECCリポジトリを更新中..." >&2
        git -C "${ECC_CACHE_DIR}" pull --quiet >/dev/null 2>&1
    fi
}

# --- チェックポイント読込 ---
read_checkpoint() {
    if [ -f "${CHECKPOINT_FILE}" ]; then
        local commit
        commit=$(jq -r '.commit // empty' "${CHECKPOINT_FILE}" 2>/dev/null || true)
        if [ -n "${commit}" ]; then
            # commit が現在のリポジトリに存在するか確認
            if git -C "${ECC_CACHE_DIR}" cat-file -e "${commit}" 2>/dev/null; then
                echo "${commit}"
                return 0
            else
                echo "警告: チェックポイントのcommit ${commit} が見つかりません。フォールバックします。" >&2
            fi
        else
            echo "警告: チェックポイントが破損しています。フォールバックします。" >&2
        fi
    fi
    return 1
}

# --- チェックポイント保存 ---
save_checkpoint() {
    local commit
    commit=$(git -C "${ECC_CACHE_DIR}" rev-parse HEAD)
    local timestamp
    timestamp=$(date -Iseconds)

    cat > "${CHECKPOINT_FILE}" <<CPEOF
{
  "commit": "${commit}",
  "timestamp": "${timestamp}",
  "checked_by": "ecc-monitor v1"
}
CPEOF
    echo "チェックポイント保存: ${commit:0:7} (${timestamp})" >&2
}

# --- check サブコマンド ---
do_check() {
    ensure_repo

    local from_commit=""
    local to_commit
    to_commit=$(git -C "${ECC_CACHE_DIR}" rev-parse HEAD)

    if from_commit=$(read_checkpoint); then
        # チェックポイントあり
        if [ "${from_commit}" = "${to_commit}" ]; then
            jq -n --arg from "${from_commit}" --arg to "${to_commit}" \
                '{status:"no_changes",from_commit:$from,to_commit:$to,changes:[]}'
            return 0
        fi
    else
        # フォールバック: 直近N日間
        from_commit=$(git -C "${ECC_CACHE_DIR}" log --since="${FALLBACK_DAYS} days ago" --reverse --format="%H" | head -1) || from_commit=""
        if [ -z "${from_commit}" ]; then
            jq -n --arg to "${to_commit}" \
                '{status:"no_changes",from_commit:"",to_commit:$to,changes:[]}'
            return 0
        fi
        # 1つ前のコミットを起点にする
        from_commit=$(git -C "${ECC_CACHE_DIR}" rev-parse "${from_commit}^" 2>/dev/null || echo "${from_commit}")
    fi

    # 変更ファイルリスト取得
    local changes="[]"
    changes=$(git -C "${ECC_CACHE_DIR}" diff --name-status "${from_commit}..${to_commit}" | while IFS=$'\t' read -r status path; do
        local category
        category=$(classify_path "${path}")
        printf '{"path":"%s","category":"%s","status":"%s"}\n' "${path}" "${category}" "${status}"
    done | jq -s '.')

    # JSON出力
    jq -n \
        --arg from "${from_commit}" \
        --arg to "${to_commit}" \
        --arg ts "$(date -Iseconds)" \
        --argjson changes "${changes}" \
        '{status:"has_changes",from_commit:$from,to_commit:$to,timestamp:$ts,changes:$changes}'
}

# --- メイン ---
case "${1:-check}" in
    check)
        do_check
        ;;
    save-checkpoint)
        ensure_repo
        save_checkpoint
        ;;
    *)
        echo "Usage: $0 [check|save-checkpoint]" >&2
        exit 1
        ;;
esac
