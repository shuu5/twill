## Vision

chain-driven + autopilot-first アーキテクチャに基づく Claude Code 開発ワークフロープラグイン。
「機械的にできることは機械に任せる」原則を徹底し、Issue → 実装 → PR → マージの全サイクルを自律化する。

## Constraints

- TWiLL フレームワーク準拠（deps.yaml v3.0, types.yaml 型システム）
- Claude Code プラグインシステム仕様に準拠
- Controller は6つ（co-autopilot, co-issue, co-project, co-architect, co-utility, co-self-improve）+ Supervisor は1つ（su-observer）
- Bare repo + worktree 一律（branch モード廃止）
- 状態管理は統一 JSON 2種（issue-{N}.json + session.json）
- **Project Board 必須**（ADR-006）: 全プロジェクトで GitHub Projects V2 を使用。autopilot の Issue 選択元、ステータス同期先
- **クロスリポジトリ対応**（ADR-007）: twill-ecosystem プロジェクトで複数リポを統合管理
- Emergency Bypass: co-autopilot 障害時のみ手動パス許可（retrospective 記録義務あり）

### Controller 操作カテゴリ

| カテゴリ | 定義 | 該当 Controller |
|----------|------|-----------------|
| Implementation | コード変更・PR 作成を伴う操作 | co-autopilot のみ |
| Non-implementation | Issue 作成・設計・プロジェクト管理 | co-issue, co-project, co-architect |
| Utility | スタンドアロンユーティリティ操作 | co-utility |
| Observation | ライブセッション観察・問題検出・Issue 起票 | co-self-improve |
| Supervisor | controller の動作を監視・介入するメタレイヤー | su-observer |

Non-implementation controller は co-autopilot を spawn しない。
co-architect が「設計 + 実装」を要求された場合: 設計完了 → Issue 起票（co-issue 経由）→ co-autopilot で実装。

### 機械 / LLM の境界

「LLM は判断のために使う。機械的にできることは機械に任せる。」— この原則が全設計判断の根底にある。

**判断基準**: ルールベースで正解が一意に決まる処理は機械化する。コンテキスト依存で複数の妥当な選択肢がある処理は LLM に委ねる。

| 機械がやるべきこと | 実装手段 | LLM に任せてよいこと | 理由 |
|--------------------|----------|----------------------|------|
| 状態管理（JSON read/write） | state-read.sh / state-write.sh | Issue の分解判断 | 分解粒度はコンテキスト依存 |
| ファイル操作（worktree 作成・削除） | worktree-create.sh / worktree-delete.sh | コードレビュー品質 | コード品質の判断は多面的 |
| バリデーション（twl validate） | PostToolUse hook | エラー診断 | 根本原因の特定は推論が必要 |
| 出力スキーマ強制（specialist 共通スキーマ） | JSON Schema + パース | アーキテクチャ決定 | トレードオフの評価が必要 |
| ステップ順序制御（chain-driven） | deps.yaml chains | merge 失敗時の対処判断 | 失敗パターンが多様 |
| フラグ伝搬（統一状態ファイル） | issue-{N}.json / session.json | cross-issue 影響の分析 | ファイル競合の影響度は文脈依存 |
| 型ルール検証（PostToolUse hook） | twl validate / check | パターン検出・知見の抽出 | 有意なパターンの選別は判断 |
| specialist 出力の機械的フィルタ | severity == CRITICAL && confidence >= 80 | PR レビューの最終判断 | WARNING の対処優先度は文脈依存 |
| 依存グラフの循環検出 | plan.yaml 生成時の DAG 検証 | Phase 分割の最適化 | 並列度と依存管理のバランス |
| セッション出力の機械的キャプチャ | tmux capture-pane + rule-based 検出 | ライブセッションのパターン抽出 | 有意なパターンの選別は文脈依存 |
| retry 上限の強制 | retry_count チェック | fix-phase の修正戦略 | 修正方針は問題の性質に依存 |
| Project Board ステータス同期 | gh project item-edit | Issue の優先度判断 | ビジネスコンテキストに依存 |
| クロスリポ Issue 分割の検出 | gh project linked-repos クエリ | 分割粒度の判断 | リポ間依存の評価は文脈依存 |
| 定型介入回復（intervention-catalog Layer 0） | intervention-catalog.yaml ルールマッチ | 介入要否・種類の判断 | 文脈依存（エラー内容・進行状況による） |

### Architecture Spec の役割

Architecture Spec は**設計意図の前方参照**として機能する living document。

- **DCI 注入源**: co-issue（Phase 1 の architecture context 注入、Step 1.5 の glossary 照合）と co-architect が直接参照する
- **陳腐化は有害**: 不正確な Spec は co-issue の Issue 品質を低下させる。変更時は architecture spec の更新を検討する
- **歴史は git に委ねる**: 現在の設計意図のみを記述。移行経緯や旧プラグインとの比較は git history で参照可能

## Non-Goals

- **技術スタック固有の機能**: Next.js, FastAPI, R/Bioconductor 等のフレームワーク固有操作はコンパニオンプラグインの責務。dev plugin は技術スタックに依存しない汎用ワークフロー（Issue → 実装 → PR → マージ）のみを提供する。tech-stack-detect スクリプトで specialist を選択するが、specialist 自体はコンパニオンプラグインまたは汎用 specialist として提供される
- **twl CLI 本体の機能開発**: deps.yaml パーサー、型システム、validate/audit/chain コマンドは twill/cli/ の責務。dev plugin は twl CLI を Open Host Service として消費するのみ
- **AI/LLM の判断を機械化すること**: Issue 分解、コードレビュー品質、エラー診断、merge 失敗時の対処は LLM の判断領域。これらを rule-based に置換しようとしない
