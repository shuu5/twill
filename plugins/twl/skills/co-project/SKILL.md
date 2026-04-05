---
name: twl:co-project
description: |
  プロジェクト管理（create / migrate / snapshot）。
  旧 controller-project, controller-project-migrate, controller-project-snapshot,
  controller-plugin を統合。plugin はテンプレートの一種として吸収。

  Use when user: says プロジェクト作りたい/作成したい/新規プロジェクト,
  says 移行したい/テンプレート更新/ガバナンス再適用,
  says スナップショット/テンプレート抽出.
type: controller
effort: medium
tools:
- Agent(worker-structure)
spawnable_by:
- user
---

# co-project

プロジェクト管理の 3 モード統合 controller。Non-implementation controller（chain-driven 不要）。

## Step 0: モード判定

引数またはユーザー入力からモードを判定:

| キーワード | モード |
|-----------|--------|
| `create`, 作成, 新規 | create |
| `migrate`, 移行, アップグレード, テンプレート更新, ガバナンス再適用 | migrate |
| `snapshot`, スナップショット, テンプレート抽出 | snapshot |

判定不能時 → AskUserQuestion で [A] create [B] migrate [C] snapshot を選択。

---

## create モード

### Step 1: 入力確認

- **プロジェクト名**（必須）: 未指定 → AskUserQuestion
- **テンプレートタイプ**（必須）: 未指定 → AskUserQuestion
  - plugin テンプレートを含む任意のタイプが指定可能
- **ルートパス**: `--root` 未指定 → タイプ別デフォルト

### Step 2: プロジェクト作成

`/twl:project-create <name> --type <type> [--root <path>] [--no-github]` を実行。

### Step 2.5: Rich Mode チェック

テンプレートに `manifest.yaml` が存在する場合（Rich Mode）:
1. スタック情報テーブルを表示
2. `containers` セクションがあれば `/twl:container-dependency-check` を実行
3. `post_create` セクションがあれば表示

### Step 3: ガバナンス適用

`/twl:project-governance --path <project-main-dir> --type <type>` を実行。

### Step 3.5: Board ビュー標準設定

`/twl:project-board-configure` を実行。`--no-github` 指定時はスキップ。
不足フィールドが検出された場合はブラウザが開き、ユーザーに設定を案内する。

### Step 4: 完了レポート

プロジェクトパス、タイプ、ガバナンス状況、スタック情報（Rich Mode時）を表示。
次のステップとして `/twl:co-issue` → `/twl:workflow-setup` を案内。

---

## migrate モード

### Step 1: 現在地確認

- `~/projects/` 配下であることを確認
- bare repo / worktree 構造を検出

### Step 2: テンプレート移行

`/twl:project-migrate [--type <type>] [--dry-run]` を実行。
`--dry-run` 指定時は変更内容を表示して終了。

### Step 3: ガバナンス再適用

`/twl:project-governance --path <project-dir> --type <type> --update` を実行。

### Step 4: 完了レポート

移行完了、テンプレート更新、ガバナンス再適用を報告。
コミット提案: `git add -A && git commit -m 'chore: migrate to latest template'`

---

## snapshot モード

### Step 1: 入力確認

- **ソースプロジェクトパス**（必須）: 未指定 → AskUserQuestion
- **テンプレート名** `--as <name>`（必須）: 未指定 → AskUserQuestion（kebab-case）
- テンプレート名衝突時は上書き確認

### Step 2: プロジェクト分析

`/twl:snapshot-analyze <source-path>` を実行。スタック情報、コンテナ依存、ファイル一覧を出力。

### Step 3: Tier 分類

`/twl:snapshot-classify <source-path> --output <classify-result>` を実行。
AI 分析 → ユーザー確認のテーブル形式。

### Step 4: テンプレート生成

`/twl:snapshot-generate <source-path> --as <name> --classify-result <classify-result>` を実行。
manifest.yaml + テンプレートファイルを生成。

### Step 5: 完了レポート

テンプレートパス、Tier 別ファイル数（Tier 4 除外）を表示。
`--type <name>` で create モードから使用可能と案内。

---

## plugin テンプレートについて

旧 controller-plugin は co-project に吸収。plugin は create モードの `--type plugin` として扱う。
plugin の保守は通常ワークフロー（workflow-setup → apply → pr-cycle）+ twl CLI で行う。

## 禁止事項（MUST NOT）

- ガバナンス適用をスキップしてはならない（create/migrate 共通）
- プロジェクト名を推測してはならない（未指定時は必ず質問）
- snapshot モードでソースプロジェクトを変更してはならない（read-only）
