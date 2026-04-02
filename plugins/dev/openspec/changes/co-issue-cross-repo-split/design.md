## Context

autopilot Worker は「1 Issue = 1 worktree = 1 リポ」の前提で設計されている。loom-dev-ecosystem は 3 リポ（loom, loom-plugin-dev, loom-plugin-session）で構成され、リポ横断 Issue（例: #108）が発生する。現在の co-issue は単一リポ前提で分解判断を行うため、クロスリポ Issue をそのまま作成してしまい Worker が完全実装できない。

co-issue は 4 Phase 構成（探索→分解→精緻化→作成）の Non-implementation controller。Phase 2（分解判断）にクロスリポ検出を追加し、Phase 4（一括作成）で parent + 子 Issue パターンを生成する。

### 制約

- co-issue は chain-driven 不要（順序は SKILL.md で自然言語定義）
- issue-bulk-create は既に親 Issue + 子 Issue パターンを持つ（Loom リファクタリング用）
- リポ一覧は `gh project` のリンク済みリポジトリから動的取得可能（loom-dev-ecosystem Project #3）
- autopilot 側の設計変更は不要（既存のクロスリポジトリ並列実行 `co-autopilot loom#X lpd#Y session#Z` で対応）

## Goals / Non-Goals

**Goals:**

- Phase 2 でクロスリポ横断を検出し、ユーザーに分割提案する
- 承認時に parent Issue（仕様定義）+ 各リポの子 Issue（実装）を生成する
- 子 Issue の body に parent Issue への参照を含める
- 分割拒否時は従来通り単一 Issue として作成する

**Non-Goals:**

- autopilot Worker のマルチリポ対応（設計上不採用と決定）
- 任意のリポ組み合わせの動的検出（loom-dev-ecosystem の 3 リポをデフォルト対象）
- リポ間の依存順序の自動解析（ユーザーが並列実行を判断）

## Decisions

### D1: クロスリポ検出ロジックの配置

**決定**: co-issue Phase 2（分解判断）の explore-summary.md 読み込み直後に検出ステップを追加。

**理由**: Phase 2 は「スコープの妥当性を判断する場所」であり、クロスリポ検出はスコープ判断の一部。Phase 1（探索）に入れると探索の自由度が下がる。

### D2: リポ一覧の取得方法

**決定**: `gh project` のリンク済みリポジトリから動的取得。現在のリポが属する Project を検索し、その Project にリンクされたリポジトリ一覧を使用する。

**理由**: ハードコードするとリポ追加時にコード変更が必要。Project のリンク済みリポは既に Step 2.3（project-board-status-update）で使用しているパターンであり、一貫性がある。

### D3: 検出方式 — キーワード + ファイルパス

**決定**: explore-summary.md の内容から以下を検出:
1. キーワード: 「全リポ」「3リポ」「各リポ」「クロスリポ」「loom + loom-plugin-dev + loom-plugin-session」等
2. ファイルパス: 複数リポのパスが含まれる場合（repos/loom/..., repos/lpd/... 等）
3. 明示的なリポ名言及: 2つ以上の異なるリポ名が言及されている場合

**理由**: LLM が自然言語で判断するため、厳密なパーサーは不要。キーワードベースで十分な精度が得られる。

### D4: parent + 子 Issue パターン

**決定**: 既存の issue-bulk-create を拡張せず、co-issue Phase 4 内で parent Issue と各リポの子 Issue を順次作成する。

**理由**: issue-bulk-create は Loom リファクタリング専用の構造（Step名、抽出先パス等）を持っており、汎用化するとコストが高い。co-issue Phase 4 が各 Issue の作成を制御しているため、Phase 4 内で対応する方が自然。

### D5: 子 Issue の作成先リポ

**決定**: 子 Issue は各対象リポに `gh issue create -R owner/repo` で作成する。parent Issue は現在のリポに作成する。

**理由**: autopilot が `owner/repo#N` 形式でリポを指定するため、各リポに実体の Issue が必要。

## Risks / Trade-offs

### R1: 検出精度

キーワードベースの検出は偽陽性（単にリポ名を言及しただけ）が発生し得る。ただし AskUserQuestion で確認するため、偽陽性の影響は「不要な確認ダイアログ1回」に留まる。

### R2: リポ間の Issue 番号の不確定性

子 Issue を複数リポに順次作成するため、先に作成した子 Issue の body に後続の子 Issue 番号を含めることができない。parent Issue に全子 Issue のリストを追記する方式（issue-bulk-create の Step 4 と同様）で対応する。

### R3: Project Board 同期の複雑化

子 Issue が複数リポにまたがる場合、各リポの Project Board 同期が必要になる可能性がある。初期実装では parent Issue のみ Board 同期し、子 Issue の Board 同期は各リポでの `/dev:workflow-setup` 実行時に行う。
