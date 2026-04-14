## Context

`cld-spawn` は tmux new-window で Claude Code Worker セッションを起動するランチャースクリプト。起動されたセッションは非インタラクティブシェルとなり、`~/.bashrc` の `case $- in *i*)` ガードが発動して `~/.secrets` 等の env file が読まれない。

既存の `--cd` オプションと同様のパターンで `--env-file PATH` オプションを追加し、ランチャースクリプト（LAUNCHER）内の `source <env-file>` 行として注入する。`autopilot-launch.sh` は `env ${AUTOPILOT_ENV} ${REPO_ENV}` で環境変数を tmux に渡す仕組みを持つが、cld-spawn はこの機構を持たない。

## Goals / Non-Goals

**Goals:**

- `cld-spawn --env-file PATH` オプションを追加し、起動する Worker セッションで env file を自動ソース
- `CLD_ENV_FILE` 環境変数による `--env-file` 自動フォールバック
- `--env-file` 引数のチルダ展開処理（`ENV_FILE="${ENV_FILE/#\~/$HOME}"`）
- env file 不在時にエラーを発生させない（`2>/dev/null || true`）
- `issue-lifecycle-orchestrator.sh` の cld-spawn 呼び出しに `--env-file ~/.secrets` を追加

**Non-Goals:**

- `autopilot-launch.sh` の既存環境変数伝搬機構の変更
- codex CLI の認証方式の変更
- `spec-review-orchestrator.sh` の cld-spawn 呼び出し修正
- env file のバリデーション（フォーマット検証等）

## Decisions

**ランチャースクリプトへの `source` 行注入**: LAUNCHER の生成部分で env file が指定されている場合に `source <env-file> 2>/dev/null || true` 行を先頭に追加。`source` はシェルの変数定義を現在のプロセスに反映するため、Worker セッションの bash 環境に API キーが伝搬される。

**既存の `--cd` パターンを踏襲**: チルダ展開は `ENV_FILE="${ENV_FILE/#\~/$HOME}"` で実施。`--cd` の `CWD="${CWD/#\~/$HOME}"` と同様の処理。ただし `--cd` と異なり、ディレクトリ存在チェックは行わない（env file 不在時は `2>/dev/null || true` で無視）。

**`CLD_ENV_FILE` 環境変数**: `--env-file` 未指定時のデフォルトとして `CLD_ENV_FILE` を参照。ユーザーが一度設定すれば全ての cld-spawn 呼び出しで自動ソースされる。

**`issue-lifecycle-orchestrator.sh` のハードコード**: Worker セッション起動の主要パスである `issue-lifecycle-orchestrator.sh` のみを修正対象とし、`--env-file ~/.secrets` をハードコードで追加。

## Risks / Trade-offs

**セキュリティ**: `source` は任意シェルコマンドを実行可能。ただし `--env-file` に指定するファイルはユーザーが管理する信頼されたファイルに限定する運用前提。env file のパーミッションを `600` にすることを推奨。

**後方互換**: `--env-file` / `CLD_ENV_FILE` いずれも未指定の場合は既存動作に変更なし。LAUNCHER 生成ロジックへの追加は条件分岐付きのため副作用なし。
