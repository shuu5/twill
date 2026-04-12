---
type: atomic
tools: [Bash, Glob, Read, Skill]
effort: low
maxTurns: 10
---
# /twl:issue-structure - Issue内容の構造化

要望テキストを受け取り、Issueタイプを判定し、テンプレートに沿って構造化されたIssue内容を生成する。

## 使用方法

```
/twl:issue-structure <要望テキスト>
```

## 入力フォーマット

`要望テキスト` は以下のいずれかの形式で渡される:

- **プレーンテキスト**: ユーザーが直接入力した要望
- **body + comments 結合テキスト**: `workflow-issue-lifecycle` から呼び出される場合、`gh_read_issue_full` の出力（body と全 comments を `## === Comments ===` セパレータで結合したもの）が入力となる。comments に記載された追加仕様・AC・制約も構造化対象とすること（MUST）。

## フロー（MUST）

### Step 1: Issueタイプ判定

要望の内容から以下を判定:

| タイプ | テンプレート | タイトルプレフィックス |
|--------|-------------|---------------------|
| Feature | `plugins/twl/templates/issue/feature.md` | `[Feature]` |
| Bug | `plugins/twl/templates/issue/bug.md` | `[Bug]` |
| Docs | （テンプレートなし） | `[Docs]` |

### Step 1.5: scope/* + ctx/* 候補リスト構築

#### Step 1.5a: scope/* 候補リスト構築

`architecture/domain/context-map.md` を Read。存在しなければ scope/* 候補空。存在すれば:
- flowchart subgraph ノードからコンポーネント名抽出 → スラッシュ→ハイフン変換 → `scope/<name>`
- 各コンポーネントの `<component>/architecture/domain/context-map.md` も Read してサブコンポーネント追加
- `COMPONENT_PATHS` を保持（Step 1.5b で使用）

#### Step 1.5b: ctx/* 候補リスト構築

`architecture/` なし → ctx/* 空。ありの場合（ref-project-model §2 導出ルール）:
1. Glob `architecture/domain/contexts/*.md` → `ctx/<name>`
2. 各 `COMPONENT_PATHS` の `<component>/architecture/domain/contexts/*.md` → `ctx/<name>`（`CTX_FILE_PATHS` マッピング保持。同名はコンポーネントパス優先、Step 2.5 で scope 照合して選択）
3. Glob `architecture/contracts/*.md` → `ctx/<name>`
4. `architecture/domain/model.md` の `## Shared Kernel` → `ctx/shared-kernel`

候補空なら ctx/* skip。

### Step 2: テンプレート読込

テンプレートを Read し、フィールドを埋める:
- **Feature**: `plugins/twl/templates/issue/feature.md` — タイトル、概要、背景、スコープ、技術的アプローチ、受け入れ基準（`- [ ]`）
- **Bug**: `plugins/twl/templates/issue/bug.md` — タイトル、概要、再現手順、期待/実際の動作、環境情報、補足
- **Docs**: テンプレートなし。`[Docs] xxx` タイトルと適切な本文

### Step 2.5: scope/* + ctx/* 提案

候補リストがある場合のみ。scope/*: 要望と各コンポーネントパスを照合→1つ選択。ctx/*: 各候補の `.md` を Read し責務照合→単一マッチ（記録）/ 複数（主要1つ提案+補足）/ 該当なし（新 Context 検討を案内）。

### Step 3: 結果出力

構造化したタイトルと本文を出力する。後続ステップ（issue-assess, issue-create）で使用される。

Step 2.5 で scope/* または ctx/\<name\> の提案がある場合、出力末尾に以下を追加:

```
## 推奨ラベル

- `scope/plugins-twl`: plugins/twl コンポーネント
- `ctx/autopilot`: Autopilot Context (Core)
```

scope/* と ctx/* を並記する。提案がない場合（architecture/ なし、候補なし、該当なし）はこのセクションを出力しない。

#### arch-ref タグ生成（Step 2.5 の提案と連動）

Step 2.5 のマッチ数別に以下の出力を追加する。パスは `CTX_FILE_PATHS` マッピングを参照して正確なコンポーネント配下のパスを使用する（例: `plugins/twl/architecture/domain/contexts/autopilot.md`）:

- **単一マッチ**: `## 推奨ラベル` セクションの直後に以下を出力する:
  ```
  <!-- arch-ref-start -->
  <component>/architecture/domain/contexts/<name>.md
  <!-- arch-ref-end -->
  ```
  コンポーネントが特定できない場合（リポルートのみ）は `architecture/domain/contexts/<name>.md` を使用する
- **複数マッチ**: 主要 context（比重が最も高い1つ）のパスのみを上記タグ内に出力する
- **該当なし**: タグセクション自体を出力しない（MUST NOT）

## 禁止事項（MUST NOT）

- Issue作成を実行してはならない（構造化のみ）
- テンプレートファイル自体を変更してはならない
