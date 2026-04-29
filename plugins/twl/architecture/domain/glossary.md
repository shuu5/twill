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
| Pilot | 制御側 cld セッション。Worker セッションを spawn し、集約を行う。autopilot では main worktree 固定で worktree 作成・削除・merge 実行・クリーンアップを担当、co-issue v2 では session 単位で起動 | Autopilot, co-issue v2 |
| Worker | Pilot が tmux 経由で spawn した独立 cld セッション。自律的に単一タスク（autopilot では 1 issue の実装、co-issue v2 では 1 issue の lifecycle）を完遂する。merge 禁止・worktree 操作禁止 | Autopilot, co-issue v2 |
| Orchestrator | Pilot 内の Issue 実行ループ管理コンポーネント。launch → poll → merge-gate → health-check を統括 | Autopilot |
| Project Board | GitHub Projects V2 ボード。Issue ステータスの SSOT。autopilot の Issue 選択元 | Project Management |
| TWiLL | Type-Woven, invariant-Led Layering。フレームワークの正式名称。CLI コマンド `twl` で操作 | 全体 |
| epic | 関連 Issue を統括する meta Issue。GitHub label `epic` が付与され、子 Issue を Acceptance Criteria の checkbox として保持する | Issue Management |
| MCP server | Model Context Protocol server。AI session に対して tool/resource を提供する。本プロジェクトでは FastMCP stdio 実装を採用 (`cli/twl/src/twl/mcp_server/server.py`) | TWiLL Integration |
| MCP tool | MCP server 経由で expose される callable 関数。`@mcp.tool()` decorator で登録され、JSON envelope を返す。tools.py（または Phase 2 以降は分割後の tools_*.py）に集約される | TWiLL Integration |
| tools.py | `cli/twl/src/twl/mcp_server/tools.py`。MCP tool 群の SSOT ファイル（Phase 0/1 現在）。Hybrid Path 5 原則 (handler pure / json.dumps / try/except ImportError / 明示引数 / 1 ファイル集約) を踏襲。Phase 2 末期に tools_validation.py / tools_state.py / tools_autopilot.py / tools_comm.py に分割予定 | TWiLL Integration |
| twl | TWiLL の CLI コマンド短縮形 | 全体 |
| twill-ecosystem | クロスリポジトリプロジェクト（#6）。TWiLL モノリポを統合管理 | Project Management |
| TDD 直行 flow | Acceptance Criteria を起点に RED test → 実装 → GREEN 確認 → REFACTOR を順に進める co-autopilot の標準フロー（ADR-023）。proposal/specs 中間層を経由しない | Autopilot |
| Acceptance Criteria | Issue body の `## AC` / `## Acceptance Criteria` 節で列挙される受入条件。TDD 直行 flow の起点であり、`ac-scaffold-tests` が AC 1 件につき 1 RED test を生成する (ADR-023) | Autopilot, Issue Management |
| ac-scaffold-tests | AC を入力に RED test を生成する agent (ADR-023 D-2)。旧 `spec-scaffold-tests` (DeltaSpec specs を入力とする構成) を reshape したもの | Autopilot |
| RED / GREEN / REFACTOR | TDD 直行 flow の 3 段階。RED: `pytest --collect-only` で test が fail することを確認、GREEN: 実装で test PASS、REFACTOR: 既存テストを maintain しつつコード整理 (ADR-023 D-3) | Autopilot |
| ECC | 外部知識ソース（doobidoo memory）。自己改善の教師データとして活用 | Self-Improve |
| Emergency Bypass | co-autopilot 障害時のみ許可される手動実装パス。retrospective 記録義務あり | Autopilot |
| Architecture Spec | 設計意図の前方参照。co-issue/co-architect が DCI で参照する living document | 全体 |
| Spec Implementation | Architecture spec（`architecture/` 配下のドキュメント）の変更・PR 作成を担う controller カテゴリ。co-architect のみ該当。Implementation（コード変更）とは区別される（ADR-019） | 全体 |
| DCI | Dynamic Context Injection。実行時にファイルを Read してコンテキストに注入するパターン | 全体 |
| CRG | Code Review Graph。MCP 経由でコード依存関係を可視化・分析するツール | TWiLL Integration |
| graceful degradation | 対応外環境（non-bare git リポ等）で機能を完全に停止せず、no-op（exit 0）で安全に終了する設計パターン。supervisor hook がその実装例（SU-8） | Supervision |
| Supervisor | プロジェクト常駐のメタ認知レイヤー。全 controller を監視・調整・知識外部化する上位層（ADR-014） | Supervision |
| su-observer | Supervisor 型の唯一のコンポーネント（ADR-014 で observer 型から再定義）。main session そのものとして機能し、controller を spawn → observe する。Observer（read-only）とは異なり介入権限を持つ | Supervision |
| SupervisorSession | su-observer のプロジェクト常駐セッション状態。Wave 管理・介入記録・記憶予算を追跡 | Supervision |
| su-compact | 知識外部化 + compaction を実行するスキル/コマンド。自動（80%閾値）/手動/Wave完了時に発火 | Supervision |
| Three-Layer Memory | 三層記憶モデル。Long-term Memory（永続）+ Working Memory Externalization（一時退避）+ Compressed Memory（compaction後） | Supervision |
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
| Bug Reproduction Scenario | 既知 Bug の再現条件を意図的に誘発するテストシナリオ。test-scenario-catalog に `bug-` プレフィックスパターンと対で定義される | Observation |
| prompt-compliance | refined_by ハッシュ整合性をチェックする chain step（pr-verify chain）。dispatch_mode=runner | PR Cycle |
| pseudo-pilot | Pilot の手動ワークフロー支援スクリプト群（plugins/twl/scripts/pseudo-pilot/）。PR 待機・Worker 完了待機 | Autopilot |
| workflow-prompt-audit | stale コンポーネントの refined_by 整合性を一括監査する workflow（#209） | PR Cycle |
| workflow-issue-lifecycle | co-issue v2 の Worker workflow。1 Issue の lifecycle（structure → spec-review → aggregate → fix loop → arch-drift → create）を独立 cld セッションで担当（ADR-017） | Issue Management |
| issue-lifecycle-orchestrator | co-issue v2 の Pilot 側オーケストレーター。N 個の workflow-issue-lifecycle Worker を tmux 経由で並列 spawn し、完了検知・集約を行う。MAX_PARALLEL=3 | Issue Management |
| conflict | IssueState の状態値。deps.yaml コンフリクト検出時に Pilot が設定。Pilot リベース後に merge-ready に復帰、リトライ上限超過で failed に遷移 | Autopilot |
| cli_dispatch | cli.py から分離された実装ロジックモジュール（#265） | TWiLL Integration |
| Refined Status | Issue lifecycle の review 完了 marker。3 specialist review（issue-critic / issue-feasibility / worker-codex-reviewer）が完了した Issue に付与される Project Board Status field の値（先頭大文字 `Refined`、ADR-024）。従来の `refined` label（小文字）を補完し、Phase B 以降は Status のみで管理する。 | Issue Management, Autopilot |
| skipped | Wave 集計における Issue 状態。state_file_missing / dependency_failed / status_other の 3 カテゴリで細分類され、wave-collect の echo 統計と skip 内訳セクションに反映される。 | Autopilot |
| intentional skip | state_file_missing または dependency_failed に分類されるスキップ。完遂率の分母から除外される意図的なスキップ（observer や Pilot の判断に基づく）。status_other は分母に残る。 | Autopilot |
| state_file_missing | issue-N.json 不在で skip されたケース。worktree 未作成や Refined 未達で投入除外された Issue が該当。intentional skip 扱いで完遂率分母から除外。 | Autopilot |
| dependency_failed | 依存先 Issue の失敗伝播により skip されたケース。autopilot-should-skip.sh が判定する。intentional skip 扱いで完遂率分母から除外。 | Autopilot |
| status_other | status が done / failed 以外（in_progress / ready_for_pr / unknown 等）で skip されたケース。機械判定 enum。完遂率分母に残る（停滞を可視化）。 | Autopilot |
