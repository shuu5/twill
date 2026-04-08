---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 30
---
# Pilot Pre-merge Check (atomic)

PR merge 直前に Pilot が呼び出す軽量 verify atomic。
autopilot-phase-sanity (Issue close 状態のみ verify) と直列 / 直交する責務。

## autopilot-phase-sanity との責務分離 (MUST)

| atomic | 責務 | 入力 | 読み込み制限 |
|---|---|---|---|
| autopilot-phase-sanity (既存) | Issue close 状態 verify | `gh issue view --json state` | state のみ |
| **autopilot-pilot-precheck (本 atomic)** | PR diff stat 削除確認 + AC spot-check + comment 確認 | PR diff stat + AC checklist + Issue comments | stat / AC / comments のみ。PR diff 全文は読まない |

Step 4.5 では sanity → **precheck** の順で直列実行される。

## 入力

| 変数 | 説明 |
|------|------|
| `$PHASE_RESULTS_JSON` | orchestrator から返された PHASE_COMPLETE JSON のパス |
| `$P` | 現在の Phase 番号 |
| `$SESSION_STATE_FILE` | session.json のパス |

## opt-out

```bash
if [ "${PILOT_ACTIVE_REVIEW_DISABLE:-0}" = "1" ]; then
  echo "WARN: PILOT_ACTIVE_REVIEW_DISABLE=1 — autopilot-pilot-precheck をスキップ" >&2
  exit 0
fi
```

## 処理ロジック (MUST)

### Step 1: done Issue リスト取得

```bash
DONE_LIST=$(jq -r '.done[]' "$PHASE_RESULTS_JSON" 2>/dev/null || true)
VERIFY_COUNT=0
MAX_VERIFY=3

declare -a PRECHECK_WARNINGS=()
declare -a PRECHECK_FAILS=()
```

### Step 2: 各 done Issue を verify (最大 3 件)

```bash
while IFS= read -r issue; do
  [ -z "$issue" ] && continue
  VERIFY_COUNT=$((VERIFY_COUNT + 1))

  if [ "$VERIFY_COUNT" -gt "$MAX_VERIFY" ]; then
    PRECHECK_WARNINGS+=("issue=${issue} reason=skipped-over-max-verify")
    continue
  fi

  # 2.1 PR 番号取得
  PR=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field pr_number 2>/dev/null || echo "")
  [ -z "$PR" ] && continue

  # 2.2 PR diff stat で削除確認
  STAT=$(gh pr diff "$PR" --stat 2>/dev/null || echo "")
  DELETIONS=$(echo "$STAT" | tail -1 | grep -oP '\d+(?= deletion)' || echo "0")
  DELETED_FILES=$(echo "$STAT" | grep -c '^\s.*|.*-' || echo "0")

  DELETE_LINE_THRESHOLD=${PILOT_PRECHECK_DELETE_LINES:-100}
  DELETE_FILE_THRESHOLD=${PILOT_PRECHECK_DELETE_FILES:-5}

  if [ "$DELETIONS" -gt "$DELETE_LINE_THRESHOLD" ] || [ "$DELETED_FILES" -gt "$DELETE_FILE_THRESHOLD" ]; then
    PRECHECK_WARNINGS+=("issue=${issue} pr=${PR} reason=high-deletion deletions=${DELETIONS} deleted_files=${DELETED_FILES}")
    echo "WARN: PR #${PR} (Issue #${issue}): ${DELETIONS} deletions, ${DELETED_FILES} deleted files — silent deletion の可能性" >&2
  fi

  # 2.3 AC spot-check: Issue body から AC リスト抽出
  ISSUE_BODY=$(gh issue view "$issue" --json body -q .body 2>/dev/null || echo "")
  AC_KEYWORDS=("Issue にコメント" "ラベル追加" "README 更新" "architecture/" "docs/")
  AC_MATCHES=()

  for kw in "${AC_KEYWORDS[@]}"; do
    if echo "$ISSUE_BODY" | grep -qF "$kw"; then
      AC_MATCHES+=("$kw")
    fi
  done

  # 2.4 検出した AC について Issue comments で痕跡確認 (最大 3 AC)
  AC_CHECK_COUNT=0
  for ac in "${AC_MATCHES[@]}"; do
    AC_CHECK_COUNT=$((AC_CHECK_COUNT + 1))
    [ "$AC_CHECK_COUNT" -gt 3 ] && break

    COMMENTS=$(gh issue view "$issue" --json comments -q '.comments[].body' 2>/dev/null || echo "")
    if [ -z "$COMMENTS" ] && [[ "$ac" == "Issue にコメント" ]]; then
      PRECHECK_FAILS+=("issue=${issue} reason=ac-unmet ac='${ac}' detail=no-comments-found")
      echo "FAIL: Issue #${issue}: AC「${ac}」の痕跡が Issue comments に見つからない" >&2
    fi
  done

done <<< "$DONE_LIST"
```

### Step 3: 結果記録

```bash
if [ "${#PRECHECK_WARNINGS[@]}" -gt 0 ] || [ "${#PRECHECK_FAILS[@]}" -gt 0 ]; then
  jq --argjson phase "$P" \
     --argjson warnings "$(printf '%s\n' "${PRECHECK_WARNINGS[@]}" | jq -R . | jq -s 'map(select(length>0))')" \
     --argjson fails "$(printf '%s\n' "${PRECHECK_FAILS[@]}" | jq -R . | jq -s 'map(select(length>0))')" \
     '.precheck_log = ((.precheck_log // []) + [{phase:$phase, warnings:$warnings, fails:$fails}])' \
     "$SESSION_STATE_FILE" > "${SESSION_STATE_FILE}.tmp" \
     && mv "${SESSION_STATE_FILE}.tmp" "$SESSION_STATE_FILE"
fi
```

### Step 4: precheck_log 出力

WARN/FAIL 情報を stderr に出力。WARN は autopilot-pilot-rebase への引き渡しを誘発する。FAIL は autopilot-multi-source-verdict への引き渡しを誘発する。

## 出力

- WARN/FAIL 情報は `$SESSION_STATE_FILE.precheck_log` セクションに記録
- stderr に WARN/FAIL を出力（呼び出し元が後続 atomic の実行を判断）

## 禁止事項 (MUST NOT)

- PR diff 全文を読んではならない (stat のみ)
- テスト再実行してはならない
- `$PHASE_RESULTS_JSON` を直接書き換えてはならない
- `gh issue view --json state` で state を取得してはならない (autopilot-phase-sanity の責務)
- Phase あたり 4 件以上の done Issue がある場合は最初の 3 件のみ verify し、残りは sanity_warnings に記録
