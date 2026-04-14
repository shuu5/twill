# マージ判定（chain-driven）

## Context (auto-injected)
- Branch: !`git branch --show-current`
- Issue: !`source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo ""`
- PR: !`gh pr view --json number -q '.number' 2>/dev/null || echo "none"`

PR の最終判定を行う。動的レビュアー構築 → 並列 specialist 実行 → 結果集約 → PASS/REJECT。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

chain Step 8（composite）。chain ライフサイクルは deps.yaml を参照。

## ドメインルール

### PR 存在確認（MUST — 最初に実行）

merge-gate は PR が存在しない状態で実行してはならない（Issue #649）。動的レビュアー構築より先に実行すること。

```bash
PR_NUM=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
if [[ -z "$PR_NUM" || "$PR_NUM" == "none" ]]; then
  echo "REJECT: PR が存在しません。PR を作成してから merge-gate を実行してください" >&2
  python3 -m twl.autopilot.checkpoint write \
    --step merge-gate \
    --status REJECT \
    --findings '[{"severity":"CRITICAL","category":"process","message":"PR が存在しない状態で merge-gate が実行されました。PR を作成してから再実行してください","confidence":100}]'
  exit 1
fi
```

PR が存在しない場合、merge-gate は即座に REJECT を返し以降の処理を行わない。
Supervisor / Pilot が PR を作成（`intervene-auto --pattern pr-create`）してから merge-gate を再実行すること。

### 動的レビュアー構築

```bash
# origin/main が解決できない場合のフォールバック付き (Issue #198)
if ! SPECIALISTS=$(git diff --name-only origin/main 2>/dev/null | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate); then
  echo "WARN: origin/main not found, falling back to FETCH_HEAD" >&2
  git fetch origin main
  SPECIALISTS=$(git diff --name-only FETCH_HEAD | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate)
fi
MANIFEST_FILE=$(mktemp /tmp/.specialist-manifest-merge-gate-XXXXXXXX.txt)
chmod 600 "$MANIFEST_FILE"
CONTEXT_ID=$(basename "$MANIFEST_FILE" .txt | sed 's/^\.specialist-manifest-//')
SPAWNED_FILE="/tmp/.specialist-spawned-${CONTEXT_ID}.txt"
echo "$SPECIALISTS" > "$MANIFEST_FILE"
trap 'rm -f "$MANIFEST_FILE" "$SPAWNED_FILE"' EXIT
```

マニフェスト各行を Task spawn 対象とする（手動追加・削除は MUST NOT）。出力 0 行は自動 PASS。結果収集後 `rm -f "$MANIFEST_FILE"` 等で削除（trap でも可）。

### 並列 specialist 実行（MUST: 全 specialist 一括 spawn）

マニフェストファイルを読み、**全行の specialist を 1 回のメッセージで同時に Task spawn すること**。
部分的な spawn は禁止。spawn 漏れは merge 判定の信頼性を毀損する。

```bash
# マニフェスト読み込み
mapfile -t SPECIALIST_LIST < <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$')
echo "spawn 対象 specialist (${#SPECIALIST_LIST[@]} 件):"
printf '  - %s\n' "${SPECIALIST_LIST[@]}"
```

上記で出力された全 specialist を以下の形式で **1 回のメッセージ内に全て並列で** Task spawn する:

```
Task(subagent_type="twl:<name>", prompt="PR diff を入力としてレビューを実行")
```

出力は ref-specialist-output-schema 準拠。

### spawn 完了確認（MUST: 結果集約の前提条件）

全 specialist の Task が完了した後、結果集約に進む **前に** 以下を実行:

```bash
if [[ -f "$MANIFEST_FILE" ]]; then
  MISSING=$(comm -23 \
    <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$' | sed 's|^twl:twl:||' | sort -u) \
    <(sort -u "$SPAWNED_FILE" 2>/dev/null || true))
  if [[ -n "$MISSING" ]]; then
    echo "ERROR: 以下の specialist が未 spawn:"
    echo "$MISSING"
    echo "未 spawn の specialist を追加 spawn してから結果集約に進むこと"
    exit 1
  fi
  echo "✓ 全 specialist spawn 完了確認済み"
fi
```

このチェックが ERROR を返した場合、**未 spawn の specialist を追加 spawn** してから再度チェックを実行する。PASS するまで結果集約に進んではならない。

### 結果集約

```bash
PARSED=$(echo "$OUTPUT" | python3 -m twl.autopilot.parser)
STATUS=$(echo "$PARSED" | jq -r '.status')
FINDINGS=$(echo "$PARSED" | jq -c '.findings')
python3 -m twl.autopilot.checkpoint write --step merge-gate --status "$STATUS" --findings "$FINDINGS"
```

AI による自由形式変換は禁止。

### PR コメント投稿（specialist findings 永続化）

checkpoint 書き込み後、specialist findings を PR コメントとして投稿する。
findings が 0 件でも投稿（証跡として「No findings」を記録）。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-comment-findings
```

### Cross-PR AC 検証（retroactive DeltaSpec 対応）

```bash
ISSUE_NUM=$(source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo "")
IMPL_PR=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE_NUM" --field implementation_pr 2>/dev/null || echo "")
if [[ -n "$IMPL_PR" && "$IMPL_PR" != "null" ]]; then
  MERGE_COMMIT=$(gh pr view "$IMPL_PR" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null || echo "")
  if [[ -n "$MERGE_COMMIT" ]]; then
    echo "ℹ️ Cross-PR AC 検証: implementation_pr=#${IMPL_PR} (merge commit: ${MERGE_COMMIT})"
    python3 -m twl.autopilot.checkpoint write --step merge-gate --extra "verified_via_pr=$IMPL_PR" --extra "verified_via_commit=$MERGE_COMMIT" 2>/dev/null || true
  else
    echo "⚠️ WARN: implementation_pr=#${IMPL_PR} のマージコミットを取得できませんでした"
  fi
fi
```

`implementation_pr` が設定されている場合、AC 検証の証跡は本 PR diff ではなく参照 PR のマージコミットを根拠とする。merge-gate レポートに `verified_via_pr` フィールドを記録する。

### checkpoint 統合（MUST）

```bash
AC_VERIFY_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step ac-verify --field findings 2>/dev/null || echo "[]")
PHASE_REVIEW_STATUS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field status 2>/dev/null || echo "MISSING")
PHASE_REVIEW_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field findings 2>/dev/null || echo "[]")
COMBINED_FINDINGS=$(jq -s 'add' <(echo "$FINDINGS") <(echo "$AC_VERIFY_FINDINGS") <(echo "$PHASE_REVIEW_FINDINGS"))
```

all-pass-check checkpoint も同形式で読み込む。ac-verify checkpoint 不在時は WARN を出して継続（autopilot 配下では異常ケース）。

### phase-review checkpoint 必須チェック（MUST）

phase-review checkpoint は merge-gate の必須ゲートである（defense-in-depth、Issue #439）。

```bash
ISSUE_NUM=$(source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo "")
ISSUE_LABELS=$(gh issue view "$ISSUE_NUM" --json labels -q '[.labels[].name]' 2>/dev/null || echo "[]")
SKIP_PHASE_REVIEW=false
for label in $(echo "$ISSUE_LABELS" | jq -r '.[]'); do
  [[ "$label" == "scope/direct" || "$label" == "quick" ]] && SKIP_PHASE_REVIEW=true && break
done
```

- `SKIP_PHASE_REVIEW=false` かつ `PHASE_REVIEW_STATUS == "MISSING"` の場合:
  - `--force` フラグなし → **REJECT**: 「phase-review checkpoint が不在です。specialist review を実行してください」
  - `--force` フラグあり → **WARNING** ログ記録して継続: 「WARNING: phase-review checkpoint が不在です（--force により続行）」
- `SKIP_PHASE_REVIEW=true` の場合: phase-review チェックをスキップ（`scope/direct` / `quick` ラベル付き Issue は軽微変更のため除外）

### severity フィルタ判定（機械的のみ）

```
BLOCKING = COMBINED_FINDINGS WHERE severity == "CRITICAL" AND confidence >= 80
PASS  ⇔ BLOCKING == 0
REJECT ⇔ BLOCKING >= 1
```

phase-review の CRITICAL findings (confidence >= 80) も COMBINED_FINDINGS に含まれるため、自動統合される。

### PASS / REJECT 時の状態遷移

PASS / REJECT 後の状態遷移ロジック（autopilot/Pilot 分岐、retry_count 管理、fix_instructions 記録、不変条件 C/E）の正典は `plugins/twl/architecture/domain/contexts/autopilot.md` および `cli/twl/src/twl/autopilot/state.py`。本 composite は judgement を出力するのみで、状態遷移の実装は呼び出し元 controller / state.py に委譲する。

## チェックポイント（MUST）

チェーン完了。

