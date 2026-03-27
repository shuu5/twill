## Vision

chain-driven + autopilot-first アーキテクチャに基づく Claude Code 開発ワークフロープラグイン。
旧 dev plugin (claude-plugin-dev) の複雑性ホットスポットを解消し、「機械的にできることは機械に任せる」原則を徹底する。

## Constraints

- Loom フレームワーク準拠（deps.yaml v3.0, types.yaml 型システム）
- Claude Code プラグインシステム仕様に準拠
- Controller は4つのみ（co-autopilot, co-issue, co-project, co-architect）
- Bare repo + worktree 一律（branch モード廃止）
- 状態管理は統一 JSON 2種（issue-{N}.json + session.json）
- Emergency Bypass: co-autopilot 障害時のみ手動パス許可（retrospective 記録義務あり）

### 旧 plugin 複雑性ホットスポットと回避策

旧 dev plugin (claude-plugin-dev) で発生した複雑性ホットスポットと、本プラグインでの回避策:

| ホットスポット | 旧 plugin の問題 | 回避策 |
|----------------|-----------------|--------|
| 9 Controller | 責務境界が曖昧、テストパス爆発 | 4 controller に統合（ADR-002）。Implementation は co-autopilot に一本化 |
| --auto / --auto-merge フラグ | 3パス分岐（手動/auto/auto-merge）でコードの複雑性増大 | Autopilot-first（ADR-001）。全実装が co-autopilot 経由。フラグ廃止 |
| 6種マーカーファイル | .done, .fail, .merge-ready 等の散在状態管理 | 統一状態ファイル（ADR-003）。issue-{N}.json + session.json の2種に集約 |
| direct パス | propose → apply の正規パスと direct パスの並存 | direct パス廃止（軽微変更 <10行 のみ例外）。propose → apply を唯一のパスに |
| standard/plugin 2パス | レビュアー構築の静的2パスが拡張困難 | 動的レビュアー構築。変更内容からspecialistを自動選択（tech-stack-detect） |
| controller-self-improve 独立 | controller 間の状態共有が複雑 | co-autopilot に吸収（ADR-002）。session 後処理として統合 |

### Controller 操作カテゴリ

| カテゴリ | 定義 | 該当 Controller |
|----------|------|-----------------|
| Implementation | コード変更・PR 作成を伴う操作 | co-autopilot のみ |
| Non-implementation | Issue 作成・設計・プロジェクト管理 | co-issue, co-project, co-architect |

Non-implementation controller は co-autopilot を spawn しない。
co-architect が「設計 + 実装」を要求された場合: 設計完了 → Issue 起票（co-issue 経由）→ co-autopilot で実装。

### 機械 / LLM の境界

「LLM は判断のために使う。機械的にできることは機械に任せる。」— この原則が全設計判断の根底にある。

**判断基準**: ルールベースで正解が一意に決まる処理は機械化する。コンテキスト依存で複数の妥当な選択肢がある処理は LLM に委ねる。

| 機械がやるべきこと | 実装手段 | LLM に任せてよいこと | 理由 |
|--------------------|----------|----------------------|------|
| 状態管理（JSON read/write） | state-read.sh / state-write.sh | Issue の分解判断 | 分解粒度はコンテキスト依存 |
| ファイル操作（worktree 作成・削除） | worktree-create.sh / worktree-delete.sh | コードレビュー品質 | コード品質の判断は多面的 |
| バリデーション（loom validate） | PostToolUse hook | エラー診断 | 根本原因の特定は推論が必要 |
| 出力スキーマ強制（specialist 共通スキーマ） | JSON Schema + パース | アーキテクチャ決定 | トレードオフの評価が必要 |
| ステップ順序制御（chain-driven） | deps.yaml chains | merge 失敗時の対処判断 | 失敗パターンが多様 |
| フラグ伝搬（統一状態ファイル） | issue-{N}.json / session.json | cross-issue 影響の分析 | ファイル競合の影響度は文脈依存 |
| 型ルール検証（PostToolUse hook） | loom validate / check | パターン検出・知見の抽出 | 有意なパターンの選別は判断 |
| specialist 出力の機械的フィルタ | severity == CRITICAL && confidence >= 80 | PR レビューの最終判断 | WARNING の対処優先度は文脈依存 |
| 依存グラフの循環検出 | plan.yaml 生成時の DAG 検証 | Phase 分割の最適化 | 並列度と依存管理のバランス |
| retry 上限の強制 | retry_count チェック | fix-phase の修正戦略 | 修正方針は問題の性質に依存 |

## Non-Goals

- **技術スタック固有の機能**: Next.js, FastAPI, R/Bioconductor 等のフレームワーク固有操作はコンパニオンプラグインの責務。dev plugin は技術スタックに依存しない汎用ワークフロー（Issue → 実装 → PR → マージ）のみを提供する。tech-stack-detect スクリプトで specialist を選択するが、specialist 自体はコンパニオンプラグインまたは汎用 specialist として提供される
- **loom CLI 本体の機能開発**: deps.yaml パーサー、型システム、validate/audit/chain コマンドは shuu5/loom リポジトリの責務。dev plugin は loom CLI を Open Host Service として消費するのみ
- **AI/LLM の判断を機械化すること**: Issue 分解、コードレビュー品質、エラー診断、merge 失敗時の対処は LLM の判断領域。これらを rule-based に置換しようとしない
- **旧 plugin との後方互換性**: 旧 dev plugin (claude-plugin-dev) のインターフェースとの互換性は維持しない。クリーンな再設計を優先する
