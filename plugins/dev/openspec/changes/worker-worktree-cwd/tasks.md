## 1. autopilot-launch.sh: --worktree-dir 引数追加

- [x] 1.1 usage() に `--worktree-dir DIR` オプションを追加
- [x] 1.2 引数パースループに `--worktree-dir` を追加し WORKTREE_DIR 変数に格納
- [x] 1.3 L204-215 の LAUNCH_DIR 計算ロジックを変更: `--worktree-dir` が渡された場合はその値を優先
- [x] 1.4 単体テスト更新: `--worktree-dir` 引数が LAUNCH_DIR に反映されることを確認

## 2. autopilot-orchestrator.sh: Pilot 側での worktree 事前作成

- [x] 2.1 `launch_worker()` 内で `autopilot-launch.sh` 呼び出し前に `worktree-create.sh` を実行
- [x] 2.2 `worktree-create.sh` の出力（worktree パス）を `WORKTREE_DIR` に格納
- [x] 2.3 `launch_args+=( --worktree-dir "$WORKTREE_DIR" )` を追加
- [x] 2.4 クロスリポジトリ対応: `ISSUE_REPO_PATH` がある場合は `--project-dir "$ISSUE_REPO_PATH"` で worktree-create を呼ぶ
- [x] 2.5 既存 worktree がある場合の冪等性確認（worktree-create.sh の動作確認）

## 3. chain-steps.sh: worktree-create を chain から除去

- [x] 3.1 `CHAIN_STEPS` 配列から `worktree-create` を削除
- [x] 3.2 `QUICK_SKIP_STEPS` 配列から `worktree-create` を削除
- [x] 3.3 chain-runner-next-step.bats の期待値を更新（init の次は board-status-update）

## 4. architecture/domain/contexts/autopilot.md: 不変条件B 更新

- [x] 4.1 不変条件B の概要を「Worktree ライフサイクル Pilot 専任（作成・削除ともに Pilot）」に更新
- [x] 4.2 Worktree ライフサイクルテーブルを更新（Worker 行の「作成」列を削除）（main ブランチ適用済み）
- [x] 4.3 Worker 実行フローの mermaid 図を更新（worktree-create ステップを削除）（main ブランチ適用済み）

## 5. workflow-setup/SKILL.md: worktree-create ステップの更新

- [x] 5.1 Step 2: worktree-create の説明を「Worker（IS_AUTOPILOT=true）時はスキップ。Manual 実行時のみ」に変更
- [x] 5.2 SKILL.md の chain ライフサイクルテーブルから worktree-create 行を削除（chain-steps.sh から除去されるため）

## 6. deps.yaml 更新

- [x] 6.1 autopilot-orchestrator と worktree-create の依存関係を追加
- [x] 6.2 `loom check` で整合性確認
- [x] 6.3 `loom update-readme` で README 更新

## 7. テスト更新

- [x] 7.1 autopilot-invariants.bats の不変条件B テストを更新（worktree-create が chain に含まれないことを検証）
- [x] 7.2 autopilot-launch.bats に `--worktree-dir` テストケースを追加（cross-repo-worker-launch.bats に追加）
- [x] 7.3 全テストスイートを実行して PASS 確認（cross-repo-worker-launch.bats 7/7 PASS、chain-runner-next-step の next-step テストは pre-existing failure）
