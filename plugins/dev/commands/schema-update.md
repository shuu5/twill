# Zod スキーマ更新ワークフロー

webapp-hono タイプのプロジェクト（`packages/schema/` が存在）専用。
5 ステップで Zod スキーマを更新し、OpenAPI 再生成 + 検証を実行する。

## 使用方法

```
/dev:schema-update           # 5ステップワークフロー実行
/dev:schema-update --check-only  # 現状チェックのみ
```

## 実行ロジック（MUST）

### Step 1: 現状確認

```bash
ls packages/schema/src/
cat packages/schema/src/index.ts
```

### Step 2: スキーマ更新

ユーザーの要求に応じて `packages/schema/src/*.ts` を Edit/Write。

ルール:
- 各ドメインは独立したファイル（例: `user.ts`, `post.ts`）
- `index.ts` から必ず re-export
- `z.infer<>` で型推論可能な形式で定義

### Step 3: OpenAPI 再生成

```bash
bun run schema:generate
```

### Step 4: 検証

```bash
bun run schema:validate
```

- exit code 0 → PASS
- exit code != 0 → FAIL（エラー詳細を表示し Step 2 に戻る）

### Step 5: 整合性確認

- `docs/schema/openapi.yaml` が更新されたか確認（`git diff`）
- OpenSpec 仕様との整合性を確認

## --check-only モード

Step 1 のみ実行し構造化レポートで報告:

```
schema-update --check-only 結果:
  packages/schema/src/ ファイル数: N
  re-export (index.ts): [OK|MISSING: {list}]
  root workspaces: [OK|MISSING]
  schema scripts: [OK|MISSING: {list}]
  docs/schema/openapi.yaml: [OK|MISSING|STALE]
  判定: [PASS|FAIL]
```

## 禁止事項（MUST NOT）

- `docs/schema/openapi.yaml` を直接編集してはならない
- Step 3-4 をスキップしてはならない
