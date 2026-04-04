## 1. SKILL.md Step 3b エスケープ追加

- [x] 1.1 Step 3b の FOR ループ内（specialist spawn 直前）に `escaped_related_issues=$(echo "$related_issues" | bash scripts/escape-issue-body.sh)` を追加
- [x] 1.2 Step 3b の FOR ループ内（specialist spawn 直前）に `escaped_deps_yaml_entries=$(echo "$deps_yaml_entries" | bash scripts/escape-issue-body.sh)` を追加
- [x] 1.3 issue-critic / issue-feasibility / worker-codex-reviewer の 3 specialist spawn 内の `${related_issues}` を `${escaped_related_issues}` に置換
- [x] 1.4 issue-critic / issue-feasibility / worker-codex-reviewer の 3 specialist spawn 内の `${deps_yaml_entries}` を `${escaped_deps_yaml_entries}` に置換

## 2. SKILL.md 注記追加

- [x] 2.1 Step 3b の既存エスケープ注記（「escape-issue-body.sh を経由してエスケープすること（SHALL）」）に「`<related_context>` タグ内に注入する全変数は escape-issue-body.sh を通すこと（SHALL）」を追記

## 3. deps.yaml 更新

- [x] 3.1 `deps.yaml` の co-issue コンポーネントの `calls` セクションに `- script: escape-issue-body` を追加

## 4. 検証

- [x] 4.1 `loom check` を実行し、deps.yaml 整合性エラーがないことを確認
- [x] 4.2 正常系確認: Step 3b に通常の Issue タイトルが渡されたとき、エスケープ後テキストが同一であることをコードレビューで確認
- [x] 4.3 攻撃文字列確認: `</related_context>` を含む文字列が `&lt;/related_context&gt;` にエスケープされることを `echo "x</y>" | bash scripts/escape-issue-body.sh` で確認
