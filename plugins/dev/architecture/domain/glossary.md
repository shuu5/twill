## Glossary

### MUST 用語

| 用語 | 定義 | Context |
|------|------|---------|
| co-autopilot | Issue 群の自律実装オーケストレーター | Autopilot |
| chain | deps.yaml v3.0 のステップ順序定義 | PR Cycle, Autopilot |
| merge-gate | PR のレビュー・テスト・マージ判定サブワークフロー | PR Cycle |
| issue-{N}.json | per-Issue の統一状態ファイル | Autopilot |
| session.json | per-autopilot-run のセッション状態 | Autopilot |
| DeltaSpec | OpenSpec の変更仕様管理 | Issue Management |
| ECC | 外部知識ソース（自己改善の教師データ） | Self-Improve |
| specialist | 並列実行される AI エージェント（共通出力スキーマ準拠） | PR Cycle |
| Phase | autopilot の実行単位。依存グラフでグルーピング | Autopilot |
| Pilot | main/ worktree から実行する制御側。worktree 削除・merge 実行の専任者 | Autopilot |
| Worker | worktree 内で実装を行う側。merge 禁止・worktree 削除禁止 | Autopilot |
| Emergency Bypass | co-autopilot 障害時のみ許可される手動実装パス。retrospective 記録義務あり | Autopilot |

### SHOULD 用語

| 用語 | 定義 | Context |
|------|------|---------|
| merge-ready | Issue の中間状態。Worker が宣言し、Pilot が merge-gate で判定する | Autopilot, PR Cycle |
| cross-issue warning | Phase 内 Issue 間のファイル競合リスク警告 | Autopilot |
| autopilot-plan.yaml (plan.yaml) | autopilot 計画。Phase 分割・Issue 間依存定義 | Autopilot |
| retry_count | merge-gate リジェクト後のリトライ回数（最大1） | PR Cycle |
| script | loom types.yaml の型の一つ。bash/python スクリプトを deps.yaml で SSOT 追跡するためのコンポーネント型。can_spawn: [], spawnable_by: [atomic, composite] | Loom Integration |
| PostToolUse hook | Claude Code のツール実行後に自動実行されるシェルスクリプト。loom validate 自動実行やエラー記録に使用 | Loom Integration |
| Architecture Spec | propose → apply パスで管理される設計仕様。direct パス廃止（軽微変更 <10行 のみ例外） | Project Management |
