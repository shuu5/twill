---
type: composite
tools: [Agent, Bash, Skill, Task, Read]
effort: medium
maxTurns: 30
---
# fix 後の specialist 並列レビュー（chain-driven）

fix-phase で修正されたコードの差分に対して specialist 並列レビューを実行する。
fix が新たな問題を導入していないことを専門 specialist により検証する。

## 入力

- fix-phase による変更差分（`git diff HEAD~1`）

## 出力

- 検証結果（PASS / WARN / FAIL + findings）

## 実行ロジック（MUST）

### Step 1: fix 差分の取得

```bash
git diff HEAD~1 --name-only  # fix で変更されたファイル
git diff HEAD~1              # 差分内容
```

### Step 2: マニフェスト取得

```bash
SPECIALISTS=$(git diff HEAD~1 --name-only | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode post-fix-verify)
MANIFEST_FILE=$(mktemp /tmp/.specialist-manifest-post-fix-verify-XXXXXXXX.txt)
chmod 600 "$MANIFEST_FILE"
CONTEXT_ID=$(basename "$MANIFEST_FILE" .txt | sed 's/^\.specialist-manifest-//')
SPAWNED_FILE="/tmp/.specialist-spawned-${CONTEXT_ID}.txt"
echo "$SPECIALISTS" > "$MANIFEST_FILE"
trap 'rm -f "$MANIFEST_FILE" "$SPAWNED_FILE"' EXIT
```

### Step 3: specialist 並列 spawn

マニフェスト出力の全件を並列 Task spawn する。
手動でリストを構築してはならない（MUST NOT）。
マニフェストに含まれない specialist を追加してはならない（MUST NOT）。

マニフェスト出力が空（0行）の場合、specialist spawn をスキップし自動 PASS とする。

```
各 specialist について:
  Task(subagent_type="twl:<specialist-name>", prompt="fix 差分を入力として渡す")
```

### Step 4: 結果集約

全 specialist の出力を Python パーサーでパースし、findings を統合する。

```bash
PARSED=$(echo "$SPECIALIST_OUTPUT" | python3 -m twl.autopilot.parser)
rm -f "$MANIFEST_FILE" "$SPAWNED_FILE"
```

AI による自由形式の変換は禁止。パーサーの構造化データのみを使用する。

### Step 5: 結果判定

```
IF 新規 CRITICAL finding なし → PASS
IF 新規 WARNING finding あり → WARN（続行可）
IF 新規 CRITICAL finding あり → FAIL（再 fix 必要）
```

## チェックポイント（MUST）

`/twl:warning-fix` を Skill tool で自動実行。
