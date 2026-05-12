#!/usr/bin/env bash
# path-validate.sh — SUPERVISOR_DIR パストラバーサル防御 (Issue #1165)
#
# Usage: source path-validate.sh && validate_supervisor_dir <path>
# Returns 0 if path is acceptable, 2 if rejected

validate_supervisor_dir() {
    local raw_path="$1"

    # 空文字チェック
    if [[ -z "$raw_path" ]]; then
        return 2
    fi

    # .. セグメント含有チェック（raw 入力で拒否）
    if [[ "$raw_path" == *".."* ]]; then
        return 2
    fi

    # 正規化（シンボリックリンク解決 + --canonicalize-missing で存在不要）
    local canonical_path
    if command -v realpath >/dev/null 2>&1; then
        canonical_path=$(realpath -m "$raw_path" 2>/dev/null) || return 2
    else
        canonical_path="$raw_path"
    fi

    # whitelist: HOME / PWD / TMPDIR 配下のみ許可
    local home_dir="${HOME:-}"
    local pwd_dir="${PWD:-}"
    local tmp_dir="${TMPDIR:-/tmp}"

    [[ -n "$home_dir" && "$canonical_path" == "$home_dir/"* ]] && return 0
    [[ -n "$pwd_dir" && "$canonical_path" == "$pwd_dir/"* ]] && return 0
    [[ "$canonical_path" == "$tmp_dir/"* ]] && return 0

    return 2
}
