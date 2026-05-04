#!/usr/bin/env bash
# autopilot-cleanup.sh - セッション完了後の一括クリーンアップ
# done/failed state file のアーカイブ + 孤立 worktree 検出・削除
set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") --autopilot-dir DIR [--project-dir DIR] [--ttl SECONDS] [--dry-run]

セッション完了後の残存リソースを一括クリーンアップする。

Options:
  --autopilot-dir DIR   .autopilot ディレクトリのパス（必須）
  --project-dir DIR     プロジェクトルート（並列 Wave の active branches 保護に使用）
  --ttl SECONDS         failed セッションのアーカイブ閾値（デフォルト: 86400 = 24h）
  --dry-run             アクションをログ出力のみ（実行しない）
  -h, --help            このヘルプを表示
EOF
}

# ── 引数パース ──
AUTOPILOT_DIR=""
PROJECT_DIR=""
TTL="${DEV_AUTOPILOT_CLEANUP_TTL:-86400}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --autopilot-dir) AUTOPILOT_DIR="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
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
if [[ -n "$PROJECT_DIR" && "$PROJECT_DIR" =~ \.\. ]]; then
  echo "ERROR: PROJECT_DIR に '..' は使用できません" >&2
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

# ── 依存チェーン判定 ──
# is_in_dependency_chain <issue_num>
# Returns 0 if issue_num is still needed by a pending dependent (skip archive)
# Returns 1 if no dependency chain or all dependents are done (archive OK)
is_in_dependency_chain() {
  local issue_num="$1"
  local plan_file="$AUTOPILOT_DIR/plan.yaml"

  [[ -f "$plan_file" ]] || return 1

  # plan.yaml の dependencies: セクションから issue_num を参照している後続 issue を取得
  local dependers
  dependers=$(awk -v target="$issue_num" '
    /^dependencies:/ { in_deps=1; next }
    in_deps && /^[^ ]/ { in_deps=0 }
    in_deps && /^  [[:alnum:]_#-]+:/ { key=$0; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", key) }
    in_deps && /^  - / { dep=$0; gsub(/^[[:space:]]*- /, "", dep); if (dep==target && key!="") print key }
  ' "$plan_file" 2>/dev/null || true)

  [[ -n "$dependers" ]] || return 1

  # 後続 issue の状態を確認: いずれか未完了なら archive スキップ
  local depender
  for depender in $dependers; do
    local dep_file="$AUTOPILOT_DIR/issues/issue-${depender}.json"
    if [[ -f "$dep_file" ]]; then
      local dep_status
      dep_status=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status','unknown'))" "$dep_file" 2>/dev/null || echo "unknown")
      if [[ "$dep_status" != "done" ]]; then
        return 0  # 後続 issue が未完了 → archive スキップ
      fi
    else
      # issues/ に存在しない → archive ディレクトリを確認
      local archived
      archived=$(find "$AUTOPILOT_DIR/archive" -name "issue-${depender}.json" 2>/dev/null | head -1)
      if [[ -z "$archived" ]]; then
        return 0  # archive にも存在しない → 後続 issue が未起動 → archive スキップ
      fi
      # archive に存在 → 後続 issue 完了済み → 次の depender をチェック
    fi
  done

  return 1  # 全後続 issue 完了済み → archive 可能
}

# セッション完了判定: Phase 1 実行前に全 issue が done か確認（done archive 後は判定不能）
# is_session_completed=true のみ session.json を archive する (#978 整合)
_is_all_issues_done() {
  local issues_dir="$1/issues"
  [[ -d "$issues_dir" ]] || return 1
  shopt -s nullglob
  local files=("$issues_dir"/issue-*.json)
  shopt -u nullglob
  ((${#files[@]} > 0)) || return 1
  local f
  for f in "${files[@]}"; do
    local status=""
    status=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status','unknown'))" "$f" 2>/dev/null || echo "unknown")
    [[ "$status" == "done" ]] || return 1
  done
  return 0
}

SESSION_COMPLETED=false
if _is_all_issues_done "$AUTOPILOT_DIR"; then
  SESSION_COMPLETED=true
fi

echo "[cleanup] セッション $SESSION_ID のクリーンアップを開始（TTL=${TTL}s, dry-run=$DRY_RUN）" >&2

# ── Phase 1: state file アーカイブ ──
for issue_file in "$AUTOPILOT_DIR/issues"/issue-*.json; do
  [[ -f "$issue_file" ]] || continue

  issue_num=$(basename "$issue_file" .json); issue_num="${issue_num#issue-}"
  status=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status','unknown'))" "$issue_file" 2>/dev/null || echo "unknown")

  case "$status" in
    done)
      # done → 依存チェーン確認後にアーカイブ
      if is_in_dependency_chain "$issue_num"; then
        echo "[cleanup] スキップ: issue-${issue_num}.json (status=done, dependency-pending)" >&2
      else
        if $DRY_RUN; then
          echo "[dry-run] アーカイブ: issue-${issue_num}.json (status=done)" >&2
        else
          mkdir -p "$ARCHIVE_DIR"
          mv "$issue_file" "$ARCHIVE_DIR/"
          echo "[cleanup] アーカイブ: issue-${issue_num}.json (status=done) → $ARCHIVE_DIR/" >&2
        fi
        ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
      fi
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
# state file に記録された branch を収集（並列 Wave 全体をスキャン）
declare -A active_branches

# 指定 autopilot-dir の issues
for issue_file in "$AUTOPILOT_DIR/issues"/issue-*.json; do
  [[ -f "$issue_file" ]] || continue
  branch=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('branch',''))" "$issue_file" 2>/dev/null || echo "")
  [[ -n "$branch" ]] && active_branches["$branch"]=1
done

# --project-dir 指定時: 他の Wave (.autopilot*/) の issues も走査して active branches を保護
if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
  for wave_dir in "$PROJECT_DIR"/.autopilot*/; do
    [[ -d "$wave_dir/issues" ]] || continue
    # 同一 autopilot-dir は既にスキャン済み（末尾スラッシュを正規化）
    [[ "$(realpath "$wave_dir" 2>/dev/null || echo "${wave_dir%/}")" == \
       "$(realpath "$AUTOPILOT_DIR" 2>/dev/null || echo "$AUTOPILOT_DIR")" ]] && continue
    for issue_file in "$wave_dir/issues"/issue-*.json; do
      [[ -f "$issue_file" ]] || continue
      branch=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('branch',''))" "$issue_file" 2>/dev/null || echo "")
      [[ -n "$branch" ]] && active_branches["$branch"]=1
    done
  done
fi

# git worktree list から autopilot 関連の worktree を検出
while IFS= read -r line; do
  # porcelain 形式: "worktree /path/to/worktree" の行
  if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
    wt_path="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
    wt_branch="${BASH_REMATCH[1]}"
    # autopilot が作成した worktree のみ対象（全 6 プレフィックス対象: _ALLOWED_PREFIXES 参照 worktree.py:31）
    if [[ "$wt_branch" =~ ^(feat|fix|refactor|docs|test|chore)/ && -n "${wt_path:-}" ]]; then
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

        # active にも archive にも存在しない（真の孤立）、または archive 済み → 削除
        # （元コードの `if $is_archived` 条件反転バグを修正: 真の孤立を含む全ケースを対象）
        if $DRY_RUN; then
          if $is_archived; then
            echo "[dry-run] 孤立 worktree 削除: $wt_path (branch=$wt_branch, archived)" >&2
          else
            echo "[dry-run] 孤立 worktree 削除: $wt_path (branch=$wt_branch, 真の孤立: state file なし)" >&2
          fi
        else
          _wt_del_out="" _wt_ok=false
          for _wt_r in 1 2; do
            if _wt_del_out=$(bash "$SCRIPTS_ROOT/worktree-delete.sh" "$wt_branch" 2>&1); then
              _wt_ok=true; break
            fi
            [[ $_wt_r -lt 2 ]] && sleep 2
          done
          if $_wt_ok; then
            echo "[cleanup] 孤立 worktree 削除: $wt_path (branch=$wt_branch)" >&2
            # リモートブランチも削除（パストラバーサル防止: `.` 除外 regex を使用）
            if [[ -n "$wt_branch" && "$wt_branch" =~ ^[a-zA-Z0-9_/.-]+$ ]]; then
              # AC-2: git push --delete 直前に OPEN PR がないか確認
              # gh 不在時はフェールセーフ（削除をスキップ）
              if ! command -v gh &>/dev/null; then
                echo "WARN: [cleanup] gh CLI が未インストールです — PR チェック不可のためリモートブランチ削除スキップ: $wt_branch" >&2
              else
                _open_prs=$(gh pr list --head "$wt_branch" --state open 2>/dev/null || true)
                if [[ -n "$_open_prs" ]]; then
                  echo "WARN: [cleanup] ブランチ $wt_branch に OPEN PR があります — リモートブランチ削除スキップ" >&2
                else
                  git push origin --delete "$wt_branch" 2>/dev/null || \
                    echo "[cleanup] ⚠️ リモートブランチ削除失敗: $wt_branch（続行）" >&2
                fi
              fi
            else
              echo "[cleanup] ⚠️ ブランチ名に不正な文字: $wt_branch — リモート削除スキップ" >&2
            fi
          else
            echo "[cleanup] ⚠️ worktree 削除失敗: $wt_branch（続行）: ${_wt_del_out}" >&2
          fi
        fi
        ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
      fi
    fi
    wt_path=""
    wt_branch=""
  fi
done < <(git worktree list --porcelain 2>/dev/null || true)

# ── Phase 3: session.json archive (is_session_completed=true の場合のみ) ──
if [[ "$SESSION_COMPLETED" == "true" && -f "$AUTOPILOT_DIR/session.json" ]]; then
  if $DRY_RUN; then
    echo "[dry-run] session.json archive: $AUTOPILOT_DIR/session.json → $ARCHIVE_DIR/" >&2
  else
    mkdir -p "$ARCHIVE_DIR"
    mv "$AUTOPILOT_DIR/session.json" "$ARCHIVE_DIR/"
    echo "[cleanup] session.json archive: $SESSION_ID → $ARCHIVE_DIR/" >&2
  fi
elif [[ -f "$AUTOPILOT_DIR/session.json" ]]; then
  echo "WARN: session.json を archive せず保持 (in-progress issues あり, is_session_completed=false)" >&2
fi

# ── 結果サマリー ──
echo "[cleanup] 完了: アーカイブ=${ARCHIVED_COUNT}件, 孤立worktree削除=${ORPHAN_COUNT}件" >&2
