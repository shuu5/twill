# test-fixtures

TWiLL フレームワークのテスト用フィクスチャ。plugin-dev の動作検証用テストプロジェクト。TWiLL モノリポ `test-fixtures/` として管理。

## 構成

- モノリポ: `~/projects/local-projects/twill/main/test-fixtures/`

<!-- GOVERNANCE-START -->

## ガバナンス（自動適用済み）

### Hooks（.claude/settings.json）

プロジェクト固有の Hooks が禁止操作を機械的にブロックします。
具体的なルールは `.claude/settings.json` の hooks セクションを参照。

### 規約

- ブランチ命名: `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`
- コミット: Conventional Commits 形式
- テスト: 実装前にテスト生成（TDD）
- PR: `/dev:controller-pr-cycle` 経由で作成

### スキーマ改善サイクル

開発中にスキーマの不整合を発見した場合:
1. SSoT（Zod スキーマ / OpenAPI）を先に修正
2. 実装コードを SSoT に合わせて修正
3. `/dev:check` で整合性確認
<!-- GOVERNANCE-END -->
