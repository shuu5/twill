---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 10
---
# externalize-state（状態外部化）

SupervisorSession の現在状態を externalization-schema に従って外部ファイルへ書き出す atomic コマンド。su-compact から呼び出されるか、手動で直接実行する。

## 引数

- `--trigger <mode>`: 外部化のきっかけ（デフォルト: `manual`）
  - `auto_precompact`: PreCompact フックによる自動実行
  - `manual`: ユーザーによる手動実行
  - `wave_complete`: Wave 完了時の保存

## フロー（MUST）

### Step 0: スキーマ読み込み

`refs/externalization-schema.md` を Read して書き出しテンプレートを取得する。

### Step 1: 書き出し先の決定

引数の `--trigger` 値に基づいて書き出し先を決定する:

```bash
TRIGGER="${1:-manual}"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
mkdir -p "${AUTOPILOT_DIR}"

if [[ "$TRIGGER" == "wave_complete" ]]; then
  # session.json から current_wave を取得
  SESSION_FILE="${AUTOPILOT_DIR}/session.json"
  if [[ -f "$SESSION_FILE" ]]; then
    WAVE_NUM=$(python3 -c "import json,sys; d=json.load(open('$SESSION_FILE')); print(d.get('current_wave','unknown'))" 2>/dev/null || echo "unknown")
  else
    WAVE_NUM="unknown"
  fi
  OUTPUT_PATH="${AUTOPILOT_DIR}/wave-${WAVE_NUM}-summary.md"
  LIFECYCLE="persistent"
else
  OUTPUT_PATH="${AUTOPILOT_DIR}/working-memory.md"
  LIFECYCLE="temporary"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo ">>> externalize-state: trigger=${TRIGGER}, output=${OUTPUT_PATH}"
```

### Step 2: 外部化ファイルの書き出し

`trigger` の値に応じて externalization-schema のテンプレートを使用してファイルを書き出す。

**`trigger=wave_complete` の場合（wave-{N}-summary.md テンプレート）:**

```markdown
---
externalized_at: "<TIMESTAMP>"
trigger: wave_complete
wave_number: <WAVE_NUM>
lifecycle: persistent
---

## Wave <WAVE_NUM> サマリ

### 実装結果

| Issue | PR | 結果 | 介入 |
|---|---|---|---|

### 知見

（Long-term Memory に保存すべき教訓）

### 次 Wave への引き継ぎ

（Working Memory に復帰させるべき情報）
```

**その他のトリガー（working-memory.md テンプレート）:**

```markdown
---
externalized_at: "<TIMESTAMP>"
trigger: <TRIGGER>
lifecycle: temporary
---

## 現在のタスク

- [ ] タスクの説明

## 進捗

現在の作業: ...
次のステップ: ...

## 監視中の Controller

| Controller | Window | Status | 最終確認 |
|---|---|---|---|

## 重要なコンテキスト

（compaction で失われると困る sharp な情報）
```

SupervisorSession の現在状態を把握してテンプレートを埋める。

### Step 3: ExternalizationRecord の追記

`.autopilot/session.json` の `externalization_log` 配列にレコードを追記する。
`new_pitfall_hashes` と `pitfall_declaration` は Step 4 Exit Gate の宣言後に確定するため、
ここでは空リストと空文字列でプレースホルダーを書き込む:

```bash
SESSION_FILE="${AUTOPILOT_DIR}/session.json"
if [[ -f "$SESSION_FILE" ]]; then
  bash "${AUTOPILOT_DIR}/../plugins/twl/scripts/session-atomic-write.sh" \
    "$SESSION_FILE" \
    --arg ts "$TIMESTAMP" --arg trigger "$TRIGGER" --arg path "$OUTPUT_PATH" \
    '.externalization_log += [{"externalized_at": $ts, "trigger": $trigger, "output_path": $path, "new_pitfall_hashes": [], "pitfall_declaration": ""}]'
  echo "✓ ExternalizationRecord 追記完了"
else
  echo "⚠️ session.json が見つかりません（スキップ）"
fi
```

### Step 4: Exit Gate — 新規 pitfall 宣言（MUST）

このセッションで発生した新規 `observer-pitfall` / `observer-lesson` の doobidoo 保存状況を確認し、
`pitfall_declaration` を宣言して session.json に記録する。

**確認手順:**

1. doobidoo で直近保存された observer-pitfall を検索:
   ```
   mcp__doobidoo__memory_search(tags="observer-pitfall", limit=5)
   mcp__doobidoo__memory_search(tags="observer-lesson", limit=5)
   ```
2. 本セッションで新規保存したハッシュを特定する
3. `scripts/externalize-state-exit-gate.sh` を実行して宣言を記録:
   ```bash
   SESSION_FILE="${AUTOPILOT_DIR}/session.json"
   PITFALL_HASHES='["hash1","hash2"]'  # 0件の場合は '[]'
   PITFALL_DECL="2-items"              # 0件の場合は "none"
   bash "${AUTOPILOT_DIR}/../plugins/twl/scripts/session-atomic-write.sh" \
     "$SESSION_FILE" \
     --argjson hashes "$PITFALL_HASHES" --arg decl "$PITFALL_DECL" \
     'if (.externalization_log | length) > 0 then
        .externalization_log[-1].new_pitfall_hashes = $hashes |
        .externalization_log[-1].pitfall_declaration = $decl
      else . end'
   echo "✓ pitfall_declaration 記録完了"
   ```
4. Exit Gate チェックスクリプトで検証:
   ```bash
   bash "${AUTOPILOT_DIR}/../plugins/twl/scripts/externalize-state-exit-gate.sh" \
     "$(basename "$AUTOPILOT_DIR")" "$SESSION_FILE"
   # exit 0 → OK, exit 1 → WARN（宣言漏れ）, exit 2 → session.json 不在
   ```

**宣言ルール:**
- 新規 pitfall あり → `pitfall_declaration: "N-items"`, `new_pitfall_hashes: ["hash1", ...]`
- 新規 pitfall なし → `pitfall_declaration: "none"`, `new_pitfall_hashes: []`
- 未宣言 → exit gate が WARN を出力する（session.json 更新後もスクリプト確認が必要）

### Step 5: 完了報告

```
✓ externalize-state 完了: <OUTPUT_PATH>
```

## 禁止事項（MUST NOT）

- session.json が存在しない場合にエラーで終了してはならない（警告のみ）
- externalization-schema に定義されていないフィールドをフロントマターに追加してはならない
- 書き出し先ディレクトリが存在しない場合は作成してから書き出すこと

## 参照

- `refs/externalization-schema.md`: 外部化ファイルのスキーマ定義
