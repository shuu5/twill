## 1. crg-auto-build.md MUST NOT ルール追加

- [x] 1.1 `plugins/twl/commands/crg-auto-build.md` の `禁止事項（MUST NOT）` セクションに `ln` コマンド実行禁止ルールを追加する
- [x] 1.2 `.code-review-graph` ディレクトリ/ファイルの手動作成・削除・symlink 操作禁止ルールを追加する

## 2. orchestrator CRG セクション強化

- [x] 2.1 `plugins/twl/scripts/autopilot-orchestrator.sh` の CRG symlink セクション（L325 付近）の冒頭に、`${TWILL_REPO_ROOT}/main/.code-review-graph` が symlink かどうかチェックするコードを追加する
- [x] 2.2 symlink が検出された場合、削除して警告ログを出力するコードを追加する

## 3. su-observer ヘルスチェック追加

- [x] 3.1 `plugins/twl/skills/su-observer/SKILL.md` の Wave 開始時チェックリストに CRG ヘルスチェック手順を追加する

## 4. テスト更新

- [x] 4.1 `plugins/twl/tests/unit/crg-symlink-reporoot/crg-symlink-reporoot.bats` に、main の `.code-review-graph` が symlink の場合に orchestrator が削除することを検証するテストケースを追加する
