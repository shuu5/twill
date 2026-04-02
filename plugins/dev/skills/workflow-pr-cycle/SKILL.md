---
name: dev:workflow-pr-cycle
description: |
  PRサイクル（verify → review → test → fix → visual → report → merge）。
  pr-cycle chain のオーケストレーター。

  Use when user: says PRサイクル/pr-cycle/レビュー開始,
  or when called from workflow-test-ready.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-test-ready
---

# PRサイクルワークフロー（chain-driven）

pr-cycle chain のオーケストレーター。chain ステップの実行順序は deps.yaml で宣言されている。
本 SKILL.md には chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 1 | ts-preflight | atomic |
| 2 | phase-review | composite |
| 2.5 | scope-judge | atomic |
| 3 | pr-test | atomic |
| 4 | fix-phase | composite |
| 4.5 | post-fix-verify | atomic |
| 5 | warning-fix | atomic |
| 6 | e2e-screening | composite |
| 7 | pr-cycle-report | atomic |
| 7.5 | all-pass-check | atomic |
| 8 | merge-gate | composite |

## ドメインルール

### fix ループ条件

phase-review または merge-gate が REJECT を返した場合の修正ループ:

```
IF phase-review に CRITICAL findings (confidence >= 80) が存在
THEN
  1. fix-phase を実行（Step 4）
  2. post-fix-verify を実行（Step 4.5）
  3. pr-test を再実行（Step 3）
  4. テスト PASS → warning-fix へ（Step 5）
  5. テスト FAIL → fix-phase に戻る（最大 1 ループ）
ELSE
  fix-phase をスキップし warning-fix へ
```

### merge-gate エスカレーション条件

merge-gate が REJECT を返した場合の処理（不変条件 E: リトライ最大 1 回）:

```
IF retry_count == 0
THEN
  1. issue-{N}.json の status を failed → running に遷移
  2. fix_instructions に CRITICAL findings を記録
  3. fix-phase → pr-test → post-fix-verify → merge-gate を再実行
  4. retry_count を 1 に更新
ELIF retry_count >= 1
THEN
  1. issue-{N}.json の status を failed に確定
  2. Pilot に手動介入を要求
  3. ワークフローを停止
```

### merge 失敗時の対応（不変条件 F）

```
IF squash merge が失敗（コンフリクト等）
THEN
  停止のみ。自動 rebase は行わない。
  Pilot に手動介入を要求。
```

### 設計方針

chain-driven + autopilot-first 前提のため、ステップ番号ルーティング・フラグ分岐・環境変数チェック・マーカーファイル管理は不要。
ステップ順序は deps.yaml で宣言的に管理し、状態管理は issue-{N}.json に一元化されている。

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### Step 1: ts-preflight（TypeScript 機械的検証）【機械的 → runner】
```bash
bash scripts/chain-runner.sh ts-preflight
```
TypeScript プロジェクトでない場合は自動スキップ。

### Step 2: phase-review（並列 specialist レビュー）【LLM 判断】
`commands/phase-review.md` を Read → 実行。

### Step 2.5: scope-judge（スコープ判定）【LLM 判断】
`commands/scope-judge.md` を Read → 実行。

### Step 3: pr-test（テスト実行）【機械的 → runner】
```bash
bash scripts/chain-runner.sh pr-test
```

### Step 4: fix-phase（自動修正ループ）【LLM 判断】
review に CRITICAL findings がある場合のみ。`commands/fix-phase.md` を Read → 実行。
fix 後は post-fix-verify（Step 4.5）→ pr-test 再実行（Step 3: runner）のループ。

### Step 4.5: post-fix-verify（fix 後検証）【LLM 判断】
fix-phase を実行した場合のみ。`commands/post-fix-verify.md` を Read → 実行。

### Step 5: warning-fix（Warning 修正）【LLM 判断】
`commands/warning-fix.md` を Read → 実行。

### Step 6: e2e-screening（Visual 検証）【LLM 判断】
`commands/e2e-screening.md` を Read → 実行。E2E なければスキップ。

### Step 7: pr-cycle-report（結果レポート）【機械的 → runner】
各ステップの結果を Markdown レポートとして構築し、runner に渡す:
```bash
echo "$REPORT" | bash scripts/chain-runner.sh pr-cycle-report
```

### Step 7.3: pr-cycle-analysis（パターン分析）【LLM 判断】
`commands/pr-cycle-analysis.md` を Read → 実行。

### Step 7.5: all-pass-check（全パス判定）【機械的 → runner】
全ステップの結果が PASS であれば:
```bash
bash scripts/chain-runner.sh all-pass-check PASS
```
FAIL があれば:
```bash
bash scripts/chain-runner.sh all-pass-check FAIL
```

### Step 8: merge-gate（マージ判定）【LLM 判断】
`commands/merge-gate.md` を Read → 実行。上記「ドメインルール」の fix ループ・エスカレーション条件に従う。

## compaction 復帰プロトコル

compaction 後に workflow-pr-cycle chain を再開する場合、完了済みステップをスキップすること。

```bash
ISSUE_NUM=$(git branch --show-current | grep -oP '^\w+/\K\d+(?=-)' || echo "")
for step in ts-preflight pr-test all-pass-check pr-cycle-report; do
  bash scripts/compaction-resume.sh "$ISSUE_NUM" "$step" || { echo "⏭ $step スキップ"; continue; }
  # 通常手順で実行（chain-runner または LLM 実行）
done
```

- `compaction-resume.sh <ISSUE_NUM> <step>` が exit 0 → 実行、exit 1 → スキップ
- fix ループ・merge-gate は LLM ステップのため状態を確認してから再実行すること
- all-pass-check がスキップされた場合は PR の CI 結果を直接確認すること

