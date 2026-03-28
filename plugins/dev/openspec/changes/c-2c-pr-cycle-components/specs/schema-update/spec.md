## ADDED Requirements

### Requirement: Zod スキーマ更新ワークフロー

5 ステップ（現状確認 → スキーマ更新 → OpenAPI 再生成 → 検証 → 整合性確認）でスキーマを更新しなければならない（SHALL）。

webapp-hono タイプのプロジェクト（`packages/schema/` が存在）専用。

#### Scenario: フルワークフロー実行
- **WHEN** `schema-update` が引数なしで呼び出される
- **THEN** 5 ステップを順次実行し、検証に失敗した場合は Step 2 に戻って修正する

#### Scenario: check-only モード
- **WHEN** `schema-update --check-only` で呼び出される
- **THEN** Step 1（現状確認）のみ実行し、構造化レポートを出力する

### Requirement: OpenAPI 直接編集禁止

`docs/schema/openapi.yaml` を直接編集してはならない（MUST NOT）。必ず `bun run schema:generate` 経由で再生成する。

#### Scenario: OpenAPI ファイルの再生成
- **WHEN** Zod スキーマが更新された
- **THEN** `bun run schema:generate` を実行して openapi.yaml を再生成する

### Requirement: 検証必須

Step 3（OpenAPI 再生成）と Step 4（検証）をスキップしてはならない（MUST NOT）。

#### Scenario: 検証成功
- **WHEN** `bun run schema:validate` が exit code 0 を返す
- **THEN** PASS と判定し整合性確認へ進む

#### Scenario: 検証失敗
- **WHEN** `bun run schema:validate` が exit code != 0 を返す
- **THEN** FAIL と判定しエラー詳細を表示、Step 2 に戻る
