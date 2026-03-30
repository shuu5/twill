# /dev:issue-structure - Issue内容の構造化

要望テキストを受け取り、Issueタイプを判定し、テンプレートに沿って構造化されたIssue内容を生成する。

## 使用方法

```
/dev:issue-structure <要望テキスト>
```

## フロー（MUST）

### Step 1: Issueタイプ判定

要望の内容から以下を判定:

| タイプ | テンプレート | タイトルプレフィックス |
|--------|-------------|---------------------|
| Feature | `plugins/dev/templates/issue/feature.md` | `[Feature]` |
| Bug | `plugins/dev/templates/issue/bug.md` | `[Bug]` |
| Docs | （テンプレートなし） | `[Docs]` |

### Step 1.5: architecture/ 検出と ctx/* 候補リスト構築

git root に `architecture/` ディレクトリが存在するか確認する。存在しない場合は本ステップを skip し、Step 2 へ進む。

存在する場合、ref-project-model §2 の導出ルールに従い ctx/\<name\> 候補リストを構築:

1. **Glob** で `architecture/domain/contexts/*.md` を検索 → ファイル名（拡張子除去）を `ctx/<name>` として収集
2. **Glob** で `architecture/contracts/*.md` を検索 → ファイル名（拡張子除去）を `ctx/<name>` として収集
3. **Read** で `architecture/domain/model.md` を確認 → `## Shared Kernel` セクションが存在すれば `ctx/shared-kernel` を追加

候補リストが空（contexts/ も contracts/ もファイルなし）の場合は skip。

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

### Step 2.5: ctx/\<name\> 提案

Step 1.5 で候補リストが構築された場合のみ実行。

1. 各候補 context の `.md` ファイルを **Read** し、context の責務・スコープを把握する
2. 要望テキストの内容と各 context の責務を照合し、最も関連性の高い ctx/\<name\> を1つ選択する
3. 判定結果:
   - **単一マッチ**: 該当する `ctx/<name>` を提案ラベルとして記録
   - **複数マッチ**: 最も主要な `ctx/<name>` を1つ提案し、関連する他を補足表示
   - **該当なし**: 「既存の context に該当しない可能性があります。新しい Bounded Context の追加を検討してください」と表示し、提案は行わない

### Step 3: 結果出力

構造化したタイトルと本文を出力する。後続ステップ（issue-assess, issue-create）で使用される。

Step 2.5 で ctx/\<name\> の提案がある場合、出力末尾に以下を追加:

```
## 推奨ラベル

- `ctx/<name>`: <context の説明>
```

提案がない場合（architecture/ なし、候補なし、該当なし）はこのセクションを出力しない。

## 禁止事項（MUST NOT）

- Issue作成を実行してはならない（構造化のみ）
- テンプレートファイル自体を変更してはならない
