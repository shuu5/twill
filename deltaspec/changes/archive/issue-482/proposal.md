## Why

real-issues モードで作成された test Issue/PR/branch が積み上がると専用リポが肥大化する。定期的なクリーンアップ機構がないため、ADR-016 で懸念された「専用リポ案のクリーンアップ複雑度」が実運用上の障害となっている。

## What Changes

- `plugins/twl/commands/test-project-reset.md` に `--real-issues` フラグ分岐を追加
- `.test-target/loaded-issues.json` を参照した PR close → Issue close → test ブランチ削除フローを実装
- `--older-than <duration>` オプション追加（`d`/`w`/`m` 単位）
- `--dry-run` オプションで削除予定リストのみ出力
- `--mode local` と `--real-issues` の相互排他チェックを追加
- `plugins/twl/deps.yaml` の effort を low → medium に更新

## Capabilities

### New Capabilities

- `test-project-reset --real-issues` による real-issues モードリソース一括クリーンアップ
- `--older-than` による経過時間フィルタリング（`d`/`w`/`m` 単位対応）
- `--dry-run` によるドライランモード（削除予定リスト出力のみ）

### Modified Capabilities

- `test-project-reset` コマンドが `--mode local` と `--real-issues` の 2 系統を持つよう拡張
- 既存 Step 4（ユーザー確認）・Step 5（`git reset --hard`）を `--mode local` 時のみ実行するよう分岐整理

## Impact

- 影響ファイル: `plugins/twl/commands/test-project-reset.md`, `plugins/twl/deps.yaml`
- 依存: `#479`（`.test-target/config.json` の `repo` フィールド）、`#480`（`.test-target/loaded-issues.json` スキーマ）
- API: `gh pr close`, `gh issue close`, `git push origin --delete <branch>` を順次呼び出す
- 既存の `--mode local` 動作には変更なし
