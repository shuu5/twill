## Why

旧 dev plugin（`~/.claude/plugins/dev/scripts/`）に存在する 18 本の shell scripts のうち、新リポジトリに未移植の 16 本が残っている。これらがないと autopilot・merge-gate・project 管理の各ワークフローが動作しない。B-3（状態管理再設計）で統一状態ファイル（state-read/write）が導入済みのため、旧マーカーファイル操作と DEV_AUTOPILOT_SESSION 参照を排除しつつ移植する必要がある。

## What Changes

- 旧 plugin の残り 16 scripts を `scripts/` に移植（新アーキテクチャ適応）
- マーカーファイル操作（`.done`, `.fail`, `.merge-ready`）を `state-write.sh` / `state-read.sh` 呼び出しに置換
- `DEV_AUTOPILOT_SESSION` 環境変数参照を排除し、`session.json` ベースの判定に統一
- deps.yaml に新 script エントリを追加
- 既存 COMMAND.md のスクリプトパス参照を新リポジトリパスに更新

## Capabilities

### New Capabilities

- autopilot-plan: deps.yaml 依存グラフ計算 → plan.yaml 生成（統一状態ファイル対応）
- autopilot-should-skip: Phase 依存スキップ判定（state-read.sh 経由）
- merge-gate-init: GATE_TYPE 判定（統一状態ファイル対応）
- merge-gate-execute: approve/reject 実行（state-write.sh 経由）
- merge-gate-issues: tech-debt Issue 自動起票
- branch-create: 通常 repo 向けブランチ作成
- worktree-create: bare repo 向け worktree 作成（新リポジトリパス）
- classify-failure: テスト失敗の分類
- parse-issue-ac: Issue AC パース
- session-audit: セッション JSONL 事後分析
- project-create: bare repo 初期化
- project-migrate: プロジェクト移行
- check-db-migration: DB マイグレーションチェック（Python）
- ecc-monitor: ECC リポジトリ変更検知
- codex-review: Codex レビュー
- create-harness-issue: self-improve Issue 起票

### Modified Capabilities

- 既存 10 scripts（B-3/B-5 で作成済み）のインターフェース整合性確認

## Impact

- **scripts/**: 16 ファイル追加
- **deps.yaml**: scripts セクションに 16 エントリ追加
- **commands/**: worktree-create, project-create, project-migrate の COMMAND.md パス参照更新
- **依存**: B-3（state-read/write）、B-5（specialist-output-parse）に依存
- **loom#31 依存**: deps.yaml v3.0 の script 型サポートが必要
