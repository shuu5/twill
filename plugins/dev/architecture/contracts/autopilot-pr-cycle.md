# Contract: Autopilot <-> PR Cycle

Autopilot Context と PR Cycle Context 間のインターフェース定義。

## Input

- `issue-{N}.json` (status = `merge-ready`, 全ステップ完了時点)
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
   - severity == CRITICAL && confidence >= 80 で機械的フィルタ

4. 判定
   - フィルタ結果が空 → PASS
   - フィルタ結果が非空 → REJECT
```

## Output

### PASS の場合
- `issue-{N}.json` の status を `done` に遷移
- `merged_at` にタイムスタンプを記録
- Pilot が squash merge を実行
- Pilot がクリーンアップを実行（順序保証）:
  1. `tmux kill-window` — Worker セッション終了（worktree 内動作停止を保証）
  2. `worktree-delete.sh` — worktree + ローカルブランチ削除
  3. `git push origin --delete` — リモートブランチ削除
- 各クリーンアップステップの失敗は個別に警告し、残りを続行（冪等性）

### REJECT の場合
- `retry_count < 1`: status を `failed` に遷移後、`failed` → `running` に再遷移。`fix_instructions` に findings を記録。Worker が fix-phase を実行
- `retry_count >= 1`: status を `failed` に確定。Pilot に報告し、手動介入を要求

## 参照する不変条件

| ID | 不変条件 | 本契約への影響 |
|----|----------|----------------|
| **B** | Worktree ライフサイクル Pilot 専任 | Worktree の作成・削除は Pilot が行う。クリーンアップも Pilot 側で集約実行 |
| **C** | Worker マージ禁止 | Worker は merge-ready を宣言するのみ。merge 実行は Pilot が本契約を通じて行う |
| **E** | merge-gate リトライ制限 | REJECT 後のリトライは最大1回。retry_count で制御 |
| **F** | merge 失敗時 rebase 禁止 | squash merge 失敗時は停止のみ。自動 rebase は行わない |
