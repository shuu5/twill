# セッション JSONL 事後分析

セッション JSONL から監査サマリーを抽出し、ワークフロー信頼性問題を 5 カテゴリで自動検出する。
co-autopilot Step 5.5 から呼び出されるほか、ユーザーが直接実行可能。

## 使用方法

```
/dev:session-audit          # 直近5件
/dev:session-audit 10       # 直近10件
/dev:session-audit --since 3d  # 直近3日間
```

## 引数解析（MUST）

```
IF 引数が数値 → COUNT=<数値>, MODE=count
ELIF 引数が --since <PERIOD> → SINCE=<PERIOD>, MODE=since
ELSE → COUNT=5, MODE=count（デフォルト）
```

PERIOD 形式: `Nd`（N日間）、`Nh`（N時間）

## 実行ロジック（MUST）

### Step 1: セッション JSONL 特定

```bash
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SAFE_NAME=$(echo "$PROJECT_DIR" | sed 's|^/||; s|/|-|g')
SESSION_DIR="$HOME/.claude/projects/-${SAFE_NAME}"
```

worktree の場合: そのまま使用。ファイル未検出時は bare repo の main worktree パスでフォールバック検索。

MODE に応じてファイルリストを取得:

```bash
# count モード
ls -t "$SESSION_DIR"/*.jsonl | head -n "$COUNT"

# since モード
find "$SESSION_DIR" -name "*.jsonl" -mtime -"$DAYS" -o -mmin -"$MINUTES"
```

### Step 2: 監査サマリー抽出

```bash
bash "$SCRIPTS_ROOT/session-audit.sh" "$JSONL_PATH"
```

全セッションのサマリーを 1 つのファイルに結合。

### Step 3: Haiku Agent による 5 カテゴリ分析

Agent tool（model: haiku）を使用して分析:

| # | カテゴリ | シグナル |
|---|---------|---------|
| 1 | script-fragility | Bash ERROR → AI が別コマンドで回避 → 成功 |
| 2 | silent-failure | Bash 成功だが出力が期待と違い AI が補償行動 |
| 3 | ai-compensation | Skill 実行中にスキル定義外の推論・ツール使用 |
| 4 | retry-loop | 同一ツール+類似入力が 3 回以上連続 |
| 5 | twl-inline-logic | Skill 実行中に長い Bash パイプラインが出現 |

各検出を JSON 形式で出力（category, confidence, description, evidence, suggestion）。

### Step 4: confidence 閾値フィルタリング

confidence >= 70 のみ抽出。< 70 はログ出力のみ。

### Step 5: 重複排除チェック

```bash
PATTERN_CONTENT="<category>:<description の正規化>"
PATTERN_HASH=$(echo -n "$PATTERN_CONTENT" | sha256sum | cut -c1-8)
DEDUP_KEY="<category>:${PATTERN_HASH}"
gh issue list --label "self-improve" --search "$DEDUP_KEY" --state open --json number,title
```

### Step 6: self-improve Issue 起票

confidence >= 70 かつ重複なしの検出について起票。

## 出力形式（MUST）

```
## /dev:session-audit 結果

分析対象: N セッション
検出数: M 件（confidence >= 70: X 件）

| # | カテゴリ | confidence | 説明 | アクション |
|---|---------|-----------|------|----------|
| 1 | script-fragility | 85 | ... | Issue #N 起票 |
| 2 | retry-loop | 72 | ... | Issue #N 起票 |
| 3 | silent-failure | 45 | ... | 低confidence（スキップ） |
```

## 禁止事項（MUST NOT）

- confidence < 70 の検出で Issue 起票してはならない
- 重複排除チェックをスキップしてはならない
- Haiku 以外のモデルで分析してはならない（コスト効率のため）
