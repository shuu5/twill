## Context

loom-plugin-dev は claude-plugin-dev の後継として chain-driven + autopilot-first アーキテクチャで新規構築されたプラグイン。C-1〜C-5 で全コンポーネント移行が完了した後、実際の運用環境への切替を行う。

現在の symlink: `~/.claude/plugins/dev → ~/projects/local-projects/claude-plugin-dev/main`

切替対象: `~/.claude/plugins/dev → ~/projects/local-projects/loom-plugin-dev/main`

### 制約
- Claude Code セッション中の symlink 変更は予期しない動作を引き起こす可能性がある
- autopilot セッションは複数の tmux window で並行動作するため、in-flight 状態での切替は禁止
- 旧プラグインの状態ファイル（`/tmp/dev-autopilot/` 配下）と新プラグインの状態ファイル（`issue-{N}.json`, `session.json`）は互換性がない

## Goals / Non-Goals

**Goals:**

- 5分以内に完全ロールバック可能な切替手順を確立する
- 並行検証フェーズで機能退行がないことを確認する手順を策定する
- 旧プラグインの設計経緯を新プロジェクトの docs/ に転記する
- 退役手順（リポジトリアーカイブ）を文書化する

**Non-Goals:**

- 旧プラグインのコードを新プラグインに直接移植することはしない（C-1〜C-5 で完了済み）
- CI/CD パイプラインの変更は対象外
- 旧プラグインの全設計判断の網羅的アーカイブは行わない（重要な判断のみ転記）

## Decisions

### D1: switchover.sh スクリプトによる一元管理

symlink 切替・事前チェック・ロールバックを `scripts/switchover.sh` に集約する。サブコマンド構成:

| サブコマンド | 動作 |
|---|---|
| `switchover.sh check` | 事前チェック（loom validate/check、autopilot 未稼働確認） |
| `switchover.sh switch` | check 実行後、symlink 切替 + バックアップ作成 |
| `switchover.sh rollback` | バックアップから旧 symlink 復元 |
| `switchover.sh retire` | 試運転完了後、バックアップ削除 + リポジトリアーカイブ案内 |

### D2: 並行検証は `claude --plugin-dir` で実施

symlink を変更せずに `claude --plugin-dir ~/projects/local-projects/loom-plugin-dev/main` で新プラグインをテストする。旧プラグインと同一 Issue で動作比較し、loom validate/check/audit の全 pass を確認。

### D3: 設計経緯転記は docs/design-decisions.md に集約

旧 controller の SKILL.md から以下の設計判断経緯を転記:
- merge-gate 2パスの理由と統合判断
- deps.yaml 競合 Phase 分離ロジック
- autopilot 不変条件の由来

### D4: 状態ファイル cleanup は switchover.sh に統合

旧プラグインの `/tmp/dev-autopilot/` 配下の状態ファイルを cleanup するロジックを `switchover.sh switch` に含める。新プラグインの状態ファイルとの衝突を防止。

## Risks / Trade-offs

| リスク | 影響 | 緩和策 |
|--------|------|--------|
| in-flight セッション中の切替 | セッション破損 | `check` サブコマンドで tmux セッション/autopilot 稼働を検出、警告 |
| 新プラグインの未発見バグ | 開発作業の中断 | ロールバック手順を事前テスト、5分以内復帰目標 |
| 設計経緯の転記漏れ | 将来の判断根拠不明 | 重要判断のみに絞り、旧リポジトリは即座にアーカイブせず猶予期間を設ける |
| symlink バックアップの破損 | ロールバック不可 | バックアップパスを固定（`~/.claude/plugins/dev.bak`）、`switch` 時に既存バックアップ確認 |
