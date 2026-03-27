# Contract: Autopilot <-> PR Cycle

Autopilot Context と PR Cycle Context 間のインターフェース定義。

## Input

- `issue-{N}.json` (status = `running`, 全ステップ完了時点)
- PR 情報:
  - `number`: PR 番号
  - `branch`: ブランチ名
  - `diff`: 変更差分（動的レビュアー構築に使用）

## Process: merge-gate workflow

```
1. 動的レビュアー構築
   - 変更ファイルリストから該当 specialist を決定
   - deps.yaml 変更 → worker-structure + worker-principles
   - コード変更 → worker-code-reviewer + worker-security-reviewer
   - Tech-stack 該当 → conditional specialist

2. 並列 specialist 実行
   - 全 specialist を Task spawn（並列実行）
   - 各 specialist は共通出力スキーマで結果を返却

3. 結果集約
   - 全 specialist の findings を集約
   - severity in [critical, high] && confidence >= 80 で機械的フィルタ

4. 判定
   - フィルタ結果が空 → PASS
   - フィルタ結果が非空 → REJECT
```

## Output

### PASS の場合
- `issue-{N}.json` の status を `done` に遷移
- `merged_at` にタイムスタンプを記録
- Pilot が squash merge を実行
- Pilot が worktree を削除

### REJECT の場合
- `retry_count < 1`: status を `running` に戻し、`fix_instructions` に findings を記録。Worker が fix-phase を実行
- `retry_count >= 1`: status を `failed` に確定。Pilot に報告し、手動介入を要求

## 参照する不変条件

| ID | 不変条件 | 本契約への影響 |
|----|----------|----------------|
| **C** | Worker マージ禁止 | Worker は merge-ready を宣言するのみ。merge 実行は Pilot が本契約を通じて行う |
| **E** | merge-gate リトライ制限 | REJECT 後のリトライは最大1回。retry_count で制御 |
| **F** | merge 失敗時 rebase 禁止 | squash merge 失敗時は停止のみ。自動 rebase は行わない |
