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

log() { echo "[setup-origin-labels] $*" >&2; }
log_dry() { echo "[DRY-RUN] $*" >&2; }

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

_resolve_host_alias() {
  local host="$1"
  if [[ ! -f "$HOST_ALIASES_FILE" ]]; then
    echo "unknown"
    return
  fi
  # 環境変数経由で渡しインジェクションを防ぐ
  TWL_HOST="$host" TWL_ALIASES_FILE="$HOST_ALIASES_FILE" python3 -c '
import json, os
with open(os.environ["TWL_ALIASES_FILE"]) as f:
    d = json.load(f)
print(d.get(os.environ["TWL_HOST"], "unknown"))
' 2>/dev/null || echo "unknown"
}

classify_issues() {
  log "Phase 2: 既存 Issue の多段階分類 (--state all --limit 500)"

  local current_host
  current_host="$(hostname)"
  local current_alias
  current_alias="$(_resolve_host_alias "$current_host")"
  log "  current host: $current_host → alias: $current_alias"

  # Step 1: キーワード grep で候補 Issue を列挙
  local search_query="検出元 OR soap-copilot OR ipatho OR thinkpad OR 起源 OR observer"
  local candidates
  candidates=$(gh issue list --repo "$REPO" --state all --limit 500 \
    --search "$search_query" \
    --json number,title,labels 2>/dev/null || echo "[]")

  local candidate_numbers=()
  while IFS= read -r n; do
    [[ -n "$n" ]] && candidate_numbers+=("$n")
  done < <(echo "$candidates" | python3 -c '
import json, sys
items = json.load(sys.stdin)
for i in items:
    print(i["number"])
' 2>/dev/null || true)

  # Step 2 (本文確認): 候補 Issue の body を gh issue view --json body で取得し cross-repo 起源を確認
  local verified_numbers=()
  for n in "${candidate_numbers[@]+"${candidate_numbers[@]}"}"; do
    local body
    body=$(gh issue view "$n" --repo "$REPO" --json body -q '.body' 2>/dev/null || echo "")
    if echo "$body" | grep -qiE "検出元|soap-copilot|cross-repo|起票.*cross|observer.*wave|ipatho"; then
      verified_numbers+=("$n")
    fi
  done

  # Step 3: doobidoo memory hash 3c47c84a の cross-reference で既知 Issue を補完（重複排除）
  local all_targets=()
  for n in "${KNOWN_CROSS_ORIGIN[@]}"; do
    all_targets+=("$n")
  done
  for n in "${verified_numbers[@]+"${verified_numbers[@]}"}"; do
    local found=false
    for existing in "${all_targets[@]}"; do
      [[ "$existing" == "$n" ]] && found=true && break
    done
    [[ "$found" == "false" ]] && all_targets+=("$n")
  done

  log "  候補 Issue 総数: ${#all_targets[@]} 件"
  # stdout に Issue 番号のみを出力（log は stderr 済み）
  printf '%s\n' "${all_targets[@]+"${all_targets[@]}"}"
}

# ---------------------------------------------------------------------------
# Phase 3: ラベル付与（べき等）
# ---------------------------------------------------------------------------

assign_labels() {
  local issue_numbers=("$@")
  local assigned=0
  local skipped=0

  log "Phase 3: ラベル付与（べき等、${#issue_numbers[@]} 件対象）"

  local current_host
  current_host="$(hostname)"
  local host_alias
  host_alias="$(_resolve_host_alias "$current_host")"

  for num in "${issue_numbers[@]}"; do
    local existing_labels
    existing_labels=$(gh issue view "$num" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || echo "")

    local host_label="origin:host:${host_alias}"
    local repo_label="origin:repo:soap-copilot-mock"

    # host / repo それぞれ独立にべき等チェック
    local has_host_label=false
    local has_repo_label=false
    echo "$existing_labels" | grep -qF "origin:host:" && has_host_label=true
    echo "$existing_labels" | grep -qF "origin:repo:" && has_repo_label=true

    if [[ "$has_host_label" == "true" && "$has_repo_label" == "true" ]]; then
      [[ "$VERBOSE" == "true" ]] && log "  skip (already labeled): #$num"
      ((skipped++)) || true
    else
      if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "gh issue edit $num --repo $REPO --add-label <labels>"
      else
        # 未付与ラベルのみ --add-label で付与（べき等）
        if [[ "$has_host_label" == "false" && "$has_repo_label" == "false" ]]; then
          gh issue edit "$num" --repo "$REPO" --add-label "$host_label" --add-label "$repo_label"
          log "  labeled: #$num (+$host_label +$repo_label)"
        elif [[ "$has_host_label" == "false" ]]; then
          gh issue edit "$num" --repo "$REPO" --add-label "$host_label"
          log "  labeled: #$num (+$host_label)"
        else
          gh issue edit "$num" --repo "$REPO" --add-label "$repo_label"
          log "  labeled: #$num (+$repo_label)"
        fi
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
  local assigned_count="$1"
  local total="$2"
  local confirmed_nums=("${@:3}")

  echo ""
  echo "=== origin:* ラベル付与 完了 ==="
  echo "分類件数: $total 件 / 付与件数: $assigned_count 件"

  if [[ "$total" -gt 3 ]]; then
    echo "（3 件超のため差分を明示）"
    echo "対象 Issue 一覧:"
    for n in "${confirmed_nums[@]+"${confirmed_nums[@]}"}"; do
      echo "  #$n"
    done
  else
    echo "対象 Issue: ${confirmed_nums[*]+"${confirmed_nums[*]}"}"
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

  local issue_numbers=()
  while IFS= read -r n; do
    [[ -n "$n" ]] && issue_numbers+=("$n")
  done < <(classify_issues)

  local assigned_count=0
  if [[ "${#issue_numbers[@]}" -gt 0 ]]; then
    assigned_count=$(assign_labels "${issue_numbers[@]}")
  else
    log "対象 Issue なし"
  fi

  report_results "$assigned_count" "${#issue_numbers[@]}" "${issue_numbers[@]+"${issue_numbers[@]}"}"
}

main "$@"
