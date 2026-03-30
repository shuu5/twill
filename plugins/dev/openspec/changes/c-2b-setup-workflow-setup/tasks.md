## 1. 未移植コンポーネントの COMMAND.md 作成

- [x] 1.1 `commands/services.md` を作成（旧プラグインから変換、frontmatter 除去）
- [x] 1.2 `commands/ui-capture.md` を作成（旧プラグインから変換、Playwright MCP 参照維持）
- [x] 1.3 `commands/e2e-plan.md` を作成（旧プラグインから変換、4層検証構造維持）
- [x] 1.4 `commands/test-scaffold.md` を作成（旧プラグインから変換、composite 構造維持）

## 2. worktree-delete コマンド化

- [x] 2.1 `commands/worktree-delete.md` を作成（scripts/worktree-delete.sh のラッパー）

## 3. deps.yaml 更新

- [x] 3.1 services を deps.yaml commands セクションに atomic 型で追加
- [x] 3.2 ui-capture を deps.yaml commands セクションに atomic 型で追加
- [x] 3.3 e2e-plan を deps.yaml commands セクションに atomic 型で追加
- [x] 3.4 test-scaffold を deps.yaml commands セクションに composite 型で追加
- [x] 3.5 worktree-delete を deps.yaml commands セクションに atomic 型で追加（既存 script は残存）
- [x] 3.6 workflow-test-ready の calls フィールドに test-scaffold, opsx-apply を step 付きで追加

## 4. 検証

- [x] 4.1 `loom check` で構造検証 PASS
- [x] 4.2 `loom validate` で全コンポーネント認識確認
- [x] 4.3 全11コンポーネントが deps.yaml に存在することを確認
