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
SPECIALISTS=$(git diff --name-only origin/main | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate)
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

### checkpoint 統合（MUST）

```bash
AC_VERIFY_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step ac-verify --field findings 2>/dev/null || echo "[]")
COMBINED_FINDINGS=$(jq -s 'add' <(echo "$FINDINGS") <(echo "$AC_VERIFY_FINDINGS"))
```

all-pass-check checkpoint も同形式で読み込む。ac-verify checkpoint 不在時は WARN を出して継続（autopilot 配下では異常ケース）。

### severity フィルタ判定（機械的のみ）

```
BLOCKING = COMBINED_FINDINGS WHERE severity == "CRITICAL" AND confidence >= 80
PASS  ⇔ BLOCKING == 0
REJECT ⇔ BLOCKING >= 1
```

### PASS / REJECT 時の状態遷移

PASS / REJECT 後の状態遷移ロジック（autopilot/Pilot 分岐、retry_count 管理、fix_instructions 記録、不変条件 C/E）の正典は `architecture/autopilot-invariants.md` および `commands/autopilot-state-write.md`。本 composite は judgement を出力するのみで、状態遷移の実装は呼び出し元 controller / state-write.sh に委譲する。

## チェックポイント（MUST）

チェーン完了。

