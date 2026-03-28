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
