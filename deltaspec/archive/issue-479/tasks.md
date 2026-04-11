## 1. Architecture 更新

- [x] 1.1 `plugins/twl/architecture/domain/contexts/observation.md` の `TestProject` エンティティに `mode: 'local' | 'real-issues'`, `repo: string | null`, `loaded_issues_file: string | null` フィールドを追加
- [x] 1.2 `plugins/twl/commands/test-project-init.md` の禁止事項「git push してはならない」を `--mode local` のみに条件付き化

## 2. test-project-init コマンド拡張

- [x] 2.1 `test-project-init.md` に `--mode <local|real-issues>` 引数の受け付け定義を追加（デフォルト: `local`）
- [x] 2.2 `--mode real-issues` 必須引数 `--repo <owner>/<name>` の定義と、未指定時のエラー処理を追加
- [x] 2.3 既存リポ指定時の空リポ検証フロー（コミット数 == 0 かつブランチ数 <= 1）を実装
- [x] 2.4 既存リポ指定時の push パーミッション確認フローを実装（失敗時明確なエラーメッセージ）
- [x] 2.5 指定リポ不存在時の gh CLI 自動作成フロー（private / empty / 指定 owner）を実装
- [x] 2.6 リポ作成失敗時のエラーハンドリング（rate limit / 権限不足 / 名前衝突）を追加
- [x] 2.7 `--mode local` 未指定時の既存動作維持（デフォルト = local）を確認

## 3. .test-target/config.json 生成

- [x] 3.1 `--mode real-issues` 初期化完了後に `.test-target/config.json` を生成するフローを追加（フィールド: `mode`, `repo`, `initialized_at`, `worktree_path`, `branch`）
- [x] 3.2 `--mode local` 初期化時にも `.test-target/config.json` を生成（`repo: null`）

## 4. 既存 bats テスト更新

- [x] 4.1 `plugins/twl/tests/bats/e2e/co-self-improve-smoke.bats` の `test-project-init` 呼び出しに `--mode local` を明示
- [x] 4.2 `plugins/twl/tests/bats/e2e/co-self-improve-regression.bats` の `test-project-init` 呼び出しに `--mode local` を明示

## 5. 動作確認

- [x] 5.1 `--mode real-issues --repo <owner>/<name>` で worktree + 専用リポ紐付けが動作することを確認
- [x] 5.2 `--mode local` または未指定で既存動作が変わらないことを確認
- [x] 5.3 既存 bats テスト（`smoke.bats`, `regression.bats`）が `--mode local` 明示で通過することを確認
