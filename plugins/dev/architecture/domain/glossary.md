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

## 旧→新 用語対応表

旧 dev plugin (claude-plugin-dev) との用語マッピング。移行時の参照用。

| 旧用語 | 新用語 | 変更理由 |
|--------|--------|----------|
| controller-autopilot | co-autopilot | co-* naming 統一（ADR-002） |
| controller-issue | co-issue | co-* naming 統一 |
| controller-project | co-project | co-project に migrate/snapshot/plugin 統合 |
| controller-project-migrate | co-project (migrate モード) | 引数ルーティングで統合 |
| controller-project-snapshot | co-project (snapshot モード) | 引数ルーティングで統合 |
| controller-plugin | co-project (plugin テンプレート) | テンプレートの一種として吸収 |
| controller-architect | co-architect | 変更なし（co-* naming のみ） |
| controller-self-improve | co-autopilot (後処理) | 独立 controller 廃止（ADR-002） |
| controller-issue-refactor | co-issue | 吸収 |
| .done / .fail / .merge-ready マーカー | issue-{N}.json status フィールド | 統一状態ファイル（ADR-003） |
| 環境変数 DEV_AUTOPILOT_SESSION | session.json 存在チェック | 統一状態ファイル（ADR-003） |
| tmux ウィンドウ名パース | issue-{N}.json window フィールド | 統一状態ファイル（ADR-003） |
| --auto フラグ | (廃止) | Autopilot-first（ADR-001） |
| --auto-merge フラグ | (廃止) | Autopilot-first（ADR-001） |
| direct パス | (廃止、軽微変更 <10行 のみ例外) | propose → apply 一本化 |
| standard/plugin 2パス | 動的レビュアー構築 | tech-stack-detect による自動選択 |
| orchestrator-* | workflow-* | naming 整理 |

## 廃止された概念

以下の概念は本プラグインで完全に廃止される。

| 廃止概念 | 廃止理由 | 代替 |
|----------|----------|------|
| `--auto` フラグ | 全実装が co-autopilot 経由のため不要 | Autopilot-first 原則 |
| `--auto-merge` フラグ | merge は常に merge-gate 経由 | merge-gate 自動判定 |
| `.done` マーカーファイル | 散在状態管理の排除 | issue-{N}.json status = done |
| `.fail` マーカーファイル | 散在状態管理の排除 | issue-{N}.json status = failed |
| `.merge-ready` マーカーファイル | 散在状態管理の排除 | issue-{N}.json status = merge-ready |
| `.cancel` マーカーファイル | 使用頻度が低く状態遷移図に不要 | 手動介入で対処 |
| `.retry` マーカーファイル | 散在状態管理の排除 | issue-{N}.json retry_count |
| `.skip` マーカーファイル | 散在状態管理の排除 | 不変条件 D（依存先 fail 時の自動 skip） |
| direct パス | 3パス分岐の排除 | propose → apply 一本化 |
| 9種 controller | 責務境界の曖昧さ排除 | 4 controller（co-*）に統合 |
| standard/plugin 2パスレビュー | 静的パスの拡張困難 | 動的レビュアー構築 |
| controller-self-improve (独立) | controller 間状態共有の複雑さ | co-autopilot 後処理として統合 |
