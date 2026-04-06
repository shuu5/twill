## 1. bats フレームワークセットアップ

- [x] 1.1 bats-core, bats-assert, bats-support を `tests/lib/` に git submodule 追加
- [x] 1.2 `tests/bats/helpers/common.bash` 作成（sandbox setup/teardown、stub_command、load パス設定）
- [x] 1.3 `.gitmodules` に submodule エントリ追加確認

## 2. scripts/ 単体テスト - 状態管理

- [x] 2.1 `tests/bats/scripts/state-write.bats` 作成（init、フィールド更新、遷移バリデーション、ロール制御）
- [x] 2.2 `tests/bats/scripts/state-read.bats` 作成（単一フィールド、全フィールド、ファイル不在）
- [x] 2.3 `tests/bats/scripts/session-create.bats` 作成（session.json 新規作成）
- [x] 2.4 `tests/bats/scripts/session-archive.bats` 作成（アーカイブ処理）
- [x] 2.5 `tests/bats/scripts/session-add-warning.bats` 作成（warning 追加）

## 3. scripts/ 単体テスト - autopilot コア

- [x] 3.1 `tests/bats/scripts/autopilot-init.bats` 作成（.autopilot/ 初期化、排他制御）
- [x] 3.2 `tests/bats/scripts/autopilot-plan.bats` 作成（依存グラフ解決、Phase 分割、循環検出）
- [x] 3.3 `tests/bats/scripts/autopilot-should-skip.bats` 作成（skip 判定、依存先 fail 伝播）
- [x] 3.4 `tests/bats/scripts/crash-detect.bats` 作成（ペイン不在検知、非 running スキップ）

## 4. scripts/ 単体テスト - merge-gate

- [x] 4.1 `tests/bats/scripts/merge-gate-init.bats` 作成（PR 情報取得、gate ファイル生成）
- [x] 4.2 `tests/bats/scripts/merge-gate-execute.bats` 作成（squash マージ、worker 拒否）
- [x] 4.3 `tests/bats/scripts/merge-gate-issues.bats` 作成（Issue 起票ロジック）

## 5. scripts/ 単体テスト - worktree / project

- [x] 5.1 `tests/bats/scripts/worktree-create.bats` 作成（ブランチ名生成、バリデーション）
- [x] 5.2 `tests/bats/scripts/worktree-delete.bats` 作成（pilot 専任制御）
- [x] 5.3 `tests/bats/scripts/branch-create.bats` 作成（ブランチ名生成）
- [x] 5.4 `tests/bats/scripts/project-create.bats` 作成（scaffold 生成）
- [x] 5.5 `tests/bats/scripts/project-migrate.bats` 作成（マイグレーション検証）

## 6. scripts/ 単体テスト - ユーティリティ

- [x] 6.1 `tests/bats/scripts/classify-failure.bats` 作成（エラー分類）
- [x] 6.2 `tests/bats/scripts/parse-issue-ac.bats` 作成（AC 抽出）
- [x] 6.3 `tests/bats/scripts/specialist-output-parse.bats` 作成（出力パース）
- [x] 6.4 `tests/bats/scripts/tech-stack-detect.bats` 作成（スタック検出）
- [x] 6.5 `tests/bats/scripts/codex-review.bats` 作成（レビュー実行）
- [x] 6.6 `tests/bats/scripts/create-harness-issue.bats` 作成（Issue 起票）
- [x] 6.7 `tests/bats/scripts/ecc-monitor.bats` 作成（ECC 変更検知）
- [x] 6.8 `tests/bats/scripts/session-audit.bats` 作成（監査ログ分析）

## 7. Autopilot 不変条件テスト

- [x] 7.1 `tests/bats/invariants/autopilot-invariants.bats` 作成（不変条件 A〜I の 9 テスト）

## 8. 構造テスト

- [x] 8.1 `tests/bats/structure/deps-yaml.bats` 作成（構造バリデーション、参照整合性）
- [x] 8.2 `tests/bats/structure/chain-definition.bats` 作成（chain ステップ参照、type 有効性）

## 9. テストランナー刷新

- [x] 9.1 `tests/run-tests.sh` を刷新（bats + scenarios 統合実行、結果集約）
- [x] 9.2 全テスト実行して pass 確認
