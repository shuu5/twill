#!/bin/bash
# =============================================================================
# autopilot-plan.sh - autopilot 実行計画 (plan.yaml) 生成
#
# Usage:
#   autopilot-plan.sh --explicit "19,18 → 20 → 23" --project-dir DIR --repo-mode MODE
#   autopilot-plan.sh --issues "84 78 83" --project-dir DIR --repo-mode MODE
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 引数解析 ---
MODE=""
INPUT=""
PROJECT_DIR=""
REPO_MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --explicit) MODE="explicit"; INPUT="$2"; shift 2 ;;
        --issues)   MODE="issues";   INPUT="$2"; shift 2 ;;
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --repo-mode)   REPO_MODE="$2"; shift 2 ;;
        *) echo "Error: 不明な引数: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$MODE" || -z "$INPUT" || -z "$PROJECT_DIR" || -z "$REPO_MODE" ]]; then
    echo "Usage: $0 --explicit|--issues INPUT --project-dir DIR --repo-mode MODE" >&2
    exit 1
fi

SESSION_ID=$(uuidgen | cut -c1-8)
AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"
mkdir -p "$AUTOPILOT_DIR"
PLAN_FILE="${AUTOPILOT_DIR}/plan.yaml"

# --- ユーティリティ ---
validate_issue() {
    local issue=$1
    if ! gh issue view "$issue" --json number -q '.number' &>/dev/null; then
        echo "Error: Issue #${issue} が存在しません" >&2
        exit 1
    fi
}

# Issue body に deps.yaml 変更が含まれるか判定
# 引数: issue番号, issue_body（省略時は gh から取得）
# 戻り値: 0=含む, 1=含まない
issue_touches_deps_yaml() {
    local issue=$1
    local body="${2:-}"
    local comments="${3:-}"
    if [[ -z "$body" ]]; then
        body=$(gh issue view "$issue" --json body -q '.body' 2>/dev/null || true)
    fi
    if [[ -z "$comments" ]]; then
        comments=$(gh api "repos/{owner}/{repo}/issues/${issue}/comments" --jq '[.[].body] | join("\n")' 2>/dev/null || true)
    fi
    [[ -z "$body" && -z "$comments" ]] && return 1
    printf '%s\n%s\n' "$body" "$comments" | grep -qi 'deps\.yaml' && return 0
    return 1
}

# Phase 配列から deps.yaml 競合を検出し sequential 化
# phases_result 配列を直接書き換え
# グローバル: phases_result, DEPS_YAML_ISSUES（deps.yaml を変更する Issue のセット）
separate_deps_yaml_phases() {
    local -a new_phases=()
    local new_phase_num=0

    for entry in "${phases_result[@]}"; do
        local pissues="${entry#*:}"
        local -a issues_arr=($pissues)

        # この Phase 内で deps.yaml を変更する Issue を抽出
        local -a deps_yaml_in_phase=()
        local -a non_deps_yaml=()
        for issue in "${issues_arr[@]}"; do
            if [[ " ${DEPS_YAML_ISSUES[*]:-} " == *" $issue "* ]]; then
                deps_yaml_in_phase+=("$issue")
            else
                non_deps_yaml+=("$issue")
            fi
        done

        if [[ ${#deps_yaml_in_phase[@]} -le 1 ]]; then
            # 競合なし: そのまま
            new_phase_num=$((new_phase_num + 1))
            new_phases+=("${new_phase_num}:${pissues}")
        else
            # 競合あり: non_deps_yaml を1 Phase、deps_yaml Issue を各1 Phase に分離
            echo "⚠ Phase 分離: deps.yaml 変更 Issue ${deps_yaml_in_phase[*]} を sequential 化" >&2
            if [[ ${#non_deps_yaml[@]} -gt 0 ]]; then
                new_phase_num=$((new_phase_num + 1))
                new_phases+=("${new_phase_num}:${non_deps_yaml[*]}")
            fi
            for di in "${deps_yaml_in_phase[@]}"; do
                new_phase_num=$((new_phase_num + 1))
                new_phases+=("${new_phase_num}:${di}")
            done
        fi
    done

    phases_result=("${new_phases[@]}")
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

# --- --explicit モード ---
# "19,18 → 20 → 23" → Phase 1: [19,18], Phase 2: [20], Phase 3: [23]
parse_explicit() {
    local input="$1"
    local phase_num=0

    # declare arrays
    declare -a ALL_PHASES=()
    declare -a ALL_ISSUES=()

    # UTF-8 の → を区切りに Phase 分割
    # sed で → をデリミタに変換
    local phases_str
    phases_str=$(echo "$input" | sed 's/ *→ */\n/g')

    while IFS= read -r phase_str; do
        [[ -z "$phase_str" ]] && continue
        phase_num=$((phase_num + 1))

        # カンマ区切りで Issue 番号を抽出（# を除去、空白トリム）
        local issues_in_phase=()
        local cleaned
        cleaned=$(echo "$phase_str" | tr ',' '\n' | sed 's/[[:space:]]*#*\([0-9]*\)[[:space:]]*/\1/' | grep -v '^$')
        while IFS= read -r num; do
            [[ -z "$num" ]] && continue
            validate_issue "$num"
            issues_in_phase+=("$num")
            ALL_ISSUES+=("$num")
        done <<< "$cleaned"

        ALL_PHASES+=("${phase_num}:${issues_in_phase[*]}")
    done <<< "$phases_str"

    # plan.yaml 出力
    {
        echo "session_id: \"${SESSION_ID}\""
        echo "repo_mode: \"${REPO_MODE}\""
        echo "project_dir: \"${PROJECT_DIR}\""
        echo "phases:"
        for entry in "${ALL_PHASES[@]}"; do
            local pnum="${entry%%:*}"
            local pissues="${entry#*:}"
            echo "  - phase: ${pnum}"
            for issue in $pissues; do
                echo "    - ${issue}"
            done
        done

        # 依存関係: Phase N の Issue は Phase N-1 の全 Issue に依存
        echo "dependencies:"
        local prev_issues=""
        for entry in "${ALL_PHASES[@]}"; do
            local pissues="${entry#*:}"
            if [[ -n "$prev_issues" ]]; then
                for issue in $pissues; do
                    echo "  ${issue}:"
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
    echo "  Issues: ${#ALL_ISSUES[@]}"

    # --explicit モードでは deps.yaml 競合を警告のみ
    warn_deps_yaml_conflict_explicit "${ALL_PHASES[@]}"
}

# --- --issues モード ---
# Issue body から依存キーワードを検出し、トポロジカルソートで Phase 分割
parse_issues() {
    local input="$1"

    # Issue 番号リスト（# を除去）
    local issues=()
    for token in $input; do
        local num="${token#\#}"
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            validate_issue "$num"
            issues+=("$num")
        else
            echo "Error: 不正な Issue 番号: $token" >&2
            exit 1
        fi
    done

    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "Error: Issue 番号が指定されていません" >&2
        exit 1
    fi

    # deps.yaml 変更 Issue を検出
    DEPS_YAML_ISSUES=()

    # 依存関係を検出
    # key=issue, value=依存先Issue（スペース区切り）
    declare -A DEPS=()
    local issues_set=" ${issues[*]} "

    for issue in "${issues[@]}"; do
        local body
        body=$(gh issue view "$issue" --json body -q '.body' 2>/dev/null || true)
        [[ -z "$body" ]] && continue

        # Issue コメント取得（body とは別変数）
        local comments
        comments=$(gh api "repos/{owner}/{repo}/issues/${issue}/comments" --jq '[.[].body] | join("\n")' 2>/dev/null || true)

        # deps.yaml 変更判定（body + コメント）
        if issue_touches_deps_yaml "$issue" "$body" "$comments"; then
            DEPS_YAML_ISSUES+=("$issue")
        fi

        # body + コメントを結合して依存検索用テキストを作成
        local search_text="$body"
        if [[ -n "$comments" ]]; then
            search_text="${search_text}"$'\n'"${comments}"
        fi

        local deps_for_issue=""
        # 依存キーワードを検出（指定された Issue リスト内のもののみ）
        # "depends on #N", "after #N", "requires #N", "#N が前提", "#N 完了後" パターン
        local dep_nums
        dep_nums=$(printf '%s\n' "$search_text" | grep -oiP '(?:depends\s+on|after|requires|blocked\s+by)\s*#(\d+)' | grep -oP '\d+' || true)
        # "#N が前提" パターン
        dep_nums+=" "$(printf '%s\n' "$search_text" | grep -oP '#(\d+)\s*が前提' | grep -oP '\d+' || true)
        # "#N 完了後" パターン
        dep_nums+=" "$(printf '%s\n' "$search_text" | grep -oP '#(\d+)\s*完了後' | grep -oP '\d+' || true)

        for dep in $dep_nums; do
            # 入力 Issue リスト内のものだけを依存として記録
            if [[ "$issues_set" == *" $dep "* && "$dep" != "$issue" ]]; then
                if [[ -z "${deps_for_issue}" ]]; then
                    deps_for_issue="$dep"
                elif [[ ! " $deps_for_issue " == *" $dep "* ]]; then
                    deps_for_issue="$deps_for_issue $dep"
                fi
            fi
        done
        DEPS[$issue]="$deps_for_issue"
    done

    # 循環依存検出 + トポロジカルソート（Kahn's algorithm）
    declare -A IN_DEGREE=()
    for issue in "${issues[@]}"; do
        IN_DEGREE[$issue]=0
    done
    for issue in "${issues[@]}"; do
        for dep in ${DEPS[$issue]:-}; do
            IN_DEGREE[$issue]=$((${IN_DEGREE[$issue]} + 1))
        done
    done

    local sorted=()
    local phases_result=()
    local remaining=("${issues[@]}")
    local phase_num=0

    while [[ ${#remaining[@]} -gt 0 ]]; do
        phase_num=$((phase_num + 1))
        local ready=()
        local next_remaining=()

        for issue in "${remaining[@]}"; do
            local all_deps_resolved=true
            for dep in ${DEPS[$issue]:-}; do
                # dep がまだ sorted に含まれていなければ未解決
                if [[ ! " ${sorted[*]:-} " == *" $dep "* ]]; then
                    all_deps_resolved=false
                    break
                fi
            done
            if $all_deps_resolved; then
                ready+=("$issue")
            else
                next_remaining+=("$issue")
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

    # deps.yaml 競合 Phase 分離
    if [[ ${#DEPS_YAML_ISSUES[@]} -ge 2 ]]; then
        separate_deps_yaml_phases
        phase_num=${#phases_result[@]}

        # Phase 分離後の暗黙的依存を DEPS ハッシュに追加
        # deps_yaml Issue 間の連続 Phase のみ対象（non_deps_yaml Phase は除外）
        local prev_phase_issues=""
        local prev_is_deps_yaml=false
        for entry in "${phases_result[@]}"; do
            local pissues="${entry#*:}"
            # 現在の Phase が deps_yaml Issue のみで構成されているか判定
            local current_is_deps_yaml=true
            for issue in $pissues; do
                if [[ ! " ${DEPS_YAML_ISSUES[*]} " == *" $issue "* ]]; then
                    current_is_deps_yaml=false
                    break
                fi
            done
            # 前 Phase も deps_yaml で現在も deps_yaml の場合のみ依存追加
            if [[ -n "$prev_phase_issues" ]] && $prev_is_deps_yaml && $current_is_deps_yaml; then
                for issue in $pissues; do
                    for dep in $prev_phase_issues; do
                        # 重複チェック: 既存依存に含まれていなければ追加
                        if [[ -z "${DEPS[$issue]:-}" ]]; then
                            DEPS[$issue]="$dep"
                        elif [[ ! " ${DEPS[$issue]} " == *" $dep "* ]]; then
                            DEPS[$issue]="${DEPS[$issue]} $dep"
                        fi
                    done
                done
            fi
            prev_phase_issues="$pissues"
            prev_is_deps_yaml=$current_is_deps_yaml
        done
    fi

    # plan.yaml 出力
    {
        echo "session_id: \"${SESSION_ID}\""
        echo "repo_mode: \"${REPO_MODE}\""
        echo "project_dir: \"${PROJECT_DIR}\""
        echo "phases:"
        for entry in "${phases_result[@]}"; do
            local pnum="${entry%%:*}"
            local pissues="${entry#*:}"
            echo "  - phase: ${pnum}"
            for issue in $pissues; do
                echo "    - ${issue}"
            done
        done

        echo "dependencies:"
        local has_deps=false
        for issue in "${issues[@]}"; do
            if [[ -n "${DEPS[$issue]:-}" ]]; then
                has_deps=true
                echo "  ${issue}:"
                for dep in ${DEPS[$issue]}; do
                    echo "  - ${dep}"
                done
            fi
        done
    } > "$PLAN_FILE"

    echo "plan.yaml 生成完了: ${PLAN_FILE}"
    echo "  Session: ${SESSION_ID}"
    echo "  Phases: ${phase_num}"
    echo "  Issues: ${#issues[@]}"
}

# --- メイン ---
case "$MODE" in
    explicit) parse_explicit "$INPUT" ;;
    issues)   parse_issues "$INPUT" ;;
    *)        echo "Error: 不明なモード: $MODE" >&2; exit 1 ;;
esac
