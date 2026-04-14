---
type: composite
tools: [Agent, Bash, Skill, Read]
effort: medium
maxTurns: 30
---
# /twl:issue-spec-review - 1 Issue の specialist 並列レビュー

1 Issue に対して 3 specialist（issue-critic, issue-feasibility, worker-codex-reviewer）を並列 spawn し、構造化 findings を返す。

**機械的保証**: 1回の呼び出しで正確に 1 Issue をレビューする。複数 Issue を受け取ってはならない（MUST NOT）。

## 入力

呼び出し元（co-issue controller）から以下を受け取る:

- `issue_body`: 構造化済み Issue body + 全 comments（Step 3a で `gh_read_issue_full` により取得済み）
- `scope_files`: 変更対象ファイルリスト
- `related_issues`: 関連 Issue 参照
- `deps_yaml_entries`: 関連 deps.yaml エントリ
- `is_quick_candidate`: quick 候補フラグ（boolean）

## フロー（MUST）

### Step 1: エスケープ処理（SHALL）

Issue body はユーザー入力由来のため、`scripts/escape-issue-body.sh` で機械的にエスケープする（LLM への「注意して」は禁止）。

```bash
escaped_body=$(printf '%s\n' "$issue_body" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/escape-issue-body.sh")
escaped_files=$(printf '%s\n' "$scope_files" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/escape-issue-body.sh")
escaped_related_issues=$(printf '%s\n' "$related_issues" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/escape-issue-body.sh")
escaped_deps_yaml_entries=$(printf '%s\n' "$deps_yaml_entries" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/escape-issue-body.sh")
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

### Step 4: specialist 並列 spawn（MUST）

まず manifest からリストを取得し、hook 追跡用ファイルに書き出す:

```bash
MANIFEST_FILE=$(mktemp /tmp/.specialist-manifest-spec-review-XXXXXXXX.txt)
chmod 600 "$MANIFEST_FILE"
CONTEXT_ID=$(basename "$MANIFEST_FILE" .txt)
CONTEXT_ID="${CONTEXT_ID#.specialist-manifest-}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-review-manifest.sh" \
  > "$MANIFEST_FILE"
specialists=$(cat "$MANIFEST_FILE")
```

**manifest の各行に対して Agent tool call を生成すること（MUST）。manifest に含まれる全 specialist を単一メッセージで同時発行した後でのみ Step 5 に進むこと（MUST）。manifest 外の specialist を追加・削除してはならない。**

**出力量制限（#672 対策）**: specialist の findings 出力から **severity: INFO を除外**すること（MUST）。INFO findings は改善提案にすぎず round-loop 判定に不要。CRITICAL + WARNING のみを出力することで Worker の 1 ターン context 飽和を防止する。各 specialist の prompt に以下を追加:

```
<output_constraint>
findings には CRITICAL と WARNING のみ出力すること。INFO（改善提案）は出力しない。
message は 1-2 文に簡潔化すること。
</output_constraint>
```

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

<output_constraint>
findings には CRITICAL と WARNING のみ出力すること。INFO（改善提案）は出力しない。
message は 1-2 文に簡潔化すること。
</output_constraint>

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

<output_constraint>
findings には CRITICAL と WARNING のみ出力すること。INFO（改善提案）は出力しない。
message は 1-2 文に簡潔化すること。
</output_constraint>

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

<output_constraint>
findings には CRITICAL と WARNING のみ出力すること。INFO（改善提案）は出力しない。
message は 1-2 文に簡潔化すること。
</output_constraint>

<related_context>
${escaped_related_issues}
${escaped_deps_yaml_entries}
</related_context>
${quick_tag}")
```

### Step 5: 結果収集・返却（全 specialist 完了後にのみ実行）

Step 4 で spawn した **3 specialist 全てが結果を返すまで** このステップに進んではならない（MUST）。1〜2 個の結果が返っただけで先に進むことは禁止。3 specialist の返却値をそのまま呼び出し元に返す。パースや集約はこのコマンドでは行わない（issue-review-aggregate の責務）。

全 specialist の結果返却後、hook 追跡用一時ファイルを削除する（CONTEXT_ID が利用可能な場合はピンポイントで、そうでなければ glob でクリーンアップ）:

```bash
if [[ -n "${MANIFEST_FILE:-}" && -n "${CONTEXT_ID:-}" ]]; then
  rm -f "$MANIFEST_FILE" \
        "/tmp/.specialist-spawned-${CONTEXT_ID}.txt"
else
  rm -f /tmp/.specialist-manifest-spec-review-*.txt \
        /tmp/.specialist-spawned-spec-review-*.txt
fi
```

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
