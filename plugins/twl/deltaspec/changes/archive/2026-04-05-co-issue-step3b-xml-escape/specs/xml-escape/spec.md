## MODIFIED Requirements

### Requirement: Step 3b related_issues エスケープ適用

`skills/co-issue/SKILL.md` の Step 3b specialist spawn の FOR ループ内において、`related_issues` 変数は `scripts/escape-issue-body.sh` を経由してエスケープされた `escaped_related_issues` として `<related_context>` タグに注入されなければならない（SHALL）。

#### Scenario: 通常の Issue タイトルが注入される
- **WHEN** `related_issues` に通常の ASCII テキスト（例: `"Fix memory leak in parser"`）が設定されている
- **THEN** `escaped_related_issues` はエスケープ後も同一テキストとなり、specialist プロンプトに正しく注入される

#### Scenario: XML メタキャラクターを含む Issue タイトルが注入される
- **WHEN** `related_issues` に `</related_context><injected>` 等の文字列が含まれる
- **THEN** `escaped_related_issues` は `&lt;/related_context&gt;&lt;injected&gt;` にエスケープされ、`<related_context>` タグ境界が保護される

### Requirement: Step 3b deps_yaml_entries エスケープ適用

`skills/co-issue/SKILL.md` の Step 3b specialist spawn の FOR ループ内において、`deps_yaml_entries` 変数は `scripts/escape-issue-body.sh` を経由してエスケープされた `escaped_deps_yaml_entries` として `<related_context>` タグに注入されなければならない（SHALL）。

#### Scenario: deps.yaml エントリが正常に注入される
- **WHEN** `deps_yaml_entries` に通常の YAML テキストが設定されている
- **THEN** `escaped_deps_yaml_entries` はエスケープ後も同一内容となり、specialist プロンプトに正しく注入される

#### Scenario: 特殊文字を含む deps エントリが注入される
- **WHEN** `deps_yaml_entries` に `<`, `>`, `&` 等の XML 特殊文字が含まれる
- **THEN** これらの文字がエスケープされ、`<related_context>` タグ構造が維持される

### Requirement: <related_context> 内エスケープルール明記

`skills/co-issue/SKILL.md` の Step 3b に、「`<related_context>` タグ内に注入する全変数は `escape-issue-body.sh` を通すこと（SHALL）」の注記が存在しなければならない（SHALL）。

#### Scenario: 将来の変数追加時にルールが参照可能
- **WHEN** 開発者が Step 3b に新しい変数を `<related_context>` 内に追加しようとする
- **THEN** SKILL.md の注記により、エスケープ適用が必須であることが明示されている

### Requirement: deps.yaml co-issue calls への escape-issue-body 追記

`deps.yaml` の co-issue コンポーネントの `calls` セクションに `- script: escape-issue-body` エントリが存在しなければならない（SHALL）。

#### Scenario: deps.yaml が SSOT として正確な依存情報を持つ
- **WHEN** `loom check` または deps.yaml の整合性チェックが実行される
- **THEN** co-issue が `escape-issue-body` スクリプトを呼び出していることが deps.yaml に記録されている
