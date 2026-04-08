---
name: twl:self-improve-review
description: セッション中のBashエラーをレビューし、問題をIssue化候補として構造化
type: atomic
tools: [AskUserQuestion, Bash, Skill, Read]
effort: low
maxTurns: 10
---

# self-improve-review

セッション中に記録された Bash エラーをレビューし、ユーザー選択に基づいて問題を構造化する atomic コマンド。

## フロー制御（MUST）

### Step 1: エラーログ読み込み

```bash
ERRORS_FILE=".self-improve/errors.jsonl"
```

- ファイルが存在しないまたは空 → 「エラーログなし。記録されたBashエラーはありません。」と表示して正常終了
- 存在する場合 → Step 2 へ

### Step 2: エラー集計

errors.jsonl を読み込み、以下の軸でグループ化:

1. **command 別**（先頭50文字で正規化）
2. **exit_code 別**
3. **頻度順**（降順）

### Step 3: サマリーテーブル表示

マークダウンテーブル形式で表示:

```markdown
## Bash エラーサマリー

| # | コマンド（先頭50文字） | exit_code | 回数 | 最終発生 |
|---|----------------------|-----------|------|---------|
| 1 | npm test             | 1         | 5    | 14:32   |
| 2 | twl check           | 1         | 3    | 14:15   |
| 3 | git push             | 128       | 1    | 13:50   |

合計: N 件のエラー（M グループ）
```

### Step 4: ユーザー選択

AskUserQuestion で選択肢を提示:

**質問**: 「どのエラーを調査しますか？」

**選択肢**:
- `[A] #N を調査` — 特定のエラーグループを選択（番号指定）
- `[B] 全て調査` — 全エラーグループを構造化
- `[C] スキップ` — 何もせず終了
- `[D] ログクリア` — errors.jsonl を削除して終了

### Step 5: 問題構造化（A または B 選択時）

選択されたエラーグループについて:

1. 該当するエラーの全レコードを読み込み
2. 会話コンテキスト（直近のやり取り）を参照し、エラーの背景を推測
3. 以下の形式で構造化:

```markdown
## 問題: <問題タイトル>

### 概要
<1-2文で問題を要約>

### エラー証跡
- コマンド: `<command>`
- exit_code: <N>
- 発生回数: <N>
- stderr抜粋: `<snippet>`

### 推定原因
<会話コンテキストから推定される原因>

### 影響範囲
<影響を受けるファイル・機能>

### 推奨アクション
<修正提案>
```

### Step 6: explore-summary.md 出力

構造化結果を `.controller-issue/explore-summary.md` に書き出し。

```bash
mkdir -p .controller-issue
```

**出力形式**（co-issue Phase 1 互換）:

```markdown
# Explore Summary

source: self-improve-review
generated_at: <ISO8601>

## 問題一覧

### 1. <問題タイトル>
<Step 5 の構造化内容>

---

### 2. <問題タイトル>
<Step 5 の構造化内容>
```

### Step 7: co-issue 続行確認

AskUserQuestion で確認:

**質問**: 「co-issue を呼び出して Issue 化を続けますか？」

**選択肢**:
- `[A] はい` — `/twl:co-issue` を案内（自動実行はしない）
- `[B] いいえ` — 「explore-summary.md を保存しました。後で `/twl:co-issue` で Issue 化できます。」と案内

## エラーログクリア（Step 4 で D 選択時）

```bash
rm -f .self-improve/errors.jsonl
```

「エラーログをクリアしました。」と表示して終了。

## 禁止事項（MUST NOT）

- エラーの自動対処を行ってはならない（構造化と提示のみ）
- co-issue を自動実行してはならない（案内のみ）
- ユーザー選択をスキップしてはならない
