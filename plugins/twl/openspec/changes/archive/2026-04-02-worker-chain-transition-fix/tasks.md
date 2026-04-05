## 1. workflow-test-ready chain 実行指示追加

- [x] 1.1 `skills/workflow-test-ready/SKILL.md` に `## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）` セクションを追加
- [x] 1.2 Step 1: change-id 解決を `### Step 1:` 形式で記載
- [x] 1.3 Step 2: テスト生成（条件判定）を `### Step 2:` 形式で記載
- [x] 1.4 Step 3: check 実行を `### Step 3:` 形式で記載（FAIL 時スキップ条件含む）
- [x] 1.5 Step 4: opsx-apply + autopilot 判定 + pr-cycle 遷移を `### Step 4:` 形式で記載

## 2. check.md チェックポイント追加

- [x] 2.1 `commands/check.md` 末尾に `## チェックポイント（MUST）` セクションを追加（`/twl:opsx-apply` 自動実行指示）

## 3. opsx-apply.md フロー制御統一

- [x] 3.1 `commands/opsx-apply.md` のフロー制御を Step 1/2/3 形式に変更（既に Step 形式で記載済み、変更不要）
- [x] 3.2 Step 3 に autopilot 判定ロジックと pr-cycle 遷移指示を明記（既に L19-40 で記載済み、変更不要）
