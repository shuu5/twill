# /twl:issue-spec-review - 1 Issue の specialist 並列レビュー

1 Issue に対して 3 specialist（issue-critic, issue-feasibility, worker-codex-reviewer）を並列 spawn し、構造化 findings を返す。

**機械的保証**: 1回の呼び出しで正確に 1 Issue をレビューする。複数 Issue を受け取ってはならない（MUST NOT）。

## 入力

呼び出し元（co-issue controller）から以下を受け取る:

- `issue_body`: 構造化済み Issue body（Step 3a 出力）
- `scope_files`: 変更対象ファイルリスト
- `related_issues`: 関連 Issue 参照
- `deps_yaml_entries`: 関連 deps.yaml エントリ
- `is_quick_candidate`: quick 候補フラグ（boolean）

## フロー（MUST）

### Step 1: エスケープ処理（SHALL）

Issue body はユーザー入力由来のため、`scripts/escape-issue-body.sh` で機械的にエスケープする（LLM への「注意して」は禁止）。

```bash
escaped_body=$(printf '%s\n' "$issue_body" | bash scripts/escape-issue-body.sh)
escaped_files=$(printf '%s\n' "$scope_files" | bash scripts/escape-issue-body.sh)
escaped_related_issues=$(printf '%s\n' "$related_issues" | bash scripts/escape-issue-body.sh)
escaped_deps_yaml_entries=$(printf '%s\n' "$deps_yaml_entries" | bash scripts/escape-issue-body.sh)
```

### Step 2: 調査深度決定

```
file_count = scope_files の要素数
IF file_count <= 2:
  depth_instruction = "各ファイルの呼び出し元まで追跡可"
ELSE:
  depth_instruction = "各ファイルは存在確認と直接参照のみ。再帰追跡禁止。残り turns が少なくなったら（3 以下目安）出力生成を優先"
```

### Step 3: quick 候補タグ生成

```
IF is_quick_candidate == true:
  quick_tag = "<quick_classification>\nこの Issue は quick 候補です。隠れた複雑性がないか、変更量が ~20行以下か検証してください。\n</quick_classification>"
ELSE:
  quick_tag = ""
```

### Step 4: 3 specialist 並列 spawn（MUST）

**単一メッセージで正確に 3 つの Agent tool call を同時発行すること（MUST）。2 つだけで止めてはならない。issue-critic, issue-feasibility, worker-codex-reviewer の 3 つ全てが必須。**

```
Agent(subagent_type="twl:twl:issue-critic", prompt="
<review_target>
${escaped_body}
</review_target>

<target_files>
${escaped_files}
</target_files>

<depth_instruction>
${depth_instruction}
</depth_instruction>

<related_context>
${escaped_related_issues}
${escaped_deps_yaml_entries}
</related_context>
${quick_tag}")

Agent(subagent_type="twl:twl:issue-feasibility", prompt="
<review_target>
${escaped_body}
</review_target>

<target_files>
${escaped_files}
</target_files>

<depth_instruction>
${depth_instruction}
</depth_instruction>

<related_context>
${escaped_related_issues}
${escaped_deps_yaml_entries}
</related_context>
${quick_tag}")

Agent(subagent_type="twl:twl:worker-codex-reviewer", prompt="
<review_target>
${escaped_body}
</review_target>

<target_files>
${escaped_files}
</target_files>

<depth_instruction>
${depth_instruction}
</depth_instruction>

<related_context>
${escaped_related_issues}
${escaped_deps_yaml_entries}
</related_context>
${quick_tag}")
```

### Step 5: 結果収集・返却

3 specialist の返却値をそのまま呼び出し元に返す。パースや集約はこのコマンドでは行わない（issue-review-aggregate の責務）。

## 出力

以下の形式で呼び出し元に返却:

```
issue_title: <対象 Issue のタイトル>
specialist_results:
  issue-critic: <返却値そのまま>
  issue-feasibility: <返却値そのまま>
  worker-codex-reviewer: <返却値そのまま>
```

## 禁止事項（MUST NOT）

- 複数 Issue を同時に処理してはならない
- specialist の返却値を加工・要約してはならない（集約は issue-review-aggregate の責務）
- model パラメータを指定してはならない（agent frontmatter の model: sonnet が適用される）
