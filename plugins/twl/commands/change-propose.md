---
type: atomic
tools: [AskUserQuestion, Bash, Read, Skill]
effort: medium
maxTurns: 30
---
# DeltaSpec 提案（change-propose）

change ディレクトリを作成し全 artifact を一括生成する。CLI フォーマット要件を spec 生成指示に注入する。

## 引数

- `change-name or description`: 変更名またはユーザーの説明
- `--arch-context <text>`: architecture/ コンテキスト（workflow-setup から注入）

## フロー制御（MUST）

### Step 0: auto_init チェック（MUST）

state の `mode` フィールドと deltaspec root の有効性を確認して auto_init を判定する:

```bash
# mode 取得
MODE=$(python3 -m twl.autopilot.state read --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "<ISSUE_NUM>" --field mode 2>/dev/null || echo "")
# cwd から有効な nested deltaspec root が参照できるか確認
# 注意: deltaspec/ ディレクトリが存在しても nested root（config.yaml）がなければ未初期化扱い
DELTASPEC_EXISTS=$(test -f deltaspec/config.yaml && echo "true" || echo "false")
```

**`MODE == "propose"` かつ `DELTASPEC_EXISTS == "false"`（cwd から有効な nested deltaspec root が参照できない）の場合（auto_init）**:
1. change-id を `issue-<ISSUE_NUM>` として確定する（例: Issue 番号 339 → `issue-339`）
2. `deltaspec/` を先行作成:
   ```bash
   mkdir -p deltaspec/
   ```
3. 既存 change との衝突チェック: `deltaspec/changes/issue-<N>/` が存在する場合は **AskUserQuestion tool** で「既存の change `issue-<N>` が見つかりました。続行しますか？それとも新しく作成しますか？」と確認してから進む
4. change ディレクトリを作成:
   ```bash
   twl spec new "issue-<N>"
   # twl spec new が自動補完する（issue 番号・name・status）
   ```
5. **Step 1 をスキップして Step 3 へ進む**

**それ以外の場合**: Step 1 へ進む。

### Step 1: 入力解析

**明確な入力がない場合、何を作りたいか質問する**

**AskUserQuestion tool**（自由入力、プリセット選択肢なし）で以下を質問:
> 「どのような変更に取り組みますか？作りたいもの・修正したいことを説明してください。」

説明からケバブケース名を導出する（例: 「ユーザー認証の追加」→ `add-user-auth`）。

**重要**: ユーザーが何を作りたいか理解するまで先に進んではならない。

### Step 2: change ディレクトリ作成
```bash
twl spec new "<name>"
```
`deltaspec/changes/<name>/` に `.deltaspec.yaml` 付きのスキャフォールドが作成される。

### Step 3: artifact ビルド順序取得
```bash
twl spec status --change "<name>" --json
```
JSON をパースして以下を取得:
- `applyRequires`: 実装前に必要な artifact ID の配列（例: `["tasks"]`）
- `artifacts`: 全 artifact のリスト（ステータスと依存関係付き）

### Step 4: artifact を順次作成（apply-ready になるまで）

依存関係順にループ（未解決の依存がない artifact から先に処理）:

a. **`ready`（依存が満たされた）artifact ごとに**:
   - 指示を取得:
     ```bash
     twl spec instructions <artifact-id> --change "<name>" --json
     ```
   - 指示 JSON の内容:
     - `context`: プロジェクト背景（自分への制約 — 出力に含めない）
     - `rules`: artifact 固有のルール（自分への制約 — 出力に含めない）
     - `template`: 出力ファイルの構造
     - `instruction`: この artifact タイプ向けのスキーマ固有ガイダンス
     - `outputPath`: artifact の書き込み先
     - `dependencies`: コンテキスト用に読み込む完了済み artifact
   - 完了済みの依存 artifact をコンテキストとして読み込む
   - `template` を構造として artifact ファイルを作成する
   - `context` と `rules` は制約として適用する — ファイルにコピーしない
   - 進捗を簡潔に表示: 「<artifact-id> を作成」

b. **全 `applyRequires` artifact が完了するまで続行**
   - 各 artifact 作成後に `twl spec status --change "<name>" --json` を再実行
   - `applyRequires` の全 artifact ID が artifacts 配列で `status: "done"` か確認
   - 全 `applyRequires` artifact が完了したら停止

c. **artifact がユーザー入力を必要とする場合**（コンテキストが不明確）:
   - **AskUserQuestion tool** で明確化する
   - その後作成を続行

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

**出力**

全 artifact 完了後、以下をサマリーとして表示:
- change 名と場所
- 作成した artifact のリストと簡単な説明
- 準備状況: 「全 artifact 作成完了！実装の準備が整いました。」
- 案内: 「`/twl:change-apply` を実行するか、実装を依頼してタスクに取り掛かりましょう。」

## Artifact 作成ガイドライン

- 各 artifact タイプの `instruction` フィールドに従う
- スキーマが各 artifact の内容を定義する — それに準拠する
- 新しい artifact を作成する前に依存 artifact を読み込む
- `template` を出力ファイルの構造として使用し、各セクションを埋める
- **重要**: `context` と `rules` は自分への制約であり、ファイルの内容ではない
  - `<context>`, `<rules>`, `<project_context>` ブロックを artifact にコピーしてはならない
  - これらは記述内容のガイドであり、出力に含めるものではない

## 禁止事項（MUST NOT）

- SHALL/MUST なしの要件本文を生成してはならない
- Scenario なしの要件を生成してはならない
- 実装に必要な全 artifact を作成すること（スキーマの `apply.requires` で定義）
- 新しい artifact を作成する前に必ず依存 artifact を読み込む
- コンテキストが著しく不明確な場合はユーザーに質問する — ただし勢いを保つために合理的な判断を優先する
- 同名の change が既に存在する場合、続行するか新規作成するか質問する
- 次の artifact に進む前に、各 artifact ファイルの存在を確認する

## チェックポイント（MUST）

`/twl:ac-extract` を Skill tool で自動実行。
