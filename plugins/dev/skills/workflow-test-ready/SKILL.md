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

## 禁止事項（MUST NOT）

- Unit/Integration テスト生成を独断でスキップしてはならない
