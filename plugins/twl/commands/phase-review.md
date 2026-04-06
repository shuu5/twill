# 並列 specialist レビュー（chain-driven）

pr-cycle chain のオーケストレーター。動的レビュアー構築と並列 specialist 実行を管理する。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 2 | phase-review（本コンポーネント） | composite |

## ドメインルール

### 動的レビュアー構築

**Step 1: マニフェストスクリプト実行**

```bash
SPECIALISTS=$(git diff --name-only origin/main | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode phase-review)

# hook 用一時ファイル作成
CONTEXT_ID="phase-review-$(git branch --show-current | tr '/' '-')"
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

全 specialist を Task spawn で並列実行する。逐次実行は行わない。

```
各 specialist について:
  Task(subagent_type="twl:<specialist-name>", prompt="...")
```

### 結果集約

全 specialist の出力を Python モジュールでパースし、findings を統合する。

```bash
PARSED=$(echo "$SPECIALIST_OUTPUT" | python3 -m twl.autopilot.parser)
```

AI による自由形式の変換は禁止。パーサーの構造化データのみを使用する。

### checkpoint 書き出し（MUST）

結果集約後、checkpoint.py で findings を永続化する。
次ステップ（fix-phase）は checkpoint の要約フィールドのみを参照し、specialist raw output を引き継がない。

```bash
# PARSED から status と findings を抽出して checkpoint に書き出す
STATUS=$(echo "$PARSED" | jq -r '.status')
FINDINGS=$(echo "$PARSED" | jq -c '.findings')
python3 -m twl.autopilot.checkpoint write --step phase-review --status "$STATUS" --findings "$FINDINGS"
```

## チェックポイント（MUST）

`/twl:scope-judge` を Skill tool で自動実行。

