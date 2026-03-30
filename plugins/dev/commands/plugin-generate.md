# generate: プラグインファイル一式生成

## 目的
design で確定した設計に基づき、プラグインのファイル一式を生成する。

## 手順

### 1. ディレクトリ構造の作成
```bash
mkdir -p ~/ubuntu-note-system/claude/plugins/t-{name}/{.claude-plugin,skills,commands,agents,scripts,docs}
```

### 2. plugin.json の生成
```json
{
  "name": "t-{name}",
  "version": "1.0.0",
  "description": "{description}",
  "author": { "name": "{author}" },
  "keywords": ["agent-teams", ...]
}
```

### 3. deps.yaml の生成
design ステップで確定した deps.yaml を書き出し。

### 4. コンポーネントファイルの生成
ref-types を参照して各型のテンプレートに従い生成:

#### team-controller (skills/controller-{purpose}/SKILL.md)
- **命名**: `controller-{purpose}`（purpose はワークフローの目的を示す具体名）
- frontmatter: name (`t-{plugin}:controller-{purpose}`), description（トリガーフレーズを含める）
- TeamCreate/TeamDelete のフロー
- 本体: ワークフロー実行ロジックのみ（ルーティングテーブル不要）

**生成ガード（MUST）**:
- 本文 ~80行以内: ステップは名前付きコンポーネントへの委譲指示のみ
- 3行以上のインライン実装 → atomic に抽出して生成
- ドキュメント的セクション → reference に抽出して生成
- reference の calls は controller 自身が参照する場合のみ（下流 atomic 用は atomic に宣言）

#### controller（非AT）エントリーポイント (skills/controller-{purpose}/SKILL.md)
- ATが不要なワークフローに使用
- frontmatter: name (`t-{plugin}:controller-{purpose}`), description（トリガーフレーズを含める）
- 本体: ワークフロー実行ロジック（TeamCreate/Delete なし）
- deps.yaml: `can_spawn: [specialist]` + `calls` に spawn する agent を全て列挙

**生成ガード（MUST）**: team-controller と同じ（~80行、インライン実装禁止、reference 配置ルール準拠）

#### team-workflow (skills/{name}/SKILL.md)
- frontmatter: name, description, user-invocable: false
- フェーズ遷移ロジック

#### team-phase (commands/{name}.md)
- frontmatter: allowed-tools: Task, SendMessage
- **冒頭に「AT 実行パターン」セクションを必ず含める**:
  - controller (lead session) が直接実行する指示書であることを明記
  - Task tool に `team_name` パラメータを必ず指定する指示
  - サブエージェント起動（team_name なし）の禁止を明記
- worker 起動時の Task tool 呼び出し例を `team_name` 付きで記載
- worker起動リスト、結果統合ロジック

#### team-worker (agents/{name}.md)
- frontmatter: tools リスト
- 完結したタスク指示（5原則準拠）

#### allowed-tools / tools 生成ルール（全コンポーネント共通）
- 本文で `mcp__xxx__yyy` を使用する場合、frontmatter に必ず宣言
- 本文で使用しないツールは frontmatter に含めない（Read, Write 等の汎用ツールは除く）

#### atomic (commands/{name}.md)
- 単一タスクの実行ロジック

#### reference (skills/{name}/SKILL.md)
- 知識提供コンテンツ

### 5. Context Snapshot + Session Isolation インフラ（該当時）

design のパターン選択で Context Snapshot が必要と判断された場合:

#### 5a. Session Initialization（controller に追加）
- glob で既存セッション検索
- session_id 生成（`uuidgen | cut -c1-8`）
- snapshot_dir: `/tmp/t-{plugin}-{workflow}[-{target}]-{session_id}/`
- team_name: `{base}-{session_id}`
- session-info.json Write
- 古い完了/放棄セッションの cleanup

#### 5b. Compaction Recovery（controller に追加、5ステップ以上時）
- 復帰プロトコル: session-info.json + team-state.json 読み込み → 状態別分岐
- 冪等性ルール: 出力 snapshot ファイルが存在し内容がある場合、そのステップはスキップ

#### 5c. workers/ サブディレクトリ
- snapshot_dir に `workers/` を追加
- 各 team-phase に team-state.json 管理指示（初期化、状態遷移、完了更新）

#### 5d. Worker Dual-Output
- team-worker の tools に Write を追加（deps.yaml）
- worker agent ファイルに Dual-Output 報告セクションを記載
- 結果を `{snapshot_dir}/workers/{name}.md` に Write + SendMessage

### 6. Subagent Delegation（該当時）
design のパターン選択で Subagent Delegation が必要と判断された場合:
- specialist agent ファイルを生成
- controller の該当ステップに Task tool 委任指示を追記
- deps.yaml に以下を追加:
  - specialist の `spawnable_by: [controller]`（型制約）
  - controller の `can_spawn` に `specialist` を追加（型制約）
  - **controller の `calls` に `- agent: {specialist名}` を追加**（SVG エッジ生成に必須）

### 7. ハイブリッド構成（該当時）
1プラグイン内に AT と非AT の controller が混在する場合:
- AT が必要な controller は team-controller 型で生成
- AT 不要な controller は従来 controller 型で生成
- deps.yaml に混在構成を正しく記述

### 8. README.md の生成
既存プラグインの標準パターンに従い README を生成:
```markdown
# t-{name}

{description}

## エントリーポイント

| コマンド | 用途 |
|---------|------|
| `/t-{name}:controller-{purpose1}` | {説明1} |
| `/t-{name}:controller-{purpose2}` | {説明2} |

## アーキテクチャ

### コンポーネント構成（{N}）
- **X controllers**: {一覧}
- **Y references**: {一覧}
- **Z commands**: {一覧}
- **W agents**: {一覧}

## 依存関係

<!-- DEPS-GRAPH-START -->
![Dependency Graph](./docs/deps.svg)
<!-- DEPS-GRAPH-END -->

### コントローラー別

<!-- DEPS-SUBGRAPHS-START -->
<!-- DEPS-SUBGRAPHS-END -->

## インストール

\```bash
claude plugin add ~/ubuntu-note-system/claude/plugins/t-{name}
\```

## 検証

\```bash
cd ~/ubuntu-note-system/claude/plugins/t-{name}
loom check
loom validate
loom tree
\```
```

**必須セクション**: エントリーポイント、アーキテクチャ（構成）、依存関係（マーカー付き）、インストール、検証

### 9. SVG 依存関係図の生成
deps.yaml から全体図 + コントローラー別分離図を生成:
```bash
cd ~/ubuntu-note-system/claude/plugins/t-{name}
loom update-readme
```
- 全体 SVG: `docs/deps.svg`
- コントローラー別 SVG: `docs/deps-{controller-name}.svg`
- README にマーカー内 SVG 参照を自動挿入

### 10. orphan チェック（生成後検証）
```bash
loom orphans
```
- 生成直後に orphan がないことを確認
- orphan がある場合: deps.yaml の calls を再確認し修正

### 11. deep-validate チェック（生成品質検証）
```bash
loom audit
```
- controller-bloat / ref-placement / tools-mismatch を検証
- 問題がある場合: 該当ファイルを即座に修正してから完了

## 出力
生成されたファイルの一覧を表示。
