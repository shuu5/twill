# Project Management

## Responsibility

プロジェクトの作成、移行、スナップショット、プラグイン管理。
bare repo + worktree 構造の初期化・検証、テンプレートとガバナンスの適用、Project Board の管理を担う。

## Key Entities

### Project
管理対象プロジェクト。bare repo + worktree 構造で管理される。

### Template
プロジェクトテンプレート。種類（webapp, omics, plugin 等）と Tier 分類を持つ。

| フィールド | 型 | 説明 |
|---|---|---|
| name | string | テンプレート名 |
| type | string | 種類（webapp, omics, plugin 等） |
| tier | string | Tier 分類（AI 分析 -> ユーザー確認で決定） |

### Manifest (manifest.yaml)
テンプレートメタデータ。スタック、ガバナンスルールを定義する。

| フィールド | 型 | 説明 |
|---|---|---|
| stack | object | 技術スタック定義 |
| governance | Governance | ガバナンスルール |

### ProjectBoard
GitHub Projects V2 のボード。プロジェクトの Issue ステータスを管理する SSOT。

### Governance
プロジェクトのガバナンスルールセット。

| 構成要素 | 説明 |
|---|---|
| Hooks | PostToolUse 等のフック定義 |
| Schema scaffold | スキーマの初期構造 |
| CLAUDE.md 拡張 | プロジェクト固有の CLAUDE.md ルール |

## Key Workflows

### project-create フロー

```mermaid
flowchart TD
    A[bare repo 初期化] --> B[テンプレート適用]
    B --> C[ガバナンス適用]
    C --> D[Board 自動作成]
    D --> E[Project V2 リンク]
```

### project-migrate フロー

```mermaid
flowchart TD
    A[最新テンプレート差分検出] --> B[差分適用]
    B --> C[ガバナンス再適用]
    C --> D[検証]
```

### snapshot フロー

```mermaid
flowchart TD
    A[analyze: ファイルスキャン] --> B[classify: Tier 分類]
    B --> C[AI 分析]
    C --> D[ユーザー確認]
    D --> E[generate: manifest + テンプレート生成]
```

## Constraints

### Bare repo 正規構造

全プロジェクトで bare repo 必須。branch モード廃止。

```
project-name/
  .bare/                 # git データ
  main/                  # main worktree（セッション起動場所）
    .git (file)          # -> .bare を指す
  worktrees/{feat,fix,docs}/
  autopilot-plan.yaml
```

### 検証条件（セッション開始時チェック）

| # | 条件 | 失敗時の対処 |
|---|------|-------------|
| 1 | `.bare/` が存在する（`.git/` ディレクトリではない） | co-project migrate で変換 |
| 2 | `main/.git` がファイル（ディレクトリではない）で `.bare` を指す | 構造破損。手動修復が必要 |
| 3 | CWD が `main/` 配下である（worktrees/ 配下は危険） | Pilot に警告し、main/ への移動を要求 |

### Project Board = SSOT

- 全プロジェクトで一律有効。autopilot が Status=Todo をクエリして対象選択
- project-create が自動で Project V2 作成+リンク
- 二層構造: ローカル状態ファイル（即時性）+ Project Board（永続化・可視化）

### 同期ルール

- **同期タイミング**: issue-{N}.json の status が `done` に遷移した時点でローカル -> Board 同期
- **同期失敗時**: WARNING ログ出力、次回セッション開始時にリトライ。Board 同期失敗は autopilot をブロックしない
- **実装の分散先**:
  - co-project: create 時の Board 自動作成
  - co-autopilot: Issue 選択時の Board クエリ、完了時の Board 更新

## Rules

- **Non-implementation controller**: co-project はコード変更を伴わない場合がある（create/migrate は構成変更のみ）。chain-driven 不要
- **co-project 引数ルーティング**: create / migrate / snapshot の 3 モード。旧 controller-project, controller-project-migrate, controller-project-snapshot を統合
- **plugin は co-project のテンプレートの一種**: 旧 controller-plugin を吸収。保守は通常ワークフロー + loom CLI

## Component Mapping

本 Context が担う controller/workflow/command の対応:

| 種別 | コンポーネント | 役割 |
|------|--------------|------|
| **controller** | co-project | プロジェクト管理（create / migrate / snapshot） |
| **atomic** | project-create | bare repo + worktree + テンプレート初期化 |
| **atomic** | project-migrate | 最新テンプレート移行 + ガバナンス再適用 |
| **atomic** | project-governance | Hooks + スキーマ scaffold + CLAUDE.md 拡張 |
| **atomic** | container-dependency-check | コンテナ依存と実状態の照合 |
| **atomic** | snapshot-analyze | ファイルスキャン + スタック自動検出 |
| **atomic** | snapshot-classify | AI Tier 分類 + ユーザー確認 |
| **atomic** | snapshot-generate | manifest.yaml + テンプレートファイル生成 |
| **atomic** | setup-crg | code-review-graph MCP セットアップ |
| **atomic** | crg-auto-build | CRG グラフ自動ビルド |
| **script** | branch-create.sh | ブランチ作成（standard repo 用） |

## Dependencies

- **Shared Kernel -> Autopilot**: bare repo + worktree 構造を共有
- **Downstream -> Issue Management**: Board ステータス更新
