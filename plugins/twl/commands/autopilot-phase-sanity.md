---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 30
---
# Phase 完了サニティチェック (atomic)

PHASE_COMPLETE 受信後、各 done Issue の GitHub Issue close 状態を Pilot 側で軽量 verify する。
co-autopilot Step 4 から呼び出される layered defense の最終層（Issue #4/#5 の安全網）。

PR diff・Issue body・テスト結果は **読まない**（Pilot context budget 維持）。
Issue close 状態のみを `gh issue view`/`gh issue close` で確認する。

## 入力

| 変数 | 説明 |
|------|------|
| `$PHASE_RESULTS_JSON` | orchestrator から返された PHASE_COMPLETE JSON のパス |
| `$P` | 現在の Phase 番号 |
| `$SESSION_STATE_FILE` | session.json のパス |

`$PHASE_RESULTS_JSON` のスキーマ:

```json
{
  "phase": <int>,
  "done": [<issue_number>, ...],
  "failed": [<issue_number>, ...],
  "skipped": [<issue_number>, ...]
}
```

## 処理ロジック (MUST)

各 done Issue について以下を順に実行する。

### Step 1: 入力読込

```bash
DONE_LIST=$(jq -r '.done[]' "$PHASE_RESULTS_JSON" 2>/dev/null || true)
FAILED_LIST=$(jq -r '.failed[]' "$PHASE_RESULTS_JSON" 2>/dev/null || true)
SKIPPED_LIST=$(jq -r '.skipped[]' "$PHASE_RESULTS_JSON" 2>/dev/null || true)

declare -a NEW_DONE=()
declare -a NEW_FAILED=()
declare -a AUTO_CLOSE_FALLBACK=()
declare -a SANITY_WARNINGS=()

# 既存 failed をそのまま継承
while IFS= read -r f; do [ -n "$f" ] && NEW_FAILED+=("$f"); done <<< "$FAILED_LIST"
```

### Step 2: 各 done Issue を verify

```bash
while IFS= read -r issue; do
  [ -z "$issue" ] && continue

  # 1. GitHub 状態取得
  state=$(gh issue view "$issue" --json state -q .state 2>/dev/null || echo "")

  case "$state" in
    CLOSED)
      # 2a. 正常: そのまま done
      NEW_DONE+=("$issue")
      ;;
    OPEN)
      # 2b. 警告 → close 試行 → 再確認
      echo "WARN: Issue #${issue} is OPEN after PHASE_COMPLETE; attempting auto-close" >&2
      gh issue close "$issue" --comment "auto-close-fallback by autopilot-phase-sanity (Phase ${P})" >/dev/null 2>&1 || true
      recheck=$(gh issue view "$issue" --json state -q .state 2>/dev/null || echo "")
      if [ "$recheck" = "CLOSED" ]; then
        NEW_DONE+=("$issue")
        AUTO_CLOSE_FALLBACK+=("$issue")
        echo "INFO: Issue #${issue} auto-closed successfully" >&2
      else
        NEW_FAILED+=("$issue")
        echo "CRITICAL: Issue #${issue} could not be closed; moved from done to failed" >&2
      fi
      ;;
    "")
      # 2c. 取得失敗: warning + done 維持
      SANITY_WARNINGS+=("issue=${issue} reason=state-fetch-failed")
      NEW_DONE+=("$issue")
      echo "WARN: Issue #${issue} state fetch failed; keeping in done" >&2
      ;;
    *)
      SANITY_WARNINGS+=("issue=${issue} reason=unknown-state:${state}")
      NEW_DONE+=("$issue")
      ;;
  esac
done <<< "$DONE_LIST"
```

### Step 3: 修正済み results JSON を出力

`$PHASE_RESULTS_JSON` を以下のスキーマで上書きする:

```bash
jq -n \
  --argjson phase "$P" \
  --argjson done "$(printf '%s\n' "${NEW_DONE[@]}" | jq -R . | jq -s 'map(tonumber)')" \
  --argjson failed "$(printf '%s\n' "${NEW_FAILED[@]}" | jq -R . | jq -s 'map(select(length>0) | tonumber)')" \
  --argjson skipped "$(printf '%s\n' "$SKIPPED_LIST" | jq -R . | jq -s 'map(select(length>0) | tonumber)')" \
  --argjson fallback "$(printf '%s\n' "${AUTO_CLOSE_FALLBACK[@]}" | jq -R . | jq -s 'map(select(length>0) | tonumber)')" \
  --argjson warnings "$(printf '%s\n' "${SANITY_WARNINGS[@]}" | jq -R . | jq -s 'map(select(length>0))')" \
  '{phase:$phase, done:$done, failed:$failed, skipped:$skipped, auto_close_fallback:$fallback, sanity_warnings:$warnings}' \
  > "${PHASE_RESULTS_JSON}.tmp" && mv "${PHASE_RESULTS_JSON}.tmp" "$PHASE_RESULTS_JSON"
```

### Step 4: session.json への記録（任意）

`auto_close_fallback` または `sanity_warnings` が非空の場合、session.json の `.sanity_log` 配列に Phase エントリを追加する:

```bash
if [ "${#AUTO_CLOSE_FALLBACK[@]}" -gt 0 ] || [ "${#SANITY_WARNINGS[@]}" -gt 0 ]; then
  jq --argjson phase "$P" \
     --argjson fb "$(printf '%s\n' "${AUTO_CLOSE_FALLBACK[@]}" | jq -R . | jq -s 'map(select(length>0) | tonumber)')" \
     --argjson wn "$(printf '%s\n' "${SANITY_WARNINGS[@]}" | jq -R . | jq -s 'map(select(length>0))')" \
     '.sanity_log = ((.sanity_log // []) + [{phase:$phase, auto_close_fallback:$fb, sanity_warnings:$wn}])' \
     "$SESSION_STATE_FILE" > "${SESSION_STATE_FILE}.tmp" \
     && mv "${SESSION_STATE_FILE}.tmp" "$SESSION_STATE_FILE"
fi
```

## 出力

修正済み `$PHASE_RESULTS_JSON`:

```json
{
  "phase": <int>,
  "done": [<verified closed issues>],
  "failed": [<...originally failed... + close失敗 issues>],
  "skipped": [...],
  "auto_close_fallback": [<auto-close で救済された issue リスト>],
  "sanity_warnings": [<取得失敗等のリスト>]
}
```

呼び出し元（co-autopilot SKILL.md Step 4）はこの修正済み results を後続の autopilot-phase-postprocess.md へ引き渡す。

## 禁止事項 (MUST NOT)

- PR diff を読んではならない（Pilot context budget 維持）
- Issue body を読んではならない
- テスト結果を再実行してはならない
- `gh issue view <issue>` で `state` 以外のフィールドを取得してはならない
- skipped リストを変更してはならない（done と failed のみ操作対象）
