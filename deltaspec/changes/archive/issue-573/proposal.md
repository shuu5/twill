## Why

`cld-spawn` 経由で起動された Worker セッションは非インタラクティブシェルとなり、`~/.bashrc` の `case $- in *i*)` ガードにより `~/.secrets` 等の環境変数ファイルが読み込まれない。そのため `CODEX_API_KEY` / `OPENAI_API_KEY` 等の API キーが Worker 環境に伝搬されず、`worker-codex-reviewer` 等の API キー依存コンポーネントが動作しない構造的課題がある。

## What Changes

- `plugins/session/scripts/cld-spawn` に `--env-file PATH` オプションを追加
- `CLD_ENV_FILE` 環境変数による自動ソース機構を追加
- `--env-file` のチルダ展開処理を追加（`ENV_FILE="${ENV_FILE/#\~/$HOME}"`）
- ランチャースクリプト生成部分を修正し、`source <env-file>` 行を挿入
- `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` の cld-spawn 呼び出しに `--env-file ~/.secrets` を追加

## Capabilities

### New Capabilities

- `cld-spawn --env-file <PATH>` で指定した env file を Worker セッションで自動ソース可能
- `CLD_ENV_FILE` 環境変数を設定することで、`--env-file` 未指定時にも自動ソース
- チルダ (`~`) を含むパスの正規展開

### Modified Capabilities

- `cld-spawn` の引数パース処理（`--env-file` オプション追加）
- `issue-lifecycle-orchestrator.sh` からの cld-spawn 呼び出し（`--env-file ~/.secrets` 付与）

## Impact

- `plugins/session/scripts/cld-spawn`: `--env-file` オプション追加・ランチャースクリプト生成ロジック変更
- `plugins/twl/scripts/issue-lifecycle-orchestrator.sh`: cld-spawn 呼び出し箇所に `--env-file ~/.secrets` 追加
- env-file が存在しない場合も `2>/dev/null || true` でエラー非伝搬（後方互換維持）
- `--env-file` / `CLD_ENV_FILE` いずれも未指定の場合は既存動作に変更なし
