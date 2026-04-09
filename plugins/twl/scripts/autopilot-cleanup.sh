#!/usr/bin/env bash
# autopilot-cleanup.sh - セッション完了後の一括クリーンアップ
# done/failed state file のアーカイブ + 孤立 worktree 検出・削除
set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") --autopilot-dir DIR [--ttl SECONDS] [--dry-run]

セッション完了後の残存リソースを一括クリーンアップする。

Options:
  --autopilot-dir DIR   .autopilot ディレクトリのパス（必須）
  --ttl SECONDS         failed セッションのアーカイブ閾値（デフォルト: 86400 = 24h）
  --dry-run             アクションをログ出力のみ（実行しない）
  -h, --help            このヘルプを表示
EOF
}

# ── 引数パース ──
AUTOPILOT_DIR=""
TTL="${DEV_AUTOPILOT_CLEANUP_TTL:-86400}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --autopilot-dir) AUTOPILOT_DIR="$2"; shift 2 ;;
    --ttl) TTL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$AUTOPILOT_DIR" ]]; then
  echo "ERROR: --autopilot-dir は必須です" >&2
  usage >&2
  exit 1
fi

# パストラバーサル防止（ディレクトリ存在確認より先に実行）
if [[ "$AUTOPILOT_DIR" =~ \.\. ]]; then
  echo "ERROR: AUTOPILOT_DIR に '..' は使用できません" >&2
  exit 1
fi

if [[ ! -d "$AUTOPILOT_DIR/issues" ]]; then
  echo "OK: $AUTOPILOT_DIR/issues が存在しません。クリーンアップ不要" >&2
  exit 0
fi

# ── session_id 取得 ──
SESSION_ID=""
if [[ -f "$AUTOPILOT_DIR/session.json" ]]; then
  SESSION_ID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('session_id',''))" "$AUTOPILOT_DIR/session.json" 2>/dev/null || echo "")
fi
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="unknown"
fi
# SESSION_ID パストラバーサル防止
if [[ ! "$SESSION_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: SESSION_ID に不正な文字が含まれています: $SESSION_ID" >&2
  exit 1
fi

# TTL 数値検証
if [[ ! "$TTL" =~ ^[0-9]+$ ]]; then
  echo "ERROR: TTL は正の整数である必要があります: $TTL" >&2
  exit 1
fi

# ── アーカイブ先ディレクトリ ──
ARCHIVE_DIR="$AUTOPILOT_DIR/archive/$SESSION_ID"

NOW_EPOCH=$(date +%s)
ARCHIVED_COUNT=0
ORPHAN_COUNT=0

echo "[cleanup] セッション $SESSION_ID のクリーンアップを開始（TTL=${TTL}s, dry-run=$DRY_RUN）" >&2

# ── Phase 1: state file アーカイブ ──
for issue_file in "$AUTOPILOT_DIR/issues"/issue-*.json; do
  [[ -f "$issue_file" ]] || continue

  issue_num=$(basename "$issue_file" | grep -oP '\d+')
  status=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status','unknown'))" "$issue_file" 2>/dev/null || echo "unknown")

  case "$status" in
    done)
      # done → 即座にアーカイブ
      if $DRY_RUN; then
        echo "[dry-run] アーカイブ: issue-${issue_num}.json (status=done)" >&2
      else
        mkdir -p "$ARCHIVE_DIR"
        mv "$issue_file" "$ARCHIVE_DIR/"
        echo "[cleanup] アーカイブ: issue-${issue_num}.json (status=done) → $ARCHIVE_DIR/" >&2
      fi
      ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
      ;;
    failed)
      # failed → TTL 超過時のみアーカイブ
      started_at=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('started_at',''))" "$issue_file" 2>/dev/null || echo "")
      if [[ -n "$started_at" ]]; then
        started_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo "")
        if [[ -z "$started_epoch" ]]; then
          echo "[cleanup] スキップ: issue-${issue_num}.json (status=failed, started_at パース失敗: $started_at)" >&2
          continue
        fi
        elapsed=$(( NOW_EPOCH - started_epoch ))
        if [[ $elapsed -ge $TTL ]]; then
          if $DRY_RUN; then
            echo "[dry-run] アーカイブ: issue-${issue_num}.json (status=failed, elapsed=${elapsed}s >= TTL=${TTL}s)" >&2
          else
            mkdir -p "$ARCHIVE_DIR"
            mv "$issue_file" "$ARCHIVE_DIR/"
            echo "[cleanup] アーカイブ: issue-${issue_num}.json (status=failed, elapsed=${elapsed}s) → $ARCHIVE_DIR/" >&2
          fi
          ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
        else
          echo "[cleanup] スキップ: issue-${issue_num}.json (status=failed, elapsed=${elapsed}s < TTL=${TTL}s)" >&2
        fi
      else
        echo "[cleanup] スキップ: issue-${issue_num}.json (status=failed, started_at 不明)" >&2
      fi
      ;;
    running)
      # running → 安全性のため対象外
      echo "[cleanup] スキップ: issue-${issue_num}.json (status=running)" >&2
      ;;
    *)
      echo "[cleanup] スキップ: issue-${issue_num}.json (status=${status})" >&2
      ;;
  esac
done

# ── Phase 2: 孤立 worktree 検出・削除 ──
# state file に記録された branch を収集
declare -A active_branches
for issue_file in "$AUTOPILOT_DIR/issues"/issue-*.json; do
  [[ -f "$issue_file" ]] || continue
  branch=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('branch',''))" "$issue_file" 2>/dev/null || echo "")
  if [[ -n "$branch" ]]; then
    active_branches["$branch"]=1
  fi
done

# git worktree list から autopilot 関連の worktree を検出
while IFS= read -r line; do
  # porcelain 形式: "worktree /path/to/worktree" の行
  if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
    wt_path="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
    wt_branch="${BASH_REMATCH[1]}"
    # autopilot が作成した worktree のみ対象（feat/ プレフィックス）
    if [[ "$wt_branch" =~ ^feat/ && -n "${wt_path:-}" ]]; then
      # アーカイブ済み state file の branch と照合
      # active_branches に含まれていない = 孤立 worktree
      if [[ -z "${active_branches[$wt_branch]+_}" ]]; then
        # アーカイブディレクトリ内の state file も確認
        is_archived=false
        if [[ -d "$AUTOPILOT_DIR/archive" ]]; then
          for archive_file in "$AUTOPILOT_DIR/archive"/*/issue-*.json; do
            [[ -f "$archive_file" ]] || continue
            archived_branch=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('branch',''))" "$archive_file" 2>/dev/null || echo "")
            if [[ "$archived_branch" == "$wt_branch" ]]; then
              is_archived=true
              break
            fi
          done
        fi

        if $is_archived; then
          if $DRY_RUN; then
            echo "[dry-run] 孤立 worktree 削除: $wt_path (branch=$wt_branch)" >&2
          else
            if bash "$SCRIPTS_ROOT/worktree-delete.sh" "$wt_branch" 2>/dev/null; then
              echo "[cleanup] 孤立 worktree 削除: $wt_path (branch=$wt_branch)" >&2
            else
              echo "[cleanup] ⚠️ worktree 削除失敗: $wt_branch（続行）" >&2
            fi
          fi
          ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
        fi
      fi
    fi
    wt_path=""
    wt_branch=""
  fi
done < <(git worktree list --porcelain 2>/dev/null || true)

# ── 結果サマリー ──
echo "[cleanup] 完了: アーカイブ=${ARCHIVED_COUNT}件, 孤立worktree削除=${ORPHAN_COUNT}件" >&2
