# PRサイクル結果フォーマット・投稿

verify / review / test / fix の結果を構造化し、PR コメントとして投稿する。

## 入力

- 各ステップの実行結果（PASS / WARN / FAIL + details）
- PR 番号

## 出力

- PR コメント（Markdown フォーマット）

## 実行ロジック（MUST）

### Step 1: 結果集約

各ステップの結果を以下のフォーマットに集約:

```markdown
## PR Cycle Report

| Step | Status | Details |
|------|--------|---------|
| ts-preflight | PASS | - |
| phase-review | WARN | 2 WARNING findings |
| pr-test | PASS | 22/22 tests passed |
| fix-phase | N/A | No CRITICAL findings |
| post-fix-verify | N/A | - |
| warning-fix | PASS | 1/2 warnings fixed |
| e2e-screening | PASS | - |

### Findings Summary
- CRITICAL: 0
- WARNING: 1 (unfixed → tech-debt #XX)
- INFO: 3
```

### Step 2: PR コメント投稿

```bash
gh pr comment ${PR_NUM} --body "${REPORT}"
```

### Step 3: 結果返却

集約結果を all-pass-check に渡すために構造化データとして返す。

## チェックポイント（MUST）

`/dev:pr-cycle-analysis` を Skill tool で自動実行。

