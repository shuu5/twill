# /dev:issue-assess - Issue品質評価

品質評価の統合指揮。2つの specialist を並列起動し、結果を統合して返す。

## 入力

呼び出し元（co-issue）から以下を受け取る:

- **type**: `feature` または `bug`
- **title**: Issueタイトル
- **body**: 構造化された本文
- **acceptance_criteria**: 受け入れ基準

---

## 実行フロー（MUST）

### 1. 入力パース

`$ARGUMENTS` またはワークフローコンテキストから以下を抽出:
- type: feature / bug
- title: Issueタイトル
- body: 構造化本文
- acceptance_criteria: 受け入れ基準

### 2. specialist 並列起動（MUST）

**単一メッセージで2つの Task tool を発行**（並列実行）:

```
Task(subagent_type="dev:template-validator", prompt="type={type}, title={title}, body={body}, criteria={criteria}")
Task(subagent_type="dev:context-checker", prompt="title={title}, summary={summary}, criteria={criteria}")
```

**重要**:
- 各 specialist に必要な入力情報をすべて渡す
- 並列実行で高速化（単一メッセージで複数Task）

### 3. 結果統合

両方の結果を受け取り、統合テーブルを出力する。

context-checker から tech-debt findings が返却された場合、統合テーブルに tech-debt セクションを追加する:
- 吸収可能な tech-debt がある場合: `tech_debt_absorbable` として一覧を含める
- 解決済み候補がある場合: `tech_debt_resolved` として一覧を含める
- `absorbable` または `resolved_candidates` が **1件以上** ある場合のみ `action_needed` に `tech_debt_decision: true` を追加（`total_found: 0` や全件が「無関係」の場合は追加しない）

### 4. ワークフローに返却

結果を workflow に返す（ユーザー判断は workflow が担当）。

---

## specialist 呼び出し（MUST）

specialist は **Task tool** で呼び出す。Skill tool は使用不可。

**呼び出し形式**:
```
Task(subagent_type="dev:template-validator", prompt="...")
Task(subagent_type="dev:context-checker", prompt="...")
```

### 並列実行（MUST）

2つの specialist を**単一メッセージで複数Task発行**して並列実行:

```
# 正しい例（並列）
Task(subagent_type="dev:template-validator", ...) + Task(subagent_type="dev:context-checker", ...) in same message

# 誤った例（順次）
Task(...) → wait → Task(...) → wait
```

---

## 出力形式（MUST）

```markdown
## 品質評価結果

### テンプレート準拠 (completeness: N%)

| フィールド | 状態 | 詳細 |
|-----------|------|------|
| タイトル形式 | ✅ | [Feature] プレフィックスあり |
| 概要 | ✅ | 2文で記述 |
| 背景・動機 | ❌ | セクション未記載 |
| ... | ... | ... |

### プロジェクトコンテキスト

| チェック | 結果 | 詳細 |
|---------|------|------|
| 重複チェック | ✅ 重複なし | - |
| 粒度 (I) | ✅ | 独立して実装可能 |
| ... | ... | ... |
| 関係性 | ℹ️ | Related: #45, #67 |
| tech-debt | ℹ️ | 吸収可能: N件, 解決済み候補: M件 |

### tech-debt 棚卸し（該当時のみ表示）

#### 吸収可能（スコープ内）
| # | タイトル | ラベル | 一致度 |
|---|---------|--------|--------|
| #12 | XXX | tech-debt/warning | high |

#### 解決済み候補（spec対応あり）
| # | タイトル | 対応spec |
|---|---------|----------|
| #8 | ZZZ | user-auth |

action_needed: { template_fix: bool, duplicate_decision: bool, split_decision: bool, tech_debt_decision: bool }
related_issues: [#N]
```

---

## 禁止事項（MUST NOT）

- **Skill tool で specialist を呼び出してはならない**: Task tool を使用
- **順次実行してはならない**: 並列実行可能なものは並列で
- **ユーザーインタラクションを行ってはならない**: 結果をワークフローに返すのみ
- **Issue作成してはならない**: 評価結果の返却のみ

---

## 次のステップ

`co-issue` 内での中間ステップ。
結果をワークフローに返す → Step 3 結果処理 → Step 4（ユーザー確認）へ。
