# /twl:project-governance

プロジェクトにガバナンスを適用します（冪等設計）。

## 使用方法

```bash
/twl:project-governance --path <project-dir> --type <type> [--update]
```

## 引数

- `--path <dir>`: プロジェクトのmainディレクトリ（必須）
- `--type <type>`: プロジェクトタイプ（rnaseq/webapp-llm/webapp-hono）
- `--update`: 既存ガバナンスセクションを最新テンプレートで更新

## 実行ロジック（AIへの命令）

### Step 1: カテゴリ解決

| タイプ | カテゴリ |
|--------|---------|
| `rnaseq` | omics |
| `webapp-llm` | webapp |
| `webapp-hono` | webapp-hono |

### Step 2: Hooks 適用

1. Step 1 で解決したカテゴリに対応する Hooks テンプレートを Read:
   - omics → `$HOME/.claude/templates/_hooks/omics.json`
   - webapp → `$HOME/.claude/templates/_hooks/webapp.json`
   - webapp-hono → `$HOME/.claude/templates/_hooks/webapp-hono.json`
2. プロジェクトの `.claude/settings.json` を確認:
   - 存在しない → Hooks テンプレートをそのまま Write
   - 存在する → 既存 Hooks とマージ（既存設定を保持、新規 Hook を追加）

### Step 3: スキーマ scaffold（webapp/webapp-hono のみ）

タイプが `webapp-llm` または `webapp-hono` の場合:

1. `docs/schema/` ディレクトリ存在確認
2. `docs/schema/openapi.yaml` が存在しない → テンプレートからコピー（`{{PROJECT_NAME}}` 置換）
3. `docs/schema/.spectral.yaml` が存在しない → テンプレートからコピー

### Step 4: CLAUDE.md ガバナンスセクション

マーカーベースで管理:

```
<!-- GOVERNANCE-START -->
## ガバナンス（自動適用済み）
...
<!-- GOVERNANCE-END -->
```

#### 初回適用（マーカーなし）

1. `$HOME/.claude/templates/_governance/governance-section.md` を Read
2. CLAUDE.md 末尾に `<!-- GOVERNANCE-START -->` + 内容 + `<!-- GOVERNANCE-END -->` を追記

#### 更新（--update、マーカーあり）

1. `<!-- GOVERNANCE-START -->` と `<!-- GOVERNANCE-END -->` の間を最新テンプレートで置換
2. マーカー外の内容は保護

#### タイプ別スキーマセクション

webapp-llm / webapp-hono の場合、ガバナンスセクションの前にスキーマ管理セクションも管理:

```
<!-- SCHEMA-MGMT-START -->
## スキーマ管理
...
<!-- SCHEMA-MGMT-END -->
```

- テンプレート: `$HOME/.claude/templates/{type}/CLAUDE.md` の `## スキーマ管理` セクション（見出しから次の `##` 見出しまたはファイル末尾まで）
- 同様にマーカーベースで初回追記/更新
- **将来**: スキーマセクションは `_governance/schema-webapp.md` に独立ファイル化予定。現時点では CLAUDE.md テンプレートからの見出しベース抽出で動作する

### Step 5: 結果報告

```
ガバナンス適用完了:
  - Hooks: {category} カテゴリ適用済み
  - スキーマ: {webapp のみ: scaffold 適用済み / N/A}
  - CLAUDE.md: ガバナンスセクション {追記 / 更新}済み
```

## 冪等性

- Hooks: 既存設定を破壊しない（マージ）
- スキーマ: 既存ファイルを上書きしない
- CLAUDE.md: マーカー間のみ更新、マーカー外を保護
