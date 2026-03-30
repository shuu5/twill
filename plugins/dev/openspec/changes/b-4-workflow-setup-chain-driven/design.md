## Context

loom-plugin-dev は旧 dev plugin の後継として新規構築中。deps.yaml v3.0 の chains セクションで宣言的にワークフローステップを管理する chain-driven パターンを採用する。

現行 workflow-setup（旧 plugin）は 9 ステップ構成で、約 65% が機械的ルーティング。loom CLI の chain 機能（loom#13 で実装済み）を活用し、ステップ順序を deps.yaml で宣言、SKILL.md をドメインルールのみに縮小する。

chain の仕組み:
- deps.yaml `chains` セクション: chain 名、type（A: workflow+atomic / B: atomic+composite）、steps リスト
- 各コンポーネント: `chain` フィールド（所属 chain）、`step_in`（親と step 番号）、`calls`（呼び出し先と step 番号）
- `loom chain generate`: チェックポイントテンプレート・called-by 宣言を自動生成
- `loom chain validate`: 双方向参照整合性を検証

既存 deps.yaml にはまだ chains セクションがない。B-4 が最初の chain 定義となる。

## Goals / Non-Goals

**Goals:**

- deps.yaml に setup chain を定義し、chain-driven パターンの最初の実践例を確立する
- workflow-setup SKILL.md を現行比 50%+ トークン削減する
- chain に参加するコンポーネントを deps.yaml に atomic として登録する
- `loom chain validate` が pass する状態を達成する

**Non-Goals:**

- 他ワークフロー（pr-cycle, autopilot 等）の chain 化（後続 Issue）
- loom CLI 自体の機能拡張
- 現行 workflow-setup の動作変更（chain 化は内部構造の変更であり、外部振る舞いは同一）

## Decisions

### D1: Chain type の選択

setup chain は Type A（workflow + atomic）を採用する。

理由: setup chain の参加者は workflow-setup（workflow）と init, worktree-create 等（atomic）で構成される。specialist や composite は参加しないため、Type A の制約が適切。

### D2: Chain ステップの粒度

以下の 7 ステップを chain に登録する:

| Step | コンポーネント | 型 | 説明 |
|------|--------------|------|------|
| 1 | init | atomic | 状態判定 |
| 2 | worktree-create | atomic | worktree 作成 |
| 2.3 | project-board-status-update | atomic | Board Status 更新 |
| 2.4 | crg-auto-build | atomic | CRG グラフビルド |
| 3 | opsx-propose | atomic | OpenSpec 提案 |
| 3.5 | ac-extract | atomic | AC 抽出 |
| 4 | workflow-test-ready | workflow | テスト準備 |

Step 番号は現行 SKILL.md のステップ番号を踏襲し、chain 内の順序整合性を維持する。

### D3: SKILL.md に残すドメインルール

chain で表現できない以下のロジックのみ SKILL.md に残す:

1. **arch-ref コンテキスト抽出**: Issue body/comments から `<!-- arch-ref-start -->` タグを解析し architecture/ ファイルを読み取る（セマンティック処理）
2. **OpenSpec 分岐条件**: init の `recommended_action` に基づく propose/apply/direct の判定ルール
3. **引数解析ルール**: `--auto`, `--auto-merge`, `#N` の解析とフラグ設定
4. **autopilot-first 前提**: `--auto`/`--auto-merge` フラグ透過を廃止し、autopilot セッション前提で簡素化

### D4: 新規コンポーネント登録

以下を deps.yaml の commands セクションに atomic として追加する:

| コンポーネント | パス | 説明 |
|--------------|------|------|
| init | commands/init.md | 開発状態判定 |
| worktree-create | commands/worktree-create.md | worktree 作成 |
| worktree-delete | commands/worktree-delete.md | worktree 削除 |
| worktree-list | commands/worktree-list.md | worktree 一覧 |
| project-board-status-update | commands/project-board-status-update.md | Board Status 更新 |
| crg-auto-build | commands/crg-auto-build.md | CRG グラフビルド |
| opsx-propose | commands/opsx-propose.md | OpenSpec 提案ラッパー |
| opsx-apply | commands/opsx-apply.md | OpenSpec 実装ラッパー |
| opsx-archive | commands/opsx-archive.md | OpenSpec アーカイブ |
| ac-extract | commands/ac-extract.md | AC 抽出 |
| workflow-test-ready | skills/workflow-test-ready/SKILL.md | テスト準備ワークフロー |

既存の workflow-setup は skills セクションに workflow 型として登録する。

### D5: COMMAND.md の内容

chain 参加コンポーネントの COMMAND.md は、旧 plugin の対応 SKILL.md/COMMAND.md からドメインロジックを移植する。chain generate で生成される called-by 宣言とチェックポイントは `--write` で自動挿入される。

## Risks / Trade-offs

### R1: loom chain generate の可用性

`loom chain generate` は loom#13 で実装済みだが、`--check` / `--all` は loom#30 で未完了。初回は `loom chain generate setup --write` で手動生成し、loom#30 完了後に `--check` で乖離検出を有効化する。

**軽減策**: 初回は手動 `--write` で十分。`--check` がなくても chain 自体は正常に機能する。

### R2: Step 番号の小数点

現行の Step 2.3, 2.5, 3.5 等は小数点を含む。loom chain validate のステップ順序検証は昇順のみ要求するため、小数点 step は技術的に問題ない。

**軽減策**: loom の step 値は文字列型であり、数値比較で昇順が保証される。

### R3: arch-ref 抽出の chain 外配置

arch-ref コンテキスト抽出（Step 2.5）は chain のステップとして登録せず、SKILL.md のドメインルールに残す。これにより chain の純粋性は維持されるが、ステップの全体像が deps.yaml だけでは把握できない。

**軽減策**: SKILL.md の冒頭に chain ライフサイクルテーブルと SKILL.md 固有ステップを並記し、全体像を明示する。
