## Name
Autopilot

## Key Entities

- **State**: `.autopilot/` 配下の JSON ファイル群で管理される issue/session の状態。ステートマシン遷移（running → merge-ready → done/failed）を持つ
- **Orchestrator**: Phase 単位の並列セッション管理。ポーリングループで worker セッションを監視し、完了・失敗を検出
- **Chain**: chain-runner のステートマシン。16 ステップの遷移とリカバリを管理
- **MergeGate**: PR マージの実行・拒否判定。issue 状態と PR レビュー結果から条件を評価
- **Checkpoint**: specialist の findings を JSON で永続化。step 単位で PASS/WARN/FAIL を記録
- **Plan**: Issue 依存グラフから実装計画（plan.yaml）を生成。Phase 分割と並列実行グルーピングを決定
- **Launcher**: tmux window の作成と Claude Code セッションの起動を制御
- **GitHubAPI**: GitHub GraphQL/REST API のラッパー。Issue AC 抽出、Project 番号解決、PR findings 取得
- **Project**: GitHub Project Board の作成・マイグレーション・アイテム管理
- **Worktree**: git worktree の作成・削除・一覧取得。ブランチ命名規約を管理
- **Session**: セッション状態（session.json）の作成・更新・アーカイブ

## Dependencies

- なし（他の twl Context からは独立。Plugin Structure や Type System を参照しない）
- `plugins/twl/` の autopilot 系スキル（co-autopilot 等）が autopilot モジュールを CLI 経由で呼び出す

## Constraints

- 各モジュールは `python3 -m twl.autopilot.<module>` で独立実行可能（CLI エントリポイント付き）
- 状態ファイルは `.autopilot/` ディレクトリに集約。`AUTOPILOT_DIR` 環境変数でオーバーライド可能
- ステートマシン遷移は `_TRANSITIONS` 辞書で厳密に制約。不正な遷移は例外を発生させる
- GitHub API 呼び出しは `gh` CLI を `subprocess` 経由で実行（GraphQL/REST 両対応）
- tmux 操作は bash の glue スクリプト（`autopilot-launch.sh` 等）に委譲。Python 側はセッション状態管理のみ担当

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `python3 -m twl.autopilot.state read --type <issue\|session> [--field F]` | 状態 JSON の読み取り |
| `python3 -m twl.autopilot.state write --type <issue\|session> --role <pilot\|worker> [--set k=v]` | 状態 JSON の書き込み |
| `python3 -m twl.autopilot.orchestrator --plan FILE --phase N --session FILE` | Phase 実行オーケストレーション |
| `python3 -m twl.autopilot.mergegate [--reject \| --reject-final]` | マージ実行・拒否 |
| `python3 -m twl.autopilot.checkpoint write --step <step> --status <PASS\|WARN\|FAIL>` | チェックポイント書き込み |
| `python3 -m twl.autopilot.checkpoint read --step <step> --field <field>` | チェックポイント読み取り |
| `python3 -m twl.autopilot.github extract-ac <issue-number>` | Issue AC 抽出 |
| `python3 -m twl.autopilot.plan --issues JSON --project-dir DIR` | 実装計画生成 |
| `python3 -m twl.autopilot.project create --name NAME --owner OWNER` | Project Board 作成 |
| `python3 -m twl.autopilot.worktree create --branch NAME` | Worktree 作成 |

## Origin

ADR-0006（scripts 技術スタック選択基準）に基づき、`plugins/twl/scripts/` の bash スクリプト群から Python に移管（PR #45-#50, Issue #14-#18）。データ構造操作（JSON 状態管理、ステートマシン、GraphQL レスポンス処理、ポーリングループ）が主体のスクリプトを対象とした。
