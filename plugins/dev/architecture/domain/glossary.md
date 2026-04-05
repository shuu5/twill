## Glossary

### MUST 用語

| 用語 | 定義 | Context |
|------|------|---------|
| co-autopilot | Issue 群の自律実装オーケストレーター。単一 Issue も co-autopilot 経由（Autopilot-first） | Autopilot |
| chain | deps.yaml v3.0 のステップ順序定義。setup chain と pr-cycle chain の2種 | PR Cycle, Autopilot |
| merge-gate | PR のレビュー・テスト・マージ判定サブワークフロー。動的レビュアー構築で specialist を自動選択 | PR Cycle |
| issue-{N}.json | per-Issue の統一状態ファイル。status, branch, pr, retry_count 等を管理 | Autopilot |
| session.json | per-autopilot-run のセッション状態。Phase 進捗、cross-issue 警告、パターン検出を管理 | Autopilot |
| specialist | 並列実行される AI エージェント（共通出力スキーマ準拠）。haiku/sonnet で実行 | PR Cycle |
| Phase | autopilot の実行単位。依存グラフでグルーピングされた Issue 群 | Autopilot |
| Pilot | main/ worktree から実行する制御側。worktree 作成・削除・merge 実行・クリーンアップの専任者 | Autopilot |
| Worker | Pilot が作成した worktree 内で cld セッションとして起動される実装側。merge 禁止・worktree 操作禁止 | Autopilot |
| Orchestrator | Pilot 内の Issue 実行ループ管理コンポーネント。launch → poll → merge-gate → health-check を統括 | Autopilot |
| Project Board | GitHub Projects V2 ボード。Issue ステータスの SSOT。autopilot の Issue 選択元 | Project Management |
| TWiLL | Type-Woven, invariant-Led Layering。フレームワークの正式名称。CLI コマンド `twl` で操作 | 全体 |
| twl | TWiLL の CLI コマンド短縮形。旧名 `loom` | 全体 |
| twill-ecosystem | クロスリポジトリプロジェクト（#3）。TWiLL モノリポを統合管理 | Project Management |
| DeltaSpec | OpenSpec の変更仕様管理 | Issue Management |
| ECC | 外部知識ソース（doobidoo memory）。自己改善の教師データとして活用 | Self-Improve |
| Emergency Bypass | co-autopilot 障害時のみ許可される手動実装パス。retrospective 記録義務あり | Autopilot |
| Architecture Spec | 設計意図の前方参照。co-issue/co-architect が DCI で参照する living document | 全体 |
| DCI | Dynamic Context Injection。実行時にファイルを Read してコンテキストに注入するパターン | 全体 |
| CRG | Code Review Graph。MCP 経由でコード依存関係を可視化・分析するツール | TWiLL Integration |

## 照合ポリシー

用語照合は**完全一致のみ**をサポートする（fuzzy-match は非サポート）。

- 単複変化（issue/issues）・略語展開（co-autopilot/autopilot）・英日表記ゆれ（Phase/フェーズ）・識別子表記（camelCase/snake_case）の正規化は行わない
- 理由: 正規化コストが現状の課題に対して低優先。用語登録時に「正式名称」を一意に定めることで、完全一致での検出を保証する
- 適用箇所: `co-issue` Step 1.5 の glossary 照合、`worker-architecture` D-4 の drift 検出

### SHOULD 用語

| 用語 | 定義 | Context |
|------|------|---------|
| merge-ready | Issue の中間状態。Worker が宣言し、Pilot が merge-gate で判定する | Autopilot, PR Cycle |
| cross-issue warning | Phase 内 Issue 間のファイル競合リスク警告 | Autopilot |
| plan.yaml | autopilot 計画。Phase 分割・Issue 間依存定義 | Autopilot |
| retry_count | merge-gate リジェクト後のリトライ回数（最大1） | PR Cycle |
| cross-repo Issue 分割 | 複数リポにまたがる要望をリポ単位の子 Issue に分割する co-issue の機能 | Issue Management |
| script | bash/python スクリプトを deps.yaml で SSOT 追跡するためのコンポーネント型 | TWiLL Integration |
| PostToolUse hook | Claude Code のツール実行後に自動実行されるシェルスクリプト | TWiLL Integration |
| architecture context 注入 | co-issue Phase 1 で architecture/ の vision.md, context-map.md, glossary.md を Read して探索に使用 | Issue Management |
| glossary 照合 | co-issue Step 1.5 で MUST 用語との完全一致を検証し、未定義概念を INFO 通知 | Issue Management |
| tech-stack-detect | 変更ファイルの拡張子・パスから specialist を自動選択するスクリプト | PR Cycle |
| nudge | autopilot orchestrator が停滞 Worker に送信するプロンプト再注入 | Autopilot |
| health-check | Worker の chain_stall（長時間停止）を検知する監視スクリプト | Autopilot |
| resolve_issue_num() | state file ベースの Issue 番号解決関数。AUTOPILOT_DIR → git branch の優先順で判定 | Autopilot |
| architecture drift detection | co-issue Phase 3.5 で Issue が architecture spec に影響するか検出する仕組み（INFO レベル） | Issue Management |
