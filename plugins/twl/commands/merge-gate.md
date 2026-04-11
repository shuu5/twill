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

### 動的レビュアー構築

```bash
# origin/main が解決できない場合のフォールバック付き (Issue #198)
if ! SPECIALISTS=$(git diff --name-only origin/main 2>/dev/null | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate); then
  echo "WARN: origin/main not found, falling back to FETCH_HEAD" >&2
  git fetch origin main
  SPECIALISTS=$(git diff --name-only FETCH_HEAD | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate)
fi
CONTEXT_ID="merge-gate-$(git branch --show-current | tr '/' '-')"
echo "$SPECIALISTS" > /tmp/.specialist-manifest-${CONTEXT_ID}.txt
```

マニフェスト各行を Task spawn 対象とする（手動追加・削除は MUST NOT）。出力 0 行は自動 PASS。結果収集後 `/tmp/.specialist-{manifest,spawned}-${CONTEXT_ID}.txt` を削除。

### 並列 specialist 実行 → 結果集約

各 specialist を `Task(subagent_type="twl:<name>", prompt="PR diff を入力としてレビューを実行")` で並列起動。出力は ref-specialist-output-schema 準拠。

```bash
PARSED=$(echo "$OUTPUT" | python3 -m twl.autopilot.parser)
STATUS=$(echo "$PARSED" | jq -r '.status')
FINDINGS=$(echo "$PARSED" | jq -c '.findings')
python3 -m twl.autopilot.checkpoint write --step merge-gate --status "$STATUS" --findings "$FINDINGS"
```

AI による自由形式変換は禁止。

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

