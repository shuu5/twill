## 1. 高変更度スクリプト移植（autopilot 系）

- [x] 1.1 autopilot-plan.sh を `scripts/` にコピーし、plan.yaml 出力先を `.autopilot/plan.yaml` に変更
- [x] 1.2 autopilot-plan.sh の `SCRIPT_DIR` 基準パス解決を追加
- [x] 1.3 autopilot-should-skip.sh を `scripts/` にコピーし、マーカーファイル参照を `state-read.sh` 経由に置換

## 2. 高変更度スクリプト移植（merge-gate 系）

- [x] 2.1 merge-gate-init.sh を `scripts/` にコピーし、MARKER_DIR / マーカーファイル参照を `state-read.sh` 経由に置換
- [x] 2.2 merge-gate-init.sh の `.merge-ready` ファイル読み取りを `state-read.sh --type issue --field status` に変更
- [x] 2.3 merge-gate-execute.sh を `scripts/` にコピーし、マーカー操作を `state-write.sh` 呼び出しに置換
- [x] 2.4 merge-gate-execute.sh の `.done` / `.fail` / `.retry-count` 操作を state-write.sh に統一
- [x] 2.5 merge-gate-issues.sh を `scripts/` にコピー（変更最小限）

## 3. worktree / ブランチ系スクリプト移植

- [x] 3.1 worktree-create.sh を `scripts/` にコピーし、パス参照を更新
- [x] 3.2 branch-create.sh を `scripts/` にコピーし、パス参照を更新

## 4. プロジェクト管理スクリプト移植

- [x] 4.1 project-create.sh を `scripts/` にコピーし、パス参照を更新
- [x] 4.2 project-migrate.sh を `scripts/` にコピーし、パス参照を更新

## 5. ユーティリティスクリプト移植

- [x] 5.1 classify-failure.sh を `scripts/` にコピー
- [x] 5.2 parse-issue-ac.sh を `scripts/` にコピー
- [x] 5.3 session-audit.sh を `scripts/` にコピーし、DEV_AUTOPILOT_SESSION 参照を session.json ベースに置換
- [x] 5.4 check-db-migration.py を `scripts/` にコピー
- [x] 5.5 ecc-monitor.sh を `scripts/` にコピー
- [x] 5.6 codex-review.sh を `scripts/` にコピー
- [x] 5.7 create-harness-issue.sh を `scripts/` にコピー

## 6. deps.yaml 統合

- [x] 6.1 deps.yaml の scripts セクションに 16 scripts のエントリを追加
- [x] 6.2 loom check で deps.yaml バリデーション

## 7. COMMAND.md パス参照更新

- [x] 7.1 commands/worktree-create/COMMAND.md のスクリプトパスを新リポジトリ相対パスに更新
- [x] 7.2 commands/project-create/COMMAND.md のスクリプトパスを新リポジトリ相対パスに更新
- [x] 7.3 commands/project-migrate/COMMAND.md のスクリプトパスを新リポジトリ相対パスに更新

## 8. 最終確認

- [x] 8.1 DEV_AUTOPILOT_SESSION 参照が `scripts/` 内に存在しないことを grep で確認
- [x] 8.2 MARKER_DIR 参照が `scripts/` 内に存在しないことを grep で確認
- [x] 8.3 `$HOME/.claude/plugins/dev/scripts/` 固定パス参照が `scripts/` 内に存在しないことを確認
