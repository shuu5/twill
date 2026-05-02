#!/usr/bin/env bash
# setup-origin-labels.sh - cross-origin Phase A: origin:* label 体系定義 + 既存 Issue 遡及付与
#
# 使用方法:
#   bash plugins/twl/scripts/onboarding/setup-origin-labels.sh [--dry-run]
#
# 機能:
#   1. origin:host:* / origin:repo:* ラベルを GitHub に作成（冪等）
#   2. 既存 OPEN/CLOSED Issue を多段階検索で分類し cross-repo 起源を確定
#   3. 確定 Issue に --add-label で一括付与（既付与は skip）
#   4. AC2 確定件数をユーザーに報告（3 件超の場合は差分を明示）
#
# doobidoo memory: 3c47c84a (soap-copilot-mock observer-lesson, cross-reference 情報)
# 参考: .explore/wave19-cross-origin-tracking/summary.md §7 Phase A

set -euo pipefail

[[ "${BASH_SOURCE[0]}" == "${0}" ]] || return 0

REPO="shuu5/twill"
DRY_RUN=false
VERBOSE=false
HOST_ALIASES_FILE="${HOME}/.config/twl/host-aliases.json"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --verbose) VERBOSE=true ;;
  esac
done

log() { echo "[setup-origin-labels] $*"; }
log_dry() { echo "[DRY-RUN] $*"; }

# ---------------------------------------------------------------------------
# Phase 1: ラベル作成
# ---------------------------------------------------------------------------

create_labels() {
  log "Phase 1: origin:* ラベル作成"

  local host_color="fef2c0"
  local repo_color="bfd4f2"

  local host_labels=(
    "origin:host:ipatho-1"
    "origin:host:ipatho2"
    "origin:host:thinkpad"
  )
  local repo_labels=(
    "origin:repo:soap-copilot-mock"
    "origin:repo:twill"
  )

  for label in "${host_labels[@]}"; do
    if gh label list --repo "$REPO" | grep -qF "$label"; then
      log "  skip (already exists): $label"
    else
      if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "gh label create \"$label\" --repo $REPO --color $host_color"
      else
        gh label create "$label" --repo "$REPO" --color "$host_color" --description "起票元 host: ${label#origin:host:}"
        log "  created: $label"
      fi
    fi
  done

  for label in "${repo_labels[@]}"; do
    if gh label list --repo "$REPO" | grep -qF "$label"; then
      log "  skip (already exists): $label"
    else
      if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "gh label create \"$label\" --repo $REPO --color $repo_color"
      else
        gh label create "$label" --repo "$REPO" --color "$repo_color" --description "起源 repo: ${label#origin:repo:}"
        log "  created: $label"
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# Phase 2: 既存 Issue の多段階分類
# ---------------------------------------------------------------------------

# doobidoo memory hash 3c47c84a の cross-reference 情報から確認済み Issue
KNOWN_CROSS_ORIGIN=(1242 1244 1231)

classify_issues() {
  log "Phase 2: 既存 Issue の多段階分類 (--state all --limit 500)"

  # host-aliases.json から hostname → alias の対応を取得
  local current_host
  current_host="$(hostname)"
  local current_alias="unknown"
  if [[ -f "$HOST_ALIASES_FILE" ]]; then
    current_alias=$(python3 -c "
import json, sys
with open('${HOST_ALIASES_FILE}') as f:
    d = json.load(f)
alias = d.get('${current_host}', 'unknown')
print(alias)
" 2>/dev/null || echo "unknown")
  fi
  log "  current host: $current_host → alias: $current_alias"

  # Step 1: キーワード grep で候補 Issue を列挙
  local search_query="検出元 OR soap-copilot OR ipatho OR thinkpad OR 起源 OR observer"
  local candidates
  candidates=$(gh issue list --repo "$REPO" --state all --limit 500 \
    --search "$search_query" \
    --json number,title,labels 2>/dev/null || echo "[]")

  local candidate_numbers
  candidate_numbers=$(echo "$candidates" | python3 -c "
import json, sys
items = json.load(sys.stdin)
nums = [str(i['number']) for i in items]
print(' '.join(nums))
" 2>/dev/null || echo "")

  # Step 2 (本文確認): 候補 Issue の body を gh issue view --json body で取得し cross-repo 起源を確認
  local verified_numbers=()
  for n in $candidate_numbers; do
    local body
    body=$(gh issue view "$n" --repo "$REPO" --json body -q '.body' 2>/dev/null || echo "")
    if echo "$body" | grep -qiE "検出元|soap-copilot|cross-repo|起票.*cross|observer.*wave|ipatho"; then
      verified_numbers+=("$n")
    fi
  done
  candidate_numbers="${verified_numbers[*]:-}"

  # Step 3: doobidoo memory hash 3c47c84a の cross-reference で既知 Issue を補完
  local all_targets=()
  for n in "${KNOWN_CROSS_ORIGIN[@]}"; do
    all_targets+=("$n")
  done
  for n in $candidate_numbers; do
    # 重複排除
    local found=false
    for existing in "${all_targets[@]:-}"; do
      [[ "$existing" == "$n" ]] && found=true && break
    done
    [[ "$found" == "false" ]] && all_targets+=("$n")
  done

  log "  候補 Issue 総数: ${#all_targets[@]} 件"
  echo "${all_targets[*]:-}"
}

# ---------------------------------------------------------------------------
# Phase 3: ラベル付与（べき等）
# ---------------------------------------------------------------------------

assign_labels() {
  local issue_numbers=("$@")
  local assigned=0
  local skipped=0

  log "Phase 3: ラベル付与（べき等、${#issue_numbers[@]} 件対象）"

  # host-aliases.json から current host の alias を取得
  local current_host
  current_host="$(hostname)"
  local host_alias="unknown"
  if [[ -f "$HOST_ALIASES_FILE" ]]; then
    host_alias=$(python3 -c "
import json
with open('${HOST_ALIASES_FILE}') as f:
    d = json.load(f)
print(d.get('${current_host}', 'unknown'))
" 2>/dev/null || echo "unknown")
  fi

  for num in "${issue_numbers[@]}"; do
    # 既存ラベルを確認（べき等チェック）
    local existing_labels
    existing_labels=$(gh issue view "$num" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || echo "")

    local host_label="origin:host:${host_alias}"
    local repo_label="origin:repo:soap-copilot-mock"

    # origin:host:* が既に付与済みかチェック
    local has_host_label=false
    if echo "$existing_labels" | grep -qF "origin:host:"; then
      has_host_label=true
    fi

    if [[ "$has_host_label" == "true" ]]; then
      [[ "$VERBOSE" == "true" ]] && log "  skip (already labeled): #$num"
      ((skipped++)) || true
    else
      if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "gh issue edit $num --repo $REPO --add-label \"$host_label\" --add-label \"$repo_label\""
      else
        gh issue edit "$num" --repo "$REPO" \
          --add-label "$host_label" \
          --add-label "$repo_label"
        log "  labeled: #$num (+$host_label, +$repo_label)"
      fi
      ((assigned++)) || true
    fi
  done

  log "  付与: $assigned 件 / skip: $skipped 件"
  echo "$assigned"
}

# ---------------------------------------------------------------------------
# Phase 4: 件数報告（AC7）
# ---------------------------------------------------------------------------

report_results() {
  local total="$1"
  local confirmed_nums=("${@:2}")

  log "Phase 4: 結果報告"
  echo ""
  echo "=== origin:* ラベル付与 完了 ==="
  echo "確定件数: $total 件"

  if [[ "$total" -gt 3 ]]; then
    echo "（3 件超のため差分を明示）"
    echo "確定 Issue 一覧:"
    for n in "${confirmed_nums[@]}"; do
      echo "  #$n"
    done
  else
    echo "確定 Issue: ${confirmed_nums[*]:-（なし）}"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "注: --dry-run モードで実行されました。実際の変更は行われていません。"
  fi

  # Project Board #6 (shuu5/twill-ecosystem) view filter 追加について:
  # 以下のフィルターを手動で追加してください（GitHub Project Board は API 経由の追加が制限されています）:
  #   - Cross-repo:          label:origin:repo:soap-copilot-mock
  #   - ipatho2 host 起票:   label:origin:host:ipatho2
  #   - ipatho-1 host 起票:  label:origin:host:ipatho-1
  #   - thinkpad host 起票:  label:origin:host:thinkpad
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  log "=== setup-origin-labels.sh 開始 ==="
  [[ "$DRY_RUN" == "true" ]] && log "DRY-RUN モード有効"

  create_labels

  local issue_numbers_str
  issue_numbers_str=$(classify_issues)
  IFS=' ' read -r -a issue_numbers <<< "$issue_numbers_str"

  local assigned_count=0
  if [[ "${#issue_numbers[@]}" -gt 0 && -n "${issue_numbers[0]:-}" ]]; then
    assigned_count=$(assign_labels "${issue_numbers[@]}")
  else
    log "対象 Issue なし"
  fi

  report_results "${#issue_numbers[@]}" "${issue_numbers[@]:-}"
}

main "$@"
