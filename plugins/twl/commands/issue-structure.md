# /twl:issue-structure - Issue内容の構造化

要望テキストを受け取り、Issueタイプを判定し、テンプレートに沿って構造化されたIssue内容を生成する。

## 使用方法

```
/twl:issue-structure <要望テキスト>
```

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

ルートレベル `architecture/domain/context-map.md` を **Read** する。存在しない場合は scope/* 候補リストを空とする。

存在する場合:
1. flowchart の subgraph 内のノード名からコンポーネント名を抽出（例: `cli/twl`, `plugins/twl`）
2. スラッシュ → ハイフン変換で `scope/<name>` 候補リストを構築（例: `scope/cli-twl`, `scope/plugins-twl`）
3. 各コンポーネントパスの `<component>/architecture/domain/context-map.md` を **Read** し（存在する場合）、サブコンポーネントがあれば追加の scope/* 候補を収集する。`COMPONENT_PATHS` として抽出したコンポーネントパスのリストを保持し、Step 1.5b で使用する

#### Step 1.5b: ctx/* 候補リスト構築

git root に `architecture/` ディレクトリが存在するか確認する。存在しない場合は ctx/* 候補リストを空とし、Step 2 へ進む。

存在する場合、ref-project-model §2 の導出ルールに従い ctx/\<name\> 候補リストを構築:

1. **Glob** で `architecture/domain/contexts/*.md` を検索 → ファイル名（拡張子除去）を `ctx/<name>` として収集
2. Step 1.5a で取得した `COMPONENT_PATHS` の各コンポーネントについて **Glob** で `<component>/architecture/domain/contexts/*.md` を検索 → ファイル名（拡張子除去）を `ctx/<name>` として収集し、`CTX_FILE_PATHS` に `ctx/<name>` → `<component>/architecture/domain/contexts/<name>.md` のエントリを追記する。同名 context が複数コンポーネントに存在する場合（例: `plugins/twl` と `cli/twl` 両方に `autopilot.md`）は、全コンポーネントのパスを保持し、Step 2.5 で scope/* と照合して最も関連性の高いコンポーネントのパスを選択する。リポルートとコンポーネントで同名が存在する場合、コンポーネントパスを優先する
3. **Glob** で `architecture/contracts/*.md` を検索 → ファイル名（拡張子除去）を `ctx/<name>` として収集
4. **Read** で `architecture/domain/model.md` を確認 → `## Shared Kernel` セクションが存在すれば `ctx/shared-kernel` を追加

`CTX_FILE_PATHS` として各 ctx/* 名から対応するファイルパス（コンポーネントパス含む）へのマッピングを保持し、Step 3 の arch-ref タグ生成で使用する。同名 context が複数コンポーネントに存在する場合は Step 2.5 で確定したコンポーネントパスのエントリを使用する。

候補リストが空（contexts/ も contracts/ もファイルなし）の場合は ctx/* を skip。

### Step 2: テンプレート読込

テンプレートを **Read tool** で読み込み、フィールドを埋める。

**Feature の場合**:

1. **タイトル**: `[Feature] xxx`
2. **概要**: 1-2文での説明
3. **背景・動機**: なぜ必要か
4. **スコープ**: 含む/含まないを明確化（不明なら省略可）
5. **技術的アプローチ**: 実現方法（不明なら省略可）
6. **受け入れ基準**: 完成条件（`- [ ]` チェックリスト形式）

**Bug の場合**:

1. **タイトル**: `[Bug] xxx`
2. **概要**: バグの内容を1-2文
3. **再現手順**: 番号付き手順（2ステップ以上）
4. **期待される動作**: 本来どう動作すべきか
5. **実際の動作**: 現在どうなっているか
6. **環境情報**: OS/ブラウザ/Node.js（わかる範囲で）
7. **補足情報**: エラーログ、スクリーンショット等（あれば）

**Docs の場合**:

テンプレートなし。タイトル（`[Docs] xxx`）と適切な本文を生成。

### Step 2.5: scope/* + ctx/\<name\> 提案

Step 1.5 で候補リストが構築された場合のみ実行。

#### scope/* 提案

Step 1.5a で scope/* 候補リストが構築された場合:
1. 要望テキストの内容と各コンポーネントのパスを照合し、最も関連性の高い `scope/<name>` を1つ選択する
2. 該当なしの場合は提案を行わない

#### ctx/* 提案

Step 1.5b で ctx/* 候補リストが構築された場合:
1. 各候補 context の `.md` ファイルを **Read** し、context の責務・スコープを把握する
2. 要望テキストの内容と各 context の責務を照合し、最も関連性の高い ctx/\<name\> を1つ選択する
3. 判定結果:
   - **単一マッチ**: 該当する `ctx/<name>` を提案ラベルとして記録
   - **複数マッチ**: 最も主要な `ctx/<name>` を1つ提案し、関連する他を補足表示
   - **該当なし**: 「既存の context に該当しない可能性があります。新しい Bounded Context の追加を検討してください」と表示し、提案は行わない

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
