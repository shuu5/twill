#!/usr/bin/env bash
# autopilot-init.sh - .autopilot/ ディレクトリの初期化とセッション排他制御
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# プロジェクトルートを特定（main/ worktree を前提）
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# AUTOPILOT_DIR 環境変数によるオーバーライドをサポート（テスト用）
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}"
if [[ "$AUTOPILOT_DIR" == *".."* ]]; then
  echo "ERROR: AUTOPILOT_DIR にパストラバーサル文字 '..' が含まれています: $AUTOPILOT_DIR" >&2
  exit 1
fi
ISSUES_DIR="$AUTOPILOT_DIR/issues"
ARCHIVE_DIR="$AUTOPILOT_DIR/archive"
SESSION_FILE="$AUTOPILOT_DIR/session.json"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

# セッション完了判定: 全 issue が done なら true を返す
# issues/ dir 不在または空の場合は未完了扱い（新 Wave 開始直後の race condition 防止 #732）
# SSoT を session.json.issues[] から per-issue file（issues/issue-*.json）に移行（#978）
is_session_completed() {
  local autopilot_dir="$1"
  local issues_dir="$autopilot_dir/issues"
  [[ -d "$issues_dir" ]] || return 1   # dir 不在 → 未完了（fail-closed 維持）
  shopt -s nullglob
  local files=("$issues_dir"/issue-*.json)
  shopt -u nullglob                    # スコープ漏れ防止
  ((${#files[@]} > 0)) || return 1     # 空 dir → 未完了（#732 race protection）
  local f
  for f in "${files[@]}"; do
    local status
    status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null) || true
    [[ "$status" == "done" ]] || return 1
  done
  return 0
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--check-only]

.autopilot/ ディレクトリを初期化し、既存セッションの排他制御を行う。

Options:
  --check-only  既存セッションの確認のみ（ディレクトリ作成しない）
  --force       stale セッションを強制削除して初期化
  -h, --help    このヘルプを表示
EOF
}

check_only=false
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) check_only=true; shift ;;
    --force) force=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# 既存セッションチェック
if [[ -f "$SESSION_FILE" ]]; then
  started_at=$(jq -r '.started_at // empty' "$SESSION_FILE" 2>/dev/null)
  session_id=$(jq -r '.session_id // "unknown"' "$SESSION_FILE" 2>/dev/null)

  if [[ -n "$started_at" ]]; then
    # started_at の ISO 8601 形式バリデーション
    if [[ ! "$started_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
      echo "WARN: started_at の形式が不正です: $started_at。stale として扱います" >&2
      started_epoch=0
    else
      # 経過時間を計算（秒）
      started_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo "0")
    fi
    now_epoch=$(date +%s)
    elapsed=$(( now_epoch - started_epoch ))
    hours=$(( elapsed / 3600 ))

    if is_session_completed "$AUTOPILOT_DIR"; then
      # 完了済みセッション: --force なしで自動削除（Wave 遷移ブロック防止）
      echo "INFO: 完了済みセッション (${hours}h経過) を自動削除します: $session_id" >&2
      rm -f "$SESSION_FILE"
      rm -f "$ISSUES_DIR"/issue-*.json 2>/dev/null || true
    elif (( hours >= 24 )); then
      if [[ "$force" == "true" ]]; then
        echo "WARN: stale セッション (${hours}h経過) を強制削除します: $session_id" >&2
        rm -f "$SESSION_FILE"
        # 旧セッションの issue ファイルもクリーンアップ
        rm -f "$ISSUES_DIR"/issue-*.json 2>/dev/null || true
      else
        echo "WARN: stale セッションが検出されました (session_id=$session_id, ${hours}h経過)" >&2
        echo "削除するには --force を指定してください" >&2
        exit 2
      fi
    else
      # < 24h + not completed: check orchestrator.pid before blocking
      _orch_pid_file="$AUTOPILOT_DIR/orchestrator.pid"
      _orch_alive=false
      if [[ -f "$_orch_pid_file" ]]; then
        _orch_pid=$(cat "$_orch_pid_file" 2>/dev/null || echo "")
        if [[ "$_orch_pid" =~ ^[0-9]+$ ]] && kill -0 "$_orch_pid" 2>/dev/null; then
          _orch_alive=true
        fi
      fi
      if [[ "$_orch_alive" == "true" ]]; then
        echo "ERROR: orchestrator プロセスが実行中です (pid=$_orch_pid, session_id=$session_id)" >&2
        echo "同一プロジェクトでの複数 autopilot セッションの同時実行は禁止されています" >&2
        exit 1
      else
        echo "INFO: orchestrator 不在または dead PID — resume_safe として続行します (session_id=$session_id, ${hours}h経過)" >&2
      fi
    fi
  fi
fi

if [[ "$check_only" == "true" ]]; then
  echo "OK: 実行中のセッションはありません"
  exit 0
fi

# ベースディレクトリを先に作成（ロック用の親ディレクトリが必要）
mkdir -p "$AUTOPILOT_DIR"

# アトミックロック取得（TOCTOU 防止: mkdir はアトミック操作）
LOCK_DIR="$AUTOPILOT_DIR/.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: 別のプロセスが初期化中です（ロック: $LOCK_DIR）" >&2
  exit 1
fi
# ロック解放用のトラップ
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# サブディレクトリ作成
mkdir -p "$ISSUES_DIR"
mkdir -p "$ARCHIVE_DIR"

# クロスリポジトリ: repos 名前空間ディレクトリ作成
# plan.yaml の repos セクションが存在する場合、各 repo_id 用のサブディレクトリを作成
PLAN_FILE="$AUTOPILOT_DIR/plan.yaml"
if [[ -f "$PLAN_FILE" ]] && grep -q '^repos:' "$PLAN_FILE"; then
  REPOS_DIR="$AUTOPILOT_DIR/repos"
  # repos: セクションから repo_id を抽出（インデント2スペース + コロン行）
  while IFS= read -r line; do
    repo_id=$(echo "$line" | sed -n 's/^  \([a-zA-Z0-9_-]*\):/\1/p')
    if [[ -n "$repo_id" ]]; then
      mkdir -p "$REPOS_DIR/$repo_id/issues"
    fi
  done < <(sed -n '/^repos:/,/^[a-z]/p' "$PLAN_FILE" | head -n -1)
fi

# .gitignore に .autopilot/ と .autopilot-*/ を追加（未追加の場合）
# multi-instance support (#1169): .autopilot-wave10/ 等の並列 dir も除外
gitignore="$PROJECT_ROOT/.gitignore"
if [[ -f "$gitignore" ]]; then
  if ! grep -qxF '.autopilot/' "$gitignore"; then
    echo '.autopilot/' >> "$gitignore"
  fi
  if ! grep -qxF '.autopilot-*/' "$gitignore"; then
    echo '.autopilot-*/' >> "$gitignore"
  fi
else
  printf '.autopilot/\n.autopilot-*/\n' > "$gitignore"
fi

echo "OK: .autopilot/ を初期化しました"
echo "  issues: $ISSUES_DIR"
echo "  archive: $ARCHIVE_DIR"
if [[ -d "${REPOS_DIR:-}" ]]; then
  echo "  repos: $REPOS_DIR"
  for d in "$REPOS_DIR"/*/; do
    [[ -d "$d" ]] && echo "    - $(basename "$d")"
  done
fi
