#!/bin/bash
# =============================================================================
# autopilot-plan.sh - autopilot 実行計画 (plan.yaml) 生成
#
# Usage:
#   autopilot-plan.sh --explicit "19,18 → 20 → 23" --project-dir DIR --repo-mode MODE
#   autopilot-plan.sh --issues "84 78 83" --project-dir DIR --repo-mode MODE
#   autopilot-plan.sh --issues "lpd#42 twill#50" --project-dir DIR --repo-mode MODE --repos '{"lpd":{"owner":"shuu5","name":"twill","path":"..."}}'
#   autopilot-plan.sh --board --project-dir DIR --repo-mode MODE
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/python-env.sh
source "${SCRIPT_DIR}/lib/python-env.sh"
# shellcheck source=./lib/gh-read-content.sh
source "${SCRIPT_DIR}/lib/gh-read-content.sh"

# --- 引数解析 ---
MODE=""
INPUT=""
PROJECT_DIR=""
REPO_MODE=""
REPOS_JSON=""  # クロスリポジトリ設定（JSON文字列）
PLAN_MODEL=""  # Worker モデル指定（省略時: sonnet）

while [[ $# -gt 0 ]]; do
    case "$1" in
        --explicit)
            [[ -n "$MODE" ]] && { echo "Error: --explicit/--issues/--board は同時に指定できません" >&2; exit 1; }
            MODE="explicit"; INPUT="$2"; shift 2 ;;
        --issues)
            [[ -n "$MODE" ]] && { echo "Error: --explicit/--issues/--board は同時に指定できません" >&2; exit 1; }
            MODE="issues"; INPUT="$2"; shift 2 ;;
        --board)
            [[ -n "$MODE" ]] && { echo "Error: --explicit/--issues/--board は同時に指定できません" >&2; exit 1; }
            MODE="board"; shift ;;
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --repo-mode)   REPO_MODE="$2"; shift 2 ;;
        # 後方互換: --repo-mode 省略時のデフォルト値は下で設定
        --repos)       REPOS_JSON="$2"; shift 2 ;;
        --model)       PLAN_MODEL="$2"; shift 2 ;;
        *) echo "Error: 不明な引数: $1" >&2; exit 1 ;;
    esac
done

# --repo-mode デフォルト: worktree（#669 — Pilot が毎回初回失敗するパターンを解消）
if [[ -z "$REPO_MODE" ]]; then
    REPO_MODE="worktree"
fi

if [[ "$MODE" == "board" ]]; then
    if [[ -z "$PROJECT_DIR" ]]; then
        echo "Usage: $0 --board --project-dir DIR [--repo-mode MODE]" >&2
        exit 1
    fi
elif [[ -z "$MODE" || -z "$INPUT" || -z "$PROJECT_DIR" ]]; then
    echo "Usage: $0 --explicit|--issues|--board INPUT --project-dir DIR [--repo-mode MODE]" >&2
    exit 1
fi

# --- クロスリポジトリ設定の解析 ---
# REPOS_JSON が指定されている場合、repo_id → owner/name/path のマップを構築
declare -A REPO_OWNERS=()
declare -A REPO_NAMES=()
declare -A REPO_PATHS=()
CROSS_REPO=false

if [[ -n "$REPOS_JSON" ]]; then
    CROSS_REPO=true
    # JSON から repo_id 一覧を取得
    for repo_id in $(echo "$REPOS_JSON" | jq -r 'keys[]'); do
        # repo_id バリデーション
        if [[ ! "$repo_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "Error: 不正な repo_id: $repo_id" >&2; exit 1
        fi
        local_owner=$(echo "$REPOS_JSON" | jq -r --arg k "$repo_id" '.[$k].owner')
        local_name=$(echo "$REPOS_JSON" | jq -r --arg k "$repo_id" '.[$k].name')
        local_path=$(echo "$REPOS_JSON" | jq -r --arg k "$repo_id" '.[$k].path')
        # owner/name フォーマット検証（引数インジェクション防止）
        if [[ ! "$local_owner" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "Error: 不正な owner 形式: $local_owner (repo_id=$repo_id)" >&2; exit 1
        fi
        if [[ ! "$local_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            echo "Error: 不正な name 形式: $local_name (repo_id=$repo_id)" >&2; exit 1
        fi
        REPO_OWNERS[$repo_id]="$local_owner"
        REPO_NAMES[$repo_id]="$local_name"
        REPO_PATHS[$repo_id]="$local_path"
    done
fi

SESSION_ID=$(uuidgen | cut -c1-8)
# bare repo レイアウト検出: .bare/ が存在する場合、state ファイルは main worktree に配置 (#660)
# PROJECT_DIR 自体は bare repo root のまま維持（orchestrator の worktree 作成パスに必要）
if [[ -d "${PROJECT_DIR}/.bare" ]]; then
  AUTOPILOT_DIR="${PROJECT_DIR}/main/.autopilot"
else
  AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"
fi
mkdir -p "$AUTOPILOT_DIR"
PLAN_FILE="${AUTOPILOT_DIR}/plan.yaml"

# --- ユーティリティ ---

# Issue 参照を解決: bare int / repo_id#N / owner/repo#N → repo_id と number を返す
# 出力: "repo_id number" (スペース区切り)
# repo_id は _default（単一リポジトリ時）または repos セクションの ID
resolve_issue_ref() {
    local ref="$1"
    local repo_id=""
    local number=""

    if [[ "$ref" =~ ^([a-zA-Z0-9_-]+)#([0-9]+)$ ]]; then
        # repo_id#N 形式
        repo_id="${BASH_REMATCH[1]}"
        number="${BASH_REMATCH[2]}"
        if [[ "$CROSS_REPO" == "true" && -z "${REPO_OWNERS[$repo_id]:-}" ]]; then
            echo "Error: 不明な repo_id: $repo_id" >&2
            exit 1
        fi
    elif [[ "$ref" =~ ^([a-zA-Z0-9_-]+)/([a-zA-Z0-9_.-]+)#([0-9]+)$ ]]; then
        # owner/repo#N 形式 → repos セクションから逆引き
        local ref_owner="${BASH_REMATCH[1]}"
        local ref_name="${BASH_REMATCH[2]}"
        number="${BASH_REMATCH[3]}"
        local found=false
        for rid in "${!REPO_OWNERS[@]}"; do
            if [[ "${REPO_OWNERS[$rid]}" == "$ref_owner" && "${REPO_NAMES[$rid]}" == "$ref_name" ]]; then
                repo_id="$rid"
                found=true
                break
            fi
        done
        if [[ "$found" != "true" ]]; then
            echo "Error: repos セクションに ${ref_owner}/${ref_name} が見つかりません" >&2
            exit 1
        fi
    elif [[ "$ref" =~ ^#?([0-9]+)$ ]]; then
        # bare integer (後方互換)
        number="${BASH_REMATCH[1]}"
        repo_id="_default"
    else
        echo "Error: 不正な Issue 参照: $ref" >&2
        exit 1
    fi

    echo "$repo_id $number"
}

# repo_id に応じた gh CLI の -R フラグを返す
# _default → 空（カレントリポジトリ）、それ以外 → "-R owner/repo"
gh_repo_flag() {
    local repo_id="$1"
    if [[ "$repo_id" == "_default" || "$CROSS_REPO" != "true" ]]; then
        echo ""
    else
        echo "-R ${REPO_OWNERS[$repo_id]}/${REPO_NAMES[$repo_id]}"
    fi
}

# Issue のユニーク ID を返す（状態管理用）
issue_uid() {
    local repo_id="$1" number="$2"
    if [[ "$repo_id" == "_default" ]]; then
        echo "$number"
    else
        echo "${repo_id}#${number}"
    fi
}

validate_issue() {
    local issue=$1
    local repo_id="${2:-_default}"
    local r_flag
    r_flag=$(gh_repo_flag "$repo_id")
    # shellcheck disable=SC2086
    if ! gh issue view "$issue" $r_flag --json number -q '.number' &>/dev/null; then
        local display_ref
        display_ref=$(issue_uid "$repo_id" "$issue")
        echo "Error: Issue ${display_ref} が存在しません" >&2
        exit 1
    fi
}

# Issue body に deps.yaml 変更が含まれるか判定
# 引数: issue番号, issue_body（省略時は gh から取得）, comments, repo_id
# 戻り値: 0=含む, 1=含まない
issue_touches_deps_yaml() {
    local issue=$1
    local body="${2:-}"
    local comments="${3:-}"
    local repo_id="${4:-_default}"
    local r_flag
    r_flag=$(gh_repo_flag "$repo_id")
    local full_content=""
    if [[ -z "$body" && -z "$comments" ]]; then
        # gh_read_issue_full で body + 全 comments を一括取得（content-reading ポリシー）
        if [[ "$repo_id" != "_default" && "$CROSS_REPO" == "true" ]]; then
            full_content=$(gh_read_issue_full "$issue" --repo "${REPO_OWNERS[$repo_id]}/${REPO_NAMES[$repo_id]}" 2>/dev/null || true)
        else
            full_content=$(gh_read_issue_full "$issue" 2>/dev/null || true)
        fi
    else
        full_content=$(printf '%s\n%s\n' "$body" "$comments")
    fi
    [[ -z "$full_content" ]] && return 1
    printf '%s\n' "$full_content" | grep -qi 'deps\.yaml' && return 0
    return 1
}

# 不変条件 H 緩和: deps.yaml 変更 Issue の並列実行を許可し、コンフリクト時は merge-gate が自動 rebase を試行する
# Phase 配列を変更せず、警告のみ出力する
# グローバル: phases_result, DEPS_YAML_ISSUES（deps.yaml を変更する Issue のセット）
separate_deps_yaml_phases() {
    for entry in "${phases_result[@]}"; do
        local pissues="${entry#*:}"
        local -a deps_yaml_in_phase=()
        for issue in $pissues; do
            if [[ " ${DEPS_YAML_ISSUES[*]:-} " == *" $issue "* ]]; then
                deps_yaml_in_phase+=("$issue")
            fi
        done
        if [[ ${#deps_yaml_in_phase[@]} -ge 2 ]]; then
            echo "⚠ 注記: Phase に deps.yaml 変更 Issue ${deps_yaml_in_phase[*]} が複数あります（並列実行許可 - merge-gate が自動 rebase を試行）" >&2
        fi
    done
    # phases_result は変更しない（並列実行許可）
}

# --explicit モード用: 同一 Phase 内の deps.yaml 競合を警告
warn_deps_yaml_conflict_explicit() {
    local -a phase_entries=("$@")
    for entry in "${phase_entries[@]}"; do
        local pnum="${entry%%:*}"
        local pissues="${entry#*:}"
        local -a deps_yaml_in_phase=()
        for issue in $pissues; do
            if issue_touches_deps_yaml "$issue"; then
                deps_yaml_in_phase+=("$issue")
            fi
        done
        if [[ ${#deps_yaml_in_phase[@]} -ge 2 ]]; then
            echo "⚠ 警告: Phase ${pnum} に deps.yaml 変更 Issue が複数あります: ${deps_yaml_in_phase[*]}" >&2
            echo "  コンフリクトの可能性があります。sequential 化を検討してください。" >&2
        fi
    done
}

# --- model フィールド YAML 出力ヘルパー ---
# PLAN_MODEL が指定されている場合のみ出力（省略時はフィールド自体を出力しない）
emit_model_yaml() {
    if [[ -n "$PLAN_MODEL" ]]; then
        # モデル名バリデーション（コマンドインジェクション防止）
        if [[ ! "$PLAN_MODEL" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            echo "Error: --model の形式が正しくありません: $PLAN_MODEL" >&2
            exit 1
        fi
        echo "model: \"${PLAN_MODEL}\""
    fi
}

# --- repos セクション YAML 出力ヘルパー ---
emit_repos_yaml() {
    if [[ "$CROSS_REPO" != "true" ]]; then
        return
    fi
    echo "repos:"
    for repo_id in "${!REPO_OWNERS[@]}"; do
        echo "  ${repo_id}:"
        echo "    owner: \"${REPO_OWNERS[$repo_id]}\""
        echo "    name: \"${REPO_NAMES[$repo_id]}\""
        echo "    path: \"${REPO_PATHS[$repo_id]}\""
    done
}

# Issue を plan.yaml 形式で出力（クロスリポジトリ対応）
# 引数: issue_uid (例: "42" or "lpd#42")
emit_issue_yaml() {
    local uid="$1"
    if [[ "$CROSS_REPO" == "true" ]]; then
        if [[ "$uid" == *"#"* ]]; then
            local repo_id="${uid%%#*}"
            local number="${uid#*#}"
            echo "    - { number: ${number}, repo: ${repo_id} }"
        else
            # CROSS_REPO モードでも default repo の Issue は統一形式で出力
            echo "    - { number: ${uid}, repo: _default }"
        fi
    else
        # 単一リポジトリ: bare integer
        echo "    - ${uid}"
    fi
}

# --- --explicit モード ---
# "19,18 → 20 → 23" → Phase 1: [19,18], Phase 2: [20], Phase 3: [23]
parse_explicit() {
    local input="$1"
    local phase_num=0

    # declare arrays
    declare -a ALL_PHASES=()
    declare -a ALL_ISSUE_UIDS=()

    # UTF-8 の → を区切りに Phase 分割
    local phases_str
    phases_str=$(echo "$input" | sed 's/ *→ */\n/g')

    while IFS= read -r phase_str; do
        [[ -z "$phase_str" ]] && continue
        phase_num=$((phase_num + 1))

        local issues_in_phase=()
        # カンマ/スペース区切りでトークン分割
        local tokens
        tokens=$(echo "$phase_str" | tr ',[:space:]' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
        while IFS= read -r token; do
            [[ -z "$token" ]] && continue
            local resolved
            resolved=$(resolve_issue_ref "$token")
            local repo_id="${resolved%% *}"
            local number="${resolved#* }"
            validate_issue "$number" "$repo_id"
            local uid
            uid=$(issue_uid "$repo_id" "$number")
            issues_in_phase+=("$uid")
            ALL_ISSUE_UIDS+=("$uid")
        done <<< "$tokens"

        ALL_PHASES+=("${phase_num}:${issues_in_phase[*]}")
    done <<< "$phases_str"

    # plan.yaml 出力
    {
        echo "session_id: \"${SESSION_ID}\""
        echo "repo_mode: \"${REPO_MODE}\""
        echo "project_dir: \"${PROJECT_DIR}\""
        emit_model_yaml
        emit_repos_yaml
        echo "phases:"
        for entry in "${ALL_PHASES[@]}"; do
            local pnum="${entry%%:*}"
            local pissues="${entry#*:}"
            echo "  - phase: ${pnum}"
            for uid in $pissues; do
                emit_issue_yaml "$uid"
            done
        done

        # 依存関係: Phase N の Issue は Phase N-1 の全 Issue に依存
        echo "dependencies:"
        local prev_issues=""
        for entry in "${ALL_PHASES[@]}"; do
            local pissues="${entry#*:}"
            if [[ -n "$prev_issues" ]]; then
                for uid in $pissues; do
                    echo "  ${uid}:"
                    for dep in $prev_issues; do
                        echo "  - ${dep}"
                    done
                done
            fi
            prev_issues="$pissues"
        done
    } > "$PLAN_FILE"

    echo "plan.yaml 生成完了: ${PLAN_FILE}"
    echo "  Session: ${SESSION_ID}"
    echo "  Phases: ${phase_num}"
    echo "  Issues: ${#ALL_ISSUE_UIDS[@]}"

    # --explicit モードでは deps.yaml 競合を警告のみ
    warn_deps_yaml_conflict_explicit "${ALL_PHASES[@]}"
}

# --- --issues モード ---
# Issue body から依存キーワードを検出し、トポロジカルソートで Phase 分割
parse_issues() {
    local input="$1"

    # Issue 参照リストを解決
    # issue_uids: ユニーク ID のリスト ("42" or "lpd#42")
    # issue_repos: uid → repo_id マップ
    # issue_nums: uid → number マップ
    local issue_uids=()
    declare -A issue_repos=()
    declare -A issue_nums=()

    for token in $input; do
        local resolved
        resolved=$(resolve_issue_ref "$token")
        local repo_id="${resolved%% *}"
        local number="${resolved#* }"
        validate_issue "$number" "$repo_id"
        local uid
        uid=$(issue_uid "$repo_id" "$number")
        issue_uids+=("$uid")
        issue_repos[$uid]="$repo_id"
        issue_nums[$uid]="$number"
    done

    if [[ ${#issue_uids[@]} -eq 0 ]]; then
        echo "Error: Issue 番号が指定されていません" >&2
        exit 1
    fi

    # deps.yaml 変更 Issue を検出
    DEPS_YAML_ISSUES=()

    # 依存関係を検出
    declare -A DEPS=()
    local issues_set=" ${issue_uids[*]} "

    for uid in "${issue_uids[@]}"; do
        local repo_id="${issue_repos[$uid]}"
        local number="${issue_nums[$uid]}"
        local r_flag
        r_flag=$(gh_repo_flag "$repo_id")

        # gh_read_issue_full で body + 全 comments を一括取得（content-reading ポリシー）
        local full_content
        if [[ "$repo_id" != "_default" && "$CROSS_REPO" == "true" ]]; then
            full_content=$(gh_read_issue_full "$number" --repo "${REPO_OWNERS[$repo_id]}/${REPO_NAMES[$repo_id]}" 2>/dev/null || true)
        else
            full_content=$(gh_read_issue_full "$number" 2>/dev/null || true)
        fi
        [[ -z "$full_content" ]] && continue

        # deps.yaml 変更判定（full_content を直接渡す: body + comments 既に結合済み）
        if issue_touches_deps_yaml "$number" "$full_content" "" "$repo_id"; then
            DEPS_YAML_ISSUES+=("$uid")
        fi

        local search_text="$full_content"

        local deps_for_issue=""
        # 依存キーワード検出: #N 形式（同リポジトリ内）
        local dep_nums
        dep_nums=$(printf '%s\n' "$search_text" | grep -oiP '(?:depends\s+on|after|requires|blocked\s+by)\s*#(\d+)' | grep -oP '\d+' || true)
        dep_nums+=" "$(printf '%s\n' "$search_text" | grep -oP '#(\d+)\s*が前提' | grep -oP '\d+' || true)
        dep_nums+=" "$(printf '%s\n' "$search_text" | grep -oP '#(\d+)\s*完了後' | grep -oP '\d+' || true)

        for dep_num in $dep_nums; do
            # 同リポジトリの uid を構築して照合
            local dep_uid
            dep_uid=$(issue_uid "$repo_id" "$dep_num")
            if [[ "$issues_set" == *" $dep_uid "* && "$dep_uid" != "$uid" ]]; then
                if [[ -z "${deps_for_issue}" ]]; then
                    deps_for_issue="$dep_uid"
                elif [[ ! " $deps_for_issue " == *" $dep_uid "* ]]; then
                    deps_for_issue="$deps_for_issue $dep_uid"
                fi
            fi
        done

        # クロスリポジトリ依存: owner/repo#N 形式
        if [[ "$CROSS_REPO" == "true" ]]; then
            local cross_deps
            cross_deps=$(printf '%s\n' "$search_text" | grep -oP '[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+#\d+' || true)
            for cross_ref in $cross_deps; do
                local cross_resolved
                cross_resolved=$(resolve_issue_ref "$cross_ref" 2>/dev/null) || continue
                local cross_repo_id="${cross_resolved%% *}"
                local cross_number="${cross_resolved#* }"
                local cross_uid
                cross_uid=$(issue_uid "$cross_repo_id" "$cross_number")
                if [[ "$issues_set" == *" $cross_uid "* && "$cross_uid" != "$uid" ]]; then
                    if [[ -z "${deps_for_issue}" ]]; then
                        deps_for_issue="$cross_uid"
                    elif [[ ! " $deps_for_issue " == *" $cross_uid "* ]]; then
                        deps_for_issue="$deps_for_issue $cross_uid"
                    fi
                fi
            done
        fi

        DEPS[$uid]="$deps_for_issue"
    done

    # 循環依存検出 + トポロジカルソート（Kahn's algorithm）
    declare -A IN_DEGREE=()
    for uid in "${issue_uids[@]}"; do
        IN_DEGREE[$uid]=0
    done
    for uid in "${issue_uids[@]}"; do
        for dep in ${DEPS[$uid]:-}; do
            IN_DEGREE[$uid]=$((${IN_DEGREE[$uid]} + 1))
        done
    done

    local sorted=()
    local phases_result=()
    local remaining=("${issue_uids[@]}")
    local phase_num=0

    while [[ ${#remaining[@]} -gt 0 ]]; do
        phase_num=$((phase_num + 1))
        local ready=()
        local next_remaining=()

        for uid in "${remaining[@]}"; do
            local all_deps_resolved=true
            for dep in ${DEPS[$uid]:-}; do
                if [[ ! " ${sorted[*]:-} " == *" $dep "* ]]; then
                    all_deps_resolved=false
                    break
                fi
            done
            if $all_deps_resolved; then
                ready+=("$uid")
            else
                next_remaining+=("$uid")
            fi
        done

        if [[ ${#ready[@]} -eq 0 ]]; then
            echo "Error: 循環依存が検出されました。残り: ${remaining[*]}" >&2
            exit 1
        fi

        phases_result+=("${phase_num}:${ready[*]}")
        sorted+=("${ready[@]}")
        remaining=("${next_remaining[@]}")
    done

    # 不変条件 H 緩和: deps.yaml 変更 Issue の並列実行を許可（警告のみ）
    if [[ ${#DEPS_YAML_ISSUES[@]} -ge 2 ]]; then
        separate_deps_yaml_phases
    fi

    # plan.yaml 出力
    {
        echo "session_id: \"${SESSION_ID}\""
        echo "repo_mode: \"${REPO_MODE}\""
        echo "project_dir: \"${PROJECT_DIR}\""
        emit_model_yaml
        emit_repos_yaml
        echo "phases:"
        for entry in "${phases_result[@]}"; do
            local pnum="${entry%%:*}"
            local pissues="${entry#*:}"
            echo "  - phase: ${pnum}"
            for uid in $pissues; do
                emit_issue_yaml "$uid"
            done
        done

        echo "dependencies:"
        for uid in "${issue_uids[@]}"; do
            if [[ -n "${DEPS[$uid]:-}" ]]; then
                echo "  ${uid}:"
                for dep in ${DEPS[$uid]}; do
                    echo "  - ${dep}"
                done
            fi
        done
    } > "$PLAN_FILE"

    echo "plan.yaml 生成完了: ${PLAN_FILE}"
    echo "  Session: ${SESSION_ID}"
    echo "  Phases: ${phase_num}"
    echo "  Issues: ${#issue_uids[@]}"
}

# --- --board モード（外部ファイルから読み込み） ---
# shellcheck source=autopilot-plan-board.sh
source "${SCRIPT_DIR}/autopilot-plan-board.sh"

# --- メイン ---
case "$MODE" in
    explicit) parse_explicit "$INPUT" ;;
    issues)   parse_issues "$INPUT" ;;
    board)    fetch_board_issues ;;
    *)        echo "Error: 不明なモード: $MODE" >&2; exit 1 ;;
esac
