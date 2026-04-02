---
name: dev:workflow-test-ready
description: |
  テスト生成と準備確認を実行する。workflow-setup の後に呼び出す。

  Use when user: says テスト準備/test-ready,
  or when called from workflow-setup chain.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-setup
---

# テスト準備 Workflow

テスト生成と準備確認を実行する。workflow-setup の後に呼び出す。

## フロー制御（MUST）

### 1. change-id 解決

openspec/changes/ から最新を自動検出。

### 2. テスト生成（条件判定）

```
IF openspec/ が存在
  AND openspec/changes/<change-id>/specs/ に Scenario が存在
  AND openspec/changes/<change-id>/test-mapping.yaml が存在しない
THEN
  a. Unit/Integration テスト → /dev:test-scaffold <change-id> --type=unit --coverage=edge-cases
  b. E2E テスト → デフォルト yes で自動実行
ELSE
  → スキップ理由を報告
```

### 3. 準備確認

`/dev:check` を Skill tool で実行。

### 4. チェックポイント出力

`/dev:opsx-apply <change-id>` を自動実行。

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### Step 1: change-id 解決
openspec/changes/ から最新の change-id を自動検出する。1 つ → 自動選択、複数 → 最新を自動選択。

### Step 2: テスト生成（条件判定）
以下の条件を判定し、該当する場合のみテスト生成を実行する。

```
IF openspec/ が存在
  AND openspec/changes/<change-id>/specs/ に Scenario が存在
  AND openspec/changes/<change-id>/test-mapping.yaml が存在しない
THEN
  a. Unit/Integration テスト → /dev:test-scaffold <change-id> --type=unit --coverage=edge-cases
  b. E2E テスト → デフォルト yes で自動実行
ELSE
  → スキップ理由を報告
```

テスト対象コードが存在しない場合（Markdown のみの変更等）はスキップ理由を報告して Step 3 に進む。

### Step 3: check 実行（準備確認）
`/dev:check` を Skill tool で実行する。

結果判定:
- CRITICAL FAIL 項目が存在 → Step 4 をスキップし、FAIL 内容を報告して停止
- FAIL なし → 即座に Step 4 に進む

### Step 4: opsx-apply + autopilot 判定 + pr-cycle 遷移
`/dev:opsx-apply <change-id>` を Skill tool で実行する。opsx-apply 内で autopilot 判定と pr-cycle 遷移が処理される。

## 禁止事項（MUST NOT）

- Unit/Integration テスト生成を独断でスキップしてはならない
