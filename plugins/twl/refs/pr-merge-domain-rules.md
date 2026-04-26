# workflow-pr-merge ドメインルール

`workflow-pr-merge/SKILL.md` から切り出したドメインルールの詳細。

## 禁止事項（不変条件 C enforcement）

Worker は `gh pr merge` を直接実行してはならない（不変条件 C）。マージは必ず `chain-runner.sh auto-merge` 経由で auto-merge.sh のガードを通すこと。`gh pr merge --squash` 等の直接呼び出しは ac-verify / merge-gate / auto-merge.sh の全ガードをバイパスするため厳禁。

## merge-gate エスカレーション条件

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

## merge 失敗時の対応（不変条件 F）

```
IF squash merge が失敗（コンフリクト等）
THEN
  停止のみ。自動 rebase は行わない。
  Pilot に手動介入を要求。
```

## Step-aware stagnation 防止（C6 MVP、#888）

orchestrator の stagnation 検知は PR workflow step（ac-verify / pr-cycle-report / merge-gate / e2e-screening / pr-cycle-analysis / auto-merge / all-pass-check / fix-phase / post-fix-verify / warning-fix / prompt-compliance / ts-preflight / phase-review / scope-judge / pr-test）で **300 秒**（5 分）の短縮 threshold を適用する（default 900 秒）。

- **機械的 step**（pr-cycle-report / all-pass-check / auto-merge）は `chain-runner.sh <step>` 呼出で `record_current_step` が自動的に `updated_at` を更新（heartbeat 役割）
- **LLM 判断 step**（e2e-screening / pr-cycle-analysis / merge-gate）は 5 分以内に結論を出すこと。詳細調査が必要な場合は stagnation timeout で自動 failed 化するのを待たず、Pilot に手動介入を escalate する
- env override: `DEV_AUTOPILOT_STAGNATION_SEC_PR_STEP=600` 等で threshold を調整可能
