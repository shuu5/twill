# マージ判定（chain-driven）

## Context (auto-injected)
- Branch: !`git branch --show-current`
- Issue: !`source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo ""`
- PR: !`gh pr view --json number -q '.number' 2>/dev/null || echo "none"`

PR の最終判定を行う。動的レビュアー構築 → 並列 specialist 実行 → 結果集約 → PASS/REJECT。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 8 | merge-gate（本コンポーネント） | composite |

## ドメインルール

### 動的レビュアー構築

**Step 1: マニフェストスクリプト実行**

```bash
SPECIALISTS=$(git diff --name-only origin/main | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate)

# hook 用一時ファイル作成
CONTEXT_ID="merge-gate-$(git branch --show-current | tr '/' '-')"
echo "$SPECIALISTS" > /tmp/.specialist-manifest-${CONTEXT_ID}.txt
```

**Step 2: マニフェスト出力の全件を並列 Task spawn**

マニフェストの各行に対して Task spawn を発行する。
手動でリストを構築してはならない（MUST NOT）。
マニフェストに含まれない specialist を追加してはならない（MUST NOT）。

マニフェスト出力が空（0行）の場合、specialist spawn をスキップし自動 PASS とする。

**Step 3: 結果収集後に一時ファイル削除**

```bash
rm -f /tmp/.specialist-manifest-${CONTEXT_ID}.txt /tmp/.specialist-spawned-${CONTEXT_ID}.txt
```

### 並列 specialist 実行

全 specialist を Task spawn で並列実行する。

```
各 specialist について:
  Task(subagent_type="twl:<specialist-name>", prompt="PR diff を入力としてレビューを実行")
```

各 specialist は共通出力スキーマ（ref-specialist-output-schema）に準拠した結果を返す。

### 結果集約

specialist 出力を Python モジュールでパースし findings を統合する。

```bash
PARSED=$(echo "$OUTPUT" | python3 -m twl.autopilot.parser)
```

**AI による自由形式の変換は禁止**。パーサーの構造化データのみを使用する。

### checkpoint 書き出し（MUST）

結果集約後、checkpoint.py で findings を永続化する。

```bash
STATUS=$(echo "$PARSED" | jq -r '.status')
FINDINGS=$(echo "$PARSED" | jq -c '.findings')
python3 -m twl.autopilot.checkpoint write --step merge-gate --status "$STATUS" --findings "$FINDINGS"
```

### all-pass-check checkpoint 読み込み

all-pass-check の checkpoint が存在する場合、`status` フィールドで事前判定を確認する。

```bash
ALL_PASS_STATUS=$(python3 -m twl.autopilot.checkpoint read --step all-pass-check --field status 2>/dev/null || echo "")
```

### severity フィルタ判定

```
BLOCKING = findings WHERE severity == "CRITICAL" AND confidence >= 80
```

| 条件 | 判定 |
|------|------|
| BLOCKING が 0 件 | **PASS** |
| BLOCKING が 1 件以上 | **REJECT** |

AI 推論による判定は禁止。上記の機械的フィルタのみで判定する。

### PASS 時の状態遷移

autopilot 状態を state-read で確認し、フローを分岐する（不変条件 C）。

- **autopilot 時（Worker 実行）**: status が `merge-ready` でなければ `status=merge-ready` を state write して停止。既に `merge-ready` なら再入検出としてスキップ。
- **非 autopilot 時（Pilot 実行）**: `ISSUE`, `PR_NUMBER`, `BRANCH` 環境変数を設定して `python3 -m twl.autopilot.mergegate` でマージを実行。

### REJECT 時の状態遷移（1回目、retry_count=0）

issue-{N}.json を `failed` → `running` に遷移（retry_count は state-write.sh が自動インクリメント）。`fix_instructions` に BLOCKING_FINDINGS を記録。Worker が fix-phase を実行する。

### REJECT 時の状態遷移（2回目、retry_count>=1 — 不変条件 E）

issue-{N}.json を `failed`（確定）に遷移。Pilot に手動介入を要求する。

### 設計方針

動的レビュアー構築による単一パス設計のため、旧プラグインのパス分岐・フラグ分岐・マーカーファイル管理は不要。
状態管理は issue-{N}.json と state-write.sh に一元化されている。

## チェックポイント（MUST）

チェーン完了。

