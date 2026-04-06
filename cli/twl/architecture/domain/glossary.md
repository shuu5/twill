## Glossary

### deps.yaml トップレベルフィールド

| 用語 | 定義 | Context |
|------|------|---------|
| version | deps.yaml のスキーマバージョン（"1.0", "2.0", "3.0"） | Plugin Structure |
| plugin | プラグイン名。ディレクトリ名から自動推論も可能 | Plugin Structure |
| entry_points | ユーザーがアクセスする起点ファイルのパスリスト | Plugin Structure |
| skills | controller, workflow, reference を含むセクション | Plugin Structure |
| commands | atomic, composite を含むセクション | Plugin Structure |
| agents | specialist を含むセクション | Plugin Structure |
| scripts | script 型コンポーネントを含むセクション | Plugin Structure |
| hooks | イベント駆動のアクション定義（任意） | Plugin Structure |
| chains | v3.0 で追加。ステップ順序定義のセクション | Chain Management |

### deps.yaml コンポーネントフィールド

| 用語 | 定義 | Context |
|------|------|---------|
| type | コンポーネントの型名（controller, workflow, atomic 等） | Type System |
| path | コンポーネントの Markdown ファイルパス（plugin_root 相対） | Plugin Structure |
| description | コンポーネントの説明文 | Plugin Structure |
| spawnable_by | このコンポーネントを呼び出せる型名のリスト | Type System |
| can_spawn | このコンポーネントが呼び出せる型名のリスト | Type System |
| calls | 実際に呼び出すコンポーネント名のリスト（SVG エッジ生成に使用） | Plugin Structure |
| model | AI モデル指定（sonnet, opus, haiku 等）。specialist で使用 | Plugin Structure |
| chain | v3.0: 所属チェーン名 | Chain Management |
| parallel | composite で specialist を並列起動するかどうか | Plugin Structure |
| user-invocable | ユーザーが直接実行可能か（スキルマッチング対象） | Plugin Structure |
| tools | specialist が利用可能なツールのリスト | Plugin Structure |
| skills | specialist が参照する reference のリスト | Plugin Structure |
| checkpoint | チェックポイント機能の有無 | Chain Management |
| checkpoint_ref | チェックポイント参照先の reference 名 | Chain Management |

### types.yaml 型名

| 用語 | 定義 | Context |
|------|------|---------|
| controller | ユーザー入口。workflow/atomic/composite/specialist/reference を spawn 可能 | Type System |
| workflow | 複数ステップの実行フロー。controller または user から呼び出される | Type System |
| atomic | 単一責務の実行単位。reference と script を spawn 可能 | Type System |
| composite | 複数 specialist を束ねる実行単位。specialist と script を spawn 可能 | Type System |
| specialist | 特化された AI エージェント。何も spawn しない leaf ノード | Type System |
| reference | 参照用ドキュメント。何も spawn しない。全型から参照可能 | Type System |
| script | シェルスクリプトのラッパー。何も spawn しない leaf ノード | Type System |

### 検証コマンド

| 用語 | 定義 | 検証範囲 | Context |
|------|------|---------|---------|
| check (`--check`) | ファイル存在確認。deps.yaml の path で指定されたファイルが実在するか検証 | ファイルシステム | Validation |
| validate (`--validate`) | 型ルール検証。can_spawn/spawnable_by の制約が types.yaml と整合するか検証 | deps.yaml + types.yaml | Validation |
| deep-validate (`--deep-validate`) | 深層検証。frontmatter/body の整合性、controller bloat、reference 配置、tools 一貫性を検証 | deps.yaml + 実ファイル内容 | Validation |
| audit (`--audit`) | TWiLL 準拠度監査。5セクション（Structure, Dependency, Content, Chain, Metrics）の総合レポートを生成 | 全体 | Validation |

### Spec Management 用語

| 用語 | 定義 | Context |
|------|------|---------|
| Change | deltaspec/changes/<name>/ に対応する変更単位。提案から実装タスクまでの成果物群を管理 | Spec Management |
| Artifact | Change 内の成果物（proposal, design, specs, tasks）。依存関係と完了状態を持つ | Spec Management |
| ArtifactStatus | Artifact の状態。ready（作成可能）, blocked（依存未完了）, done（完了） | Spec Management |
| delta header | spec ファイル内の変更種別ヘッダ（ADDED/MODIFIED/REMOVED/RENAMED Requirements） | Spec Management |
| deltaspec root | deltaspec/ ディレクトリを持つプロジェクトルート。cwd から上方探索で発見 | Spec Management |
| spec-driven | 標準スキーマ。proposal → design, specs → tasks の依存グラフで成果物を管理 | Spec Management |
| Instruction | Artifact 作成のための指示テキスト・テンプレート・依存情報の構造化出力 | Spec Management |

### Autopilot 用語

| 用語 | 定義 | Context |
|------|------|---------|
| State | `.autopilot/` 配下の JSON ファイルで管理される issue/session の状態 | Autopilot |
| State Transition | ステートマシン遷移（running → merge-ready → done/failed）。不正な遷移は例外 | Autopilot |
| Orchestrator | Phase 単位の並列セッション管理。ポーリングループで worker を監視 | Autopilot |
| MergeGate | PR マージの実行・拒否判定。issue 状態と PR レビュー結果から評価 | Autopilot |
| Checkpoint | specialist の findings を step 単位で PASS/WARN/FAIL として永続化 | Autopilot |
| Plan | Issue 依存グラフから生成する実装計画（plan.yaml）。Phase 分割と並列グルーピング | Autopilot |
| Launcher | tmux window の作成と Claude Code セッション起動の制御 | Autopilot |
| Worktree | git worktree の作成・削除・一覧取得 | Autopilot |

### その他の用語

| 用語 | 定義 | Context |
|------|------|---------|
| deps.yaml | プラグイン構造の SSOT。全コンポーネント定義を含む | Plugin Structure |
| types.yaml | 型ルールの SSOT。can_spawn/spawnable_by を定義 | Type System |
| Component | プラグインの構成単位（.md ファイル） | Plugin Structure |
| Chain | v3.0 のステップ順序定義。deps.yaml の chains セクション | Chain Management |
| Template A | chain generate が生成するチェックポイントセクション | Chain Management |
| Template B | chain generate が生成する called-by frontmatter | Chain Management |
| SSOT | Single Source of Truth。唯一の正しい情報源 | (cross-cutting) |
| orphan | どのコンポーネントからも参照されない孤立ノード | Refactoring |
| dead component | entry_points から到達不能なコンポーネント | Refactoring |
