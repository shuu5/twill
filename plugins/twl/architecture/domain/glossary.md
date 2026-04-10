## Glossary

### MUST 用語

| 用語 | 定義 | Context |
|------|------|---------|
| co-autopilot | Issue 群の自律実装オーケストレーター。単一 Issue も co-autopilot 経由（Autopilot-first） | Autopilot |
| chain | deps.yaml v3.0 のステップ順序定義。setup / pr-verify / pr-fix / pr-merge 等、deps.yaml chains セクションで定義されるステップ順序。具体的な chain 名の列挙は deps.yaml chains セクションを参照 | PR Cycle, Autopilot |
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
| twl | TWiLL の CLI コマンド短縮形 | 全体 |
| twill-ecosystem | クロスリポジトリプロジェクト（#3）。TWiLL モノリポを統合管理 | Project Management |
| DeltaSpec | DeltaSpec の変更仕様管理 | Issue Management |
| ECC | 外部知識ソース（doobidoo memory）。自己改善の教師データとして活用 | Self-Improve |
| Emergency Bypass | co-autopilot 障害時のみ許可される手動実装パス。retrospective 記録義務あり | Autopilot |
| Architecture Spec | 設計意図の前方参照。co-issue/co-architect が DCI で参照する living document | 全体 |
| DCI | Dynamic Context Injection。実行時にファイルを Read してコンテキストに注入するパターン | 全体 |
| CRG | Code Review Graph。MCP 経由でコード依存関係を可視化・分析するツール | TWiLL Integration |
| Supervisor | プロジェクト常駐のメタ認知レイヤー。全 controller を監視・調整・知識外部化する上位層（ADR-014） | Supervision |
| su-observer | Supervisor 型の唯一のコンポーネント。main session そのものとして機能し、controller を spawn → observe する | Supervision |
| SupervisorSession | su-observer のプロジェクト常駐セッション状態。Wave 管理・介入記録・記憶予算を追跡 | Supervision |
| su-compact | 知識外部化 + compaction を実行するスキル/コマンド。自動（50%閾値）/手動/Wave完了時に発火 | Supervision |
| Three-Layer Memory | 三層記憶モデル。Working Memory（context）+ Externalized Memory（doobidoo/ファイル）+ Compressed Memory（compaction後） | Supervision |
| Wave | autopilot で大量 Issue を分割実行する単位。1 Wave = 1 co-autopilot セッション。Wave 間で su-compact を実行 | Supervision, Autopilot |
| Observer | 別 session を能動的に観察する観察側 session。read-only で対象を覗き見る | Observation |
| Observed | 観察される対象 session（autopilot/co-issue/co-architect 等） | Observation |
| Live Observation | 実行中の session を外部から観察し問題を検出する活動 | Observation |
| co-self-improve | Live Observation を統括する controller。テストプロジェクト管理も担う | Observation |
| Test Target | observer の観察対象として隔離された worktree（test-target/main branch） | Observation |
| Observation Pattern | 過去に検出された問題パターンとその検知ルール | Observation |
| Test Scenario | テストプロジェクトに投入する Issue 群と期待結果のセット（smoke / regression / load） | Observation |

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
| observer-evaluator | LLM 判定で微妙な問題を検出する specialist | Observation |
| problem-detect | rule-based で capture から既知パターンを検出する atomic | Observation |
| test-project-init/reset/scenario-load | テストプロジェクト隔離 worktree 管理 atomic 群 | Observation |
| load-test baseline | 負荷テスト level（smoke/regression/load）の定量基準 reference | Observation |
| prompt-compliance | refined_by ハッシュ整合性をチェックする chain step（pr-verify chain）。dispatch_mode=runner | PR Cycle |
| pseudo-pilot | Pilot の手動ワークフロー支援スクリプト群（plugins/twl/scripts/pseudo-pilot/）。PR 待機・Worker 完了待機 | Autopilot |
| workflow-prompt-audit | stale コンポーネントの refined_by 整合性を一括監査する workflow（#209） | PR Cycle |
| cli_dispatch | cli.py から分離された実装ロジックモジュール（#265） | TWiLL Integration |
