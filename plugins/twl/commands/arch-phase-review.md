---
type: composite
tools: [Bash, Skill, Read]
effort: medium
maxTurns: 20
---
# アーキテクチャ docs 並列 specialist レビュー（arch-phase-review）

architecture docs 専用の並列 specialist レビュー。arch-review chain のオーケストレーター。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 1 | arch-phase-review（本コンポーネント） | composite |

## ドメインルール

### 動的レビュアー構築

```bash
# origin/main が解決できない場合のフォールバック付き (Issue #198)
if ! SPECIALISTS=$(git diff --name-only origin/main 2>/dev/null | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode arch-review); then
  echo "WARN: origin/main not found, falling back to FETCH_HEAD" >&2
  git fetch origin main
  SPECIALISTS=$(git diff --name-only FETCH_HEAD | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode arch-review)
fi

# hook 用一時ファイル作成
CONTEXT_ID="arch-phase-review-$(git branch --show-current | tr '/' '-')"
echo "$SPECIALISTS" > /tmp/.specialist-manifest-${CONTEXT_ID}.txt
```

specialist 選択ルール（arch-review モード）:
- **常時必須**: worker-arch-doc-reviewer（architecture docs 変更は常に対象）
- **常時必須**: worker-architecture（architecture/ 配下変更は常に対象）
- **条件付き**: worker-structure + worker-principles（deps.yaml 変更あり）

マニフェスト出力が空（0行）の場合は自動 PASS。

### 並列 specialist 実行

マニフェストの各行に対して Task spawn を発行する。
手動でリストを構築してはならない（MUST NOT）。
マニフェストに含まれない specialist を追加してはならない（MUST NOT）。

```
各 specialist について:
  Task(subagent_type="twl:<specialist-name>", prompt="PR diff を入力として architecture docs のレビューを実施してください")
```

### 結果収集後に一時ファイル削除

```bash
rm -f /tmp/.specialist-manifest-${CONTEXT_ID}.txt /tmp/.specialist-spawned-${CONTEXT_ID}.txt
```

### 結果集約

全 specialist の出力を Python モジュールでパースし、findings を統合する。

```bash
PARSED=$(echo "$SPECIALIST_OUTPUT" | python3 -m twl.autopilot.parser)
```

AI による自由形式の変換は禁止。パーサーの構造化データのみを使用する。

### checkpoint 書き出し（MUST）

```bash
STATUS=$(echo "$PARSED" | jq -r '.status')
FINDINGS=$(echo "$PARSED" | jq -c '.findings')
python3 -m twl.autopilot.checkpoint write --step arch-phase-review --status "$STATUS" --findings "$FINDINGS"
```

## チェックポイント（MUST）

`/twl:arch-fix-phase` を続けて実行。
