## Why

co-autopilot が単一リポジトリを前提としており、クロスリポジトリプロジェクト（例: loom + loom-plugin-dev）の Issue 群を一括実行できない。Project Board はクロスリポジトリ対応だが、autopilot のデータモデル・スクリプト・Worker 起動が単一リポジトリ前提のため活用できていない。

## What Changes

- plan.yaml スキーマに repos セクションを追加し、Issue ごとにリポジトリ識別子を付与
- autopilot-plan.sh で `owner/repo#N` 形式の Issue 参照を解決
- 状態ファイルをリポジトリ名前空間化（`.autopilot/repos/{repo_id}/issues/issue-{N}.json`）
- session.json にリポジトリ情報を追加
- Worker 起動時に正しいリポジトリの Pilot が事前作成した worktree ディレクトリへ cd（bare repo 構造の自動検出）
- gh CLI コマンドに `-R owner/repo` フラグを追加（plan.sh, worktree-create.sh, merge-gate-*.sh, parse-issue-ac.sh）
- project-create.sh で複数リポジトリリンク対応
- project-board-sync のクロスリポジトリ Issue 同期

## Capabilities

### New Capabilities

- plan.yaml の repos セクションでクロスリポジトリプロジェクトを宣言
- `owner/repo#N` 形式による外部リポジトリ Issue の参照・解決
- Worker がリポジトリごとの正しい Pilot が作成した worktree ディレクトリで起動
- 状態ファイルのリポジトリ名前空間化による Issue 番号衝突回避
- Project Board への複数リポジトリ Issue 同期

### Modified Capabilities

- autopilot-plan.sh: repos セクション解析と `owner/repo#N` 解決を追加
- worktree-create.sh: `-R` フラグ対応と別リポジトリ bare repo パス解決
- merge-gate-init.sh / merge-gate-execute.sh: `-R` フラグ追加
- parse-issue-ac.sh: `-R` フラグ追加
- autopilot-launch.md: リポジトリ別 LAUNCH_DIR 解決
- session.json: リポジトリフィールド追加

## Impact

- **スクリプト**: autopilot-plan.sh, autopilot-init.sh, state-read.sh, state-write.sh, worktree-create.sh, merge-gate-init.sh, merge-gate-execute.sh, parse-issue-ac.sh, project-create.sh
- **コマンド**: autopilot-launch.md, autopilot-phase-execute.md, project-board-sync.md
- **スキル**: co-autopilot/SKILL.md（repos 引数の解析・plan.sh への受け渡し）
- **後方互換**: repos セクション省略時は従来の単一リポジトリ動作を維持
