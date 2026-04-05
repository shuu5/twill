## 1. 廃止フラグ・環境変数テスト修正

- [x] 1.1 `auto-flag-removal.test.sh` の `--auto`/`--auto-merge` 不在確認テスト修正（検索パターン・除外ディレクトリ調整）
- [x] 1.2 `DEV_AUTOPILOT_SESSION` 不在確認テスト修正（all-pass-check.test.sh 等）
- [x] 1.3 `autopilot-launch` テストの `--auto --auto-merge` 参照修正

## 2. 削除済みスクリプト・コンポーネントテスト修正

- [x] 2.1 `autopilot-scripts-migration.test.sh`（autopilot-plan.sh、autopilot-should-skip.sh）修正
- [x] 2.2 `co-project-scripts-migration.test.sh`（project-create.sh、project-migrate.sh）修正
- [x] 2.3 `check-db-migration` deps.yaml 登録期待テスト修正
- [x] 2.4 `classify-failure.sh`、`session-audit.sh`、`ecc-monitor.sh` テスト修正
- [x] 2.5 `branch-create.sh` テスト修正（worktree-branch-scripts-migration.test.sh）
- [x] 2.6 `worktree-create.sh` テスト修正

## 3. deps.yaml 構造・カウント系テスト修正

- [x] 3.1 agents 数・refs 数の期待値を現行値に更新
- [x] 3.2 chain/step_in 構造テスト修正（chain-definition.test.sh 等）
- [x] 3.3 atomic/composite コンポーネント数テスト修正
- [x] 3.4 `deps.yaml co-autopilot can_spawn` テスト修正

## 4. SKILL.md 構造テスト修正

- [x] 4.1 `co-issue SKILL.md` 行数制限テスト修正
- [x] 4.2 `pr-cycle SKILL.md` ステップ番号・フロー列挙テスト修正
- [x] 4.3 `co-autopilot SKILL.md` 構造テスト修正

## 5. merge-gate・health-report テスト修正

- [x] 5.1 merge-gate-execute.sh モード分岐テスト修正
- [x] 5.2 merge-gate ディレクトリ構造テスト修正
- [x] 5.3 health-report.bats スタブ参照修正

## 6. その他テスト修正

- [x] 6.1 Bash エラー記録テスト修正（bash-error-recording.test.sh）
- [x] 6.2 loom deep-validate 警告件数テスト修正
- [x] 6.3 specialist パーサーテスト修正
- [x] 6.4 ベースラインテスト（bats/scenario ファイル数）更新
- [x] 6.5 tmux ペイン消失検知テスト修正

## 7. 最終検証

- [x] 7.1 全テスト実行し PASS 率 100% 確認
