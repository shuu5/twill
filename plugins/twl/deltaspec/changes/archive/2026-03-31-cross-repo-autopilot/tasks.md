## 1. plan.yaml スキーマ拡張

- [x] 1.1 autopilot-plan.sh に repos セクション生成ロジックを追加（`--repos` 引数の解析、repos YAML ブロック出力）
- [x] 1.2 autopilot-plan.sh の Issue 参照解決を拡張（bare integer / repo_id#N / owner/repo#N の 3 形式パース）
- [x] 1.3 phases 内の issues を `{ number: N, repo: repo_id }` オブジェクト形式に拡張（後方互換: bare integer も許可）
- [x] 1.4 dependencies セクションのキー・値を `repo_id#N` 形式に拡張

## 2. 状態ファイル名前空間化

- [x] 2.1 autopilot-init.sh で repos セクション検出時に `.autopilot/repos/{repo_id}/issues/` ディレクトリを作成
- [x] 2.2 state-read.sh に `--repo` 引数を追加し、名前空間パスから読み取り（省略時は従来パスにフォールバック）
- [x] 2.3 state-write.sh に `--repo` 引数を追加し、名前空間パスに書き込み（省略時は従来パスにフォールバック）
- [x] 2.4 session.json に `repos` フィールドと `default_repo` フィールドを追加

## 3. gh CLI -R フラグ対応

- [x] 3.1 autopilot-plan.sh の `gh issue view` / `gh api` に repo_id ベースの `-R` フラグ付与ヘルパー関数を作成
- [x] 3.2 worktree-create.sh に `-R` フラグ対応と外部リポジトリ bare repo パス解決を追加
- [x] 3.3 merge-gate-init.sh の `gh pr diff` に `-R` フラグ対応を追加
- [x] 3.4 merge-gate-execute.sh の `gh pr merge` に `-R` フラグ対応を追加
- [x] 3.5 parse-issue-ac.sh の `gh api` で owner/repo を明示指定に変更

## 4. Worker 起動のリポジトリ解決

- [x] 4.1 autopilot-launch.md に repo_id → LAUNCH_DIR 解決ロジックを追加（bare repo / standard repo 判定）
- [x] 4.2 Worker 起動時に AUTOPILOT_DIR を Pilot 側の `.autopilot/` パスに固定する環境変数を設定
- [x] 4.3 autopilot-phase-execute.md にリポジトリコンテキスト（repo_id, owner, name）の受け渡しを追加
- [x] 4.4 Worker 起動前の repos[repo_id].path 存在チェックと bare repo 構造検証を追加

## 5. Project Board・co-autopilot 統合

- [x] 5.1 project-create.sh で repos セクションの全リポジトリに `linkProjectV2ToRepository` を呼び出し
- [x] 5.2 project-board-sync.md でクロスリポジトリ Issue の同期対応
- [x] 5.3 co-autopilot/SKILL.md に `--repos` 引数の解析と autopilot-plan.sh への受け渡しを追加

## 6. テスト・検証

- [x] 6.1 後方互換テスト: repos セクション省略時に従来の単一リポジトリ動作が維持されることを確認
- [x] 6.2 クロスリポジトリ E2E テスト: 2 リポジトリの Issue を含む plan.yaml で autopilot セッションを実行
- [x] 6.3 状態ファイル衝突テスト: 異なるリポジトリの同一 Issue 番号で状態ファイルが分離されることを確認
