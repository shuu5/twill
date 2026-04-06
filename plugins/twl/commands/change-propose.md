# OpenSpec 提案（change-propose）

change ディレクトリを作成し全 artifact を一括生成する。CLI フォーマット要件を spec 生成指示に注入する。

## 引数

- `change-name or description`: 変更名またはユーザーの説明
- `--arch-context <text>`: architecture/ コンテキスト（workflow-setup から注入）

## フロー制御（MUST）

### Step 1: 入力解析

**If no clear input provided, ask what they want to build**

Use the **AskUserQuestion tool** (open-ended, no preset options) to ask:
> "What change do you want to work on? Describe what you want to build or fix."

From their description, derive a kebab-case name (e.g., "add user authentication" → `add-user-auth`).

**IMPORTANT**: Do NOT proceed without understanding what the user wants to build.

### Step 2: change ディレクトリ作成
```bash
twl spec new change "<name>"
```
This creates a scaffolded change at `deltaspec/changes/<name>/` with `.deltaspec.yaml`.

### Step 3: artifact ビルド順序取得
```bash
twl spec status --change "<name>" --json
```
Parse the JSON to get:
- `applyRequires`: array of artifact IDs needed before implementation (e.g., `["tasks"]`)
- `artifacts`: list of all artifacts with their status and dependencies

### Step 4: artifact を順次作成（apply-ready になるまで）

Loop through artifacts in dependency order (artifacts with no pending dependencies first):

a. **For each artifact that is `ready` (dependencies satisfied)**:
   - Get instructions:
     ```bash
     twl spec instructions <artifact-id> --change "<name>" --json
     ```
   - The instructions JSON includes:
     - `context`: Project background (constraints for you - do NOT include in output)
     - `rules`: Artifact-specific rules (constraints for you - do NOT include in output)
     - `template`: The structure to use for your output file
     - `instruction`: Schema-specific guidance for this artifact type
     - `outputPath`: Where to write the artifact
     - `dependencies`: Completed artifacts to read for context
   - Read any completed dependency files for context
   - Create the artifact file using `template` as the structure
   - Apply `context` and `rules` as constraints - but do NOT copy them into the file
   - Show brief progress: "Created <artifact-id>"

b. **Continue until all `applyRequires` artifacts are complete**
   - After creating each artifact, re-run `twl spec status --change "<name>" --json`
   - Check if every artifact ID in `applyRequires` has `status: "done"` in the artifacts array
   - Stop when all `applyRequires` artifacts are done

c. **If an artifact requires user input** (unclear context):
   - Use **AskUserQuestion tool** to clarify
   - Then continue with creation

### Step 5: spec 生成時フォーマット要件（MUST）

#### Delta ヘッダー

`## ADDED Requirements` / `## MODIFIED Requirements` / `## REMOVED Requirements` / `## RENAMED Requirements`

#### Requirement プレフィックス

`### Requirement: 要件タイトル`

#### SHALL/MUST キーワード（必須）

各要件の本文に `SHALL` または `MUST` を最低 1 回含める。日本語: `〜しなければならない（SHALL）。`

#### Scenario ブロック（必須）

```markdown
#### Scenario: シナリオ名
- **WHEN** 条件
- **THEN** 期待結果
```

`####`（4 つ）を使用すること。

### Step 6: 最終ステータス表示
```bash
twl spec status --change "<name>"
```

チェックポイント出力:
```
>>> 提案完了: <change-id>
```

**Output**

After completing all artifacts, summarize:
- Change name and location
- List of artifacts created with brief descriptions
- What's ready: "All artifacts created! Ready for implementation."
- Prompt: "Run `/twl:change-apply` or ask me to implement to start working on the tasks."

## Artifact Creation Guidelines

- Follow the `instruction` field from `twl spec instructions` for each artifact type
- The schema defines what each artifact should contain - follow it
- Read dependency artifacts for context before creating new ones
- Use `template` as the structure for your output file - fill in its sections
- **IMPORTANT**: `context` and `rules` are constraints for YOU, not content for the file
  - Do NOT copy `<context>`, `<rules>`, `<project_context>` blocks into the artifact
  - These guide what you write, but should never appear in the output

## 禁止事項（MUST NOT）

- SHALL/MUST なしの要件本文を生成してはならない
- Scenario なしの要件を生成してはならない
- Create ALL artifacts needed for implementation (as defined by schema's `apply.requires`)
- Always read dependency artifacts before creating a new one
- If context is critically unclear, ask the user - but prefer making reasonable decisions to keep momentum
- If a change with that name already exists, ask if user wants to continue it or create a new one
- Verify each artifact file exists after writing before proceeding to next

## チェックポイント（MUST）

`/twl:ac-extract` を Skill tool で自動実行。
