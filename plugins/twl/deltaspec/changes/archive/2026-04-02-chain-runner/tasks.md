## 1. chain-runner.sh 基盤

- [x] 1.1 scripts/chain-runner.sh を新規作成（エントリポイント + case ディスパッチ + 共通ユーティリティ関数）
- [x] 1.2 共通関数: extract_issue_num（ブランチ名から Issue 番号抽出）、resolve_worktree_path、構造化出力ヘルパー

## 2. setup chain ステップ実装

- [x] 2.1 init ステップ（ブランチ判定、openspec 検出、recommended_action を JSON 出力）
- [x] 2.2 worktree-create ステップ（既存 worktree-create.sh のラッパー）
- [x] 2.3 board-status-update ステップ（GraphQL で Project Board Status 更新）
- [x] 2.4 arch-ref ステップ（Issue body/comments から arch-ref タグ抽出、パストラバーサル拒否）
- [x] 2.5 ac-extract ステップ（parse-issue-ac.sh 呼び出し + snapshot 保存）

## 3. test-ready chain ステップ実装

- [x] 3.1 change-id-resolve ステップ（openspec/changes/ から最新 change-id 検出）
- [x] 3.2 check ステップ（loom check 相当の準備確認）

## 4. pr-cycle chain ステップ実装

- [x] 4.1 ts-preflight ステップ（tsconfig.json 判定 + tsc/lint/build 実行）
- [x] 4.2 pr-test ステップ（テストランナー自動検出 + テスト実行 + 結果集約）
- [x] 4.3 pr-cycle-report ステップ（結果 Markdown テーブル集約 + PR コメント投稿）
- [x] 4.4 all-pass-check ステップ（全ステップ判定 + autopilot 配下判定 + state-write.sh 呼び出し）

## 5. workflow SKILL.md 更新

- [x] 5.1 workflow-setup/SKILL.md: 機械的ステップを `bash chain-runner.sh <step>` に置換
- [x] 5.2 workflow-test-ready/SKILL.md: change-id-resolve + check を runner 呼び出しに置換
- [x] 5.3 workflow-pr-cycle/SKILL.md: ts-preflight, pr-test, pr-cycle-report, all-pass-check を runner 呼び出しに置換

## 6. deps.yaml 登録 + 検証

- [x] 6.1 deps.yaml の scripts セクションに chain-runner.sh を登録
- [x] 6.2 loom check で整合性検証
- [x] 6.3 手動実行パス（non-autopilot）で既存 command.md が動作することを確認
