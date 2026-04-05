## Why

`co-issue` の Step 3b specialist spawn プロンプトにおいて、ユーザー入力由来の変数 `related_issues` と `deps_yaml_entries` が XML エスケープされずに `<related_context>` タグ内に注入されており、プロンプトインジェクションのベクターとなっている。既存の `escape-issue-body.sh` をこれらの変数に適用してセキュリティホールを閉じる。

## What Changes

- `skills/co-issue/SKILL.md` Step 3b（L172-174）: specialist spawn の FOR ループ内で `related_issues` と `deps_yaml_entries` に `escape-issue-body.sh` を適用する指示を追加
- エスケープ済み変数の命名規則を `escaped_` プレフィックスに統一（`escaped_related_issues`, `escaped_deps_yaml_entries`）
- `<related_context>` タグ内の全変数エスケープルールを SKILL.md Step 3b に明記
- `deps.yaml` の co-issue `calls` セクションに `- script: escape-issue-body` を追加（既に使用中だが未記載）

## Capabilities

### New Capabilities

なし（セキュリティ修正のみ）

### Modified Capabilities

- **co-issue Step 3b プロンプト生成**: `related_issues` と `deps_yaml_entries` がエスケープ済みで `<related_context>` タグに注入される。`</related_context>` 等の XML メタキャラクターを含む Issue タイトル/本文が渡されても、タグ境界を破壊しない。

## Impact

- **`skills/co-issue/SKILL.md`**: Step 3b（L172-174 付近）のエスケープ追加・変数名変更
- **`deps.yaml`**: co-issue の calls セクション（1 行追加）
- **ランタイム動作**: 正常系（通常のタイトル・本文）に変化なし。特殊文字を含む入力のみエスケープが適用される
