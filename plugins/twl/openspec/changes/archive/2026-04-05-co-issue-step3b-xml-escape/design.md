## Context

`skills/co-issue/SKILL.md` の Step 3b specialist spawn プロンプトでは、`escaped_body`/`escaped_files` は既に `scripts/escape-issue-body.sh`（`& → &amp;, < → &lt;, > → &gt;`）を経由しているが、同一プロンプト内の `related_issues`（他 Issue タイトル/本文）と `deps_yaml_entries`（deps.yaml エントリ）はエスケープなしで `<related_context>` タグに注入されている。

`</related_context>` 等を含む Issue タイトルが渡された場合、XML コンテキスト境界が破壊され、specialist プロンプトに任意コンテキストを注入できる。

## Goals / Non-Goals

**Goals:**

- `related_issues` と `deps_yaml_entries` を `escape-issue-body.sh` でエスケープしてから注入する
- エスケープ済み変数の命名を `escaped_` プレフィックスで統一する
- `<related_context>` タグ内の全変数エスケープルールを SKILL.md に明記する
- `deps.yaml` の co-issue `calls` に `- script: escape-issue-body` を追記する

**Non-Goals:**

- `escape-issue-body.sh` 自体の機能変更
- Step 1.5 の変更（XML injection sink なし）
- specialist agent 側のプロンプトインジェクション耐性強化
- co-issue 以外の skill への適用

## Decisions

### エスケープ位置: FOR ループ内（specialist spawn 直前）

Step 3b の FOR ループ内、specialist spawn の直前に以下を追加する:

```bash
escaped_related_issues=$(echo "$related_issues" | bash scripts/escape-issue-body.sh)
escaped_deps_yaml_entries=$(echo "$deps_yaml_entries" | bash scripts/escape-issue-body.sh)
```

`related_issues` と `deps_yaml_entries` は FOR ループごとに異なる可能性があるため（ループ変数依存）、ループ外よりもループ内での定義が安全。

### 変数参照の一括置換

3 つの specialist spawn（issue-critic, issue-feasibility, worker-codex-reviewer）の `<related_context>` 内の変数参照を `${escaped_related_issues}` / `${escaped_deps_yaml_entries}` に変更する。

### SKILL.md 注記の明文化

既存の注記（「Issue body はユーザー入力由来のため…escape-issue-body.sh を経由してエスケープすること（SHALL）」）を拡張し、「`<related_context>` タグ内に注入する全変数は escape-issue-body.sh を通すこと（SHALL）」を追記する。

## Risks / Trade-offs

- **パフォーマンス**: `escape-issue-body.sh` を 2 回追加呼び出し（シェルプロセス）。入力サイズが数 KB 程度であれば無視できる。
- **後退リスク**: `related_issues` が空文字列の場合、エスケープ後も空文字列のため動作変化なし。
