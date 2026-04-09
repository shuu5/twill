---
type: atomic
tools: [Bash]
effort: low
---
# Layer 2 エスカレーション（intervene-escalate）

Observer が自分では実行せずにユーザーへ委譲する Layer 2 介入。コンフリクト解決と根本的設計課題に対応する。

## 引数

- `--pattern <id>`: 介入パターン ID（`conflict-rebase` | `design-issue`）
- `--issue <num>`: 対象 Issue 番号（任意）
- `--branch <name>`: 対象 branch 名（conflict-rebase 時）
- `--context <text>`: 問題の詳細説明

## フロー

### Step 1: 情報収集

**conflict-rebase の情報収集**:

```bash
# conflict ファイルを収集
cd "$(git rev-parse --show-toplevel)"
git fetch origin
CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null || echo "（確認不可）")
BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo "不明")
```

**design-issue の情報収集**:

```bash
# 影響コンポーネントを一覧化
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$(git rev-parse --show-toplevel)/.autopilot}"
ACTIVE_ISSUES=$(ls "$AUTOPILOT_DIR/issues/" 2>/dev/null | grep "issue-" | wc -l)
```

### Step 2: ユーザーへの報告（実行しない）

収集した情報をユーザーに提示する。**実行は行わない。**

**conflict-rebase の報告**:

```
[Layer 2 Escalate] コンフリクト解決が必要です
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
対象 branch : <branch>
main との差分: <behind> commits 遅れ
conflict ファイル:
  <file1>
  <file2>

推奨コマンド:
  git fetch origin
  git checkout <branch>
  git rebase origin/main
  # conflict を解消して git add + git rebase --continue

解消後:
  git push --force-with-lease origin <branch>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Observer は実行しません。手動で対処してください。
```

**design-issue の報告**:

```
[Layer 2 Escalate] 根本的設計課題を検出しました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
概要: <context>
影響範囲: <affected-components>
アクティブ Issue 数: <active-issues>

推奨アクション:
  1. Issue を起票して設計課題を記録
  2. 必要に応じて ADR を起草
  3. 影響する Issue を一時凍結を検討

Observer は実行しません。設計判断はユーザーが行ってください。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 3: カタログ外パターンのフォールバック処理

`--pattern unknown` が指定された場合（フォールバック）:

```
[Layer 2 Escalate] 未知の介入パターンを検出しました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
状況: <context>

このパターンは intervention-catalog.md に定義されていません。
自動的に Layer 2 Escalate として扱います。

推奨: self-improve Issue を起票してカタログを拡張してください。
  labels: scope/plugins-twl, ctx/observation, self-improve
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 4: InterventionRecord 記録

```bash
OBSERVATION_DIR="$(git rev-parse --show-toplevel)/.observation/interventions"
mkdir -p "$OBSERVATION_DIR"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
cat > "$OBSERVATION_DIR/${TIMESTAMP}-${PATTERN_ID}.json" <<JSON
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pattern_id": "${PATTERN_ID}",
  "layer": "escalate",
  "issue_num": ${ISSUE_NUM:-0},
  "branch": "${BRANCH:-}",
  "action_taken": "reported-to-user",
  "result": "escalated",
  "notes": "${CONTEXT:-}"
}
JSON
```

## 出力

- 常に: `⚠ Layer 2 Escalate: <pattern-id> — ユーザー対処が必要です`
- フォールバック時: `⚠ Layer 2 Escalate (未知パターン): カタログ拡張を推奨します`

## 禁止事項（MUST NOT）

- rebase, force push, merge, state 書き換えを実行してはならない
- ユーザーの承認なしに何らかの変更を加えてはならない
