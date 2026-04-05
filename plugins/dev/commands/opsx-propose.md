# OpenSpec 提案ラッパー

`/dev:propose` をラップし、CLI フォーマット要件を spec 生成指示に注入する。

## 引数

- `change-name or description`: 変更名またはユーザーの説明
- `--arch-context <text>`: architecture/ コンテキスト（workflow-setup から注入）

## フロー制御（MUST）

### Step 1: propose 実行

`/dev:propose <arguments>` を Skill tool で実行。

### Step 2: spec 生成時フォーマット要件（MUST）

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

### Step 3: チェックポイント出力

```
>>> 提案完了: <change-id>
```

## 禁止事項（MUST NOT）

- SHALL/MUST なしの要件本文を生成してはならない
- Scenario なしの要件を生成してはならない

## チェックポイント（MUST）

`/dev:ac-extract` を Skill tool で自動実行。

