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
- frontmatter: `name` (`t-{plugin}:controller-{purpose}`), `description`（トリガーフレーズ含む）
- TeamCreate/TeamDelete のフロー + ワークフロー実行ロジック（ルーティングテーブル不要）
- **生成ガード（MUST）**: 本文 ~80行以内。ステップは委譲指示のみ。3行以上のインライン実装 → atomic 抽出。ドキュメント的セクション → reference 抽出。reference の calls は controller 自身が参照する場合のみ。

#### controller（非AT）(skills/controller-{purpose}/SKILL.md)
- TeamCreate/Delete なし。deps.yaml: `can_spawn: [specialist]` + `calls` に spawn する全 agent を列挙。
- **生成ガード（MUST）**: team-controller と同じ。

#### team-workflow (skills/{name}/SKILL.md)
- frontmatter: `user-invocable: false`。本体: フェーズ遷移ロジック。

#### team-phase (commands/{name}.md)
- frontmatter: `allowed-tools: Task, SendMessage`
- 冒頭に「AT 実行パターン」セクション必須: lead session が直接実行する指示書であることを明記、`team_name` 付き Task tool 呼び出し例、サブエージェント起動（team_name なし）禁止を明記。

#### team-worker (agents/{name}.md)
- frontmatter: tools リスト。本体: 完結したタスク指示（5原則準拠）。

#### allowed-tools / tools 生成ルール（全コンポーネント共通）
- `mcp__xxx__yyy` を使用する場合 frontmatter に必ず宣言。使用しないツールは含めない。

#### atomic (commands/{name}.md) / reference (skills/{name}/SKILL.md)
- atomic: 単一タスクの実行ロジック。reference: 知識提供コンテンツ。

### 5. Context Snapshot + Session Isolation インフラ（該当時）

design で Context Snapshot が必要と判断された場合:

- **5a. Session Initialization**: glob で既存セッション検索、`session_id=$(uuidgen | cut -c1-8)` 生成、`snapshot_dir=/tmp/t-{plugin}-{workflow}-{session_id}/`・`team_name={base}-{session_id}`・session-info.json を controller に追加、古いセッションの cleanup。
- **5b. Compaction Recovery**（5ステップ以上時）: session-info.json + team-state.json 読み込み → 状態別分岐、冪等性ルール（出力ファイル既存時スキップ）を追加。
- **5c. workers/ サブディレクトリ**: snapshot_dir に `workers/` を追加、各 team-phase に team-state.json 管理指示。
- **5d. Worker Dual-Output**: team-worker の tools に Write 追加（deps.yaml）、結果を `{snapshot_dir}/workers/{name}.md` に Write + SendMessage。

### 6. Subagent Delegation（該当時）

- specialist agent ファイルを生成
- controller の該当ステップに Task tool 委任指示を追記
- deps.yaml に `spawnable_by`, `can_spawn`, `calls` を追加（SVG エッジ生成に必須）

### 7. ハイブリッド構成（該当時）

AT が必要な controller は team-controller 型、AT 不要な controller は従来 controller 型で生成。deps.yaml に混在構成を正しく記述。

### 8. README.md の生成

既存プラグインの標準パターンに従い生成。**必須セクション**: エントリーポイント（コマンド一覧表）、アーキテクチャ（コンポーネント構成）、依存関係（`<!-- DEPS-GRAPH-START -->` マーカー付き）、インストール、検証。

### 9. SVG 依存関係図の生成

`twl update-readme` を実行。全体 SVG（`docs/deps.svg`）+ コントローラー別 SVG（`docs/deps-{name}.svg`）を生成し README のマーカー内に自動挿入。

### 10. orphan チェック（生成後検証）

`twl orphans` を実行。orphan がある場合は deps.yaml の calls を再確認し修正。

### 11. deep-validate チェック（生成品質検証）

`twl audit` を実行。controller-bloat / ref-placement / tools-mismatch を検証。問題があれば即座に修正してから完了。

## 出力
生成されたファイルの一覧を表示。
