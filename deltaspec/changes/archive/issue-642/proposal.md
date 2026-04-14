## Why

autopilot パイプラインの中間成果物（specialist manifest、checkpoint、state 遷移）が揮発性（/tmp）または上書き型で保管されており、実行の全体像を事後追跡できない。Wave 16-18 で 17 Issue を実装した際、specialist の spawn 完了・checkpoint のパス不整合・state stall 検知が困難であることが発覚した（#640 の根本原因）。

## What Changes

- `cli/twl/src/twl/cli.py` — `twl audit <on|off|status>` サブコマンドのディスパッチ追加
- `cli/twl/src/twl/autopilot/audit.py` — 新規モジュール（on/off/status ロジック + ヘルパー関数）
- `cli/twl/src/twl/autopilot/checkpoint.py` — `write()` に audit 分岐追加（上書き前にタイムスタンプ付きコピー）
- `cli/twl/src/twl/autopilot/state.py` — write 系メソッドに audit 分岐追加（変更前後 diff を state-log.jsonl に追記）
- `cli/twl/src/twl/autopilot/launcher.py` — `env_flags` に `TWL_AUDIT` / `TWL_AUDIT_DIR` を追加
- `plugins/twl/scripts/hooks/check-specialist-completeness.sh` — TWL_AUDIT 時に /tmp の specialist ファイルを audit dir にコピー（既存削除処理より前）
- `.gitignore` — `.audit/` 追加
- `deps.yaml` — `audit.py` 新規モジュールのエントリ追加

## Capabilities

### New Capabilities

- `twl audit on [--run-id ID]` — `.audit/<run-id>/` ディレクトリを作成し `.audit/.active` ファイルを書き出す
- `twl audit off` — `.audit/.active` を削除し `.audit/<run-id>/index.json`（保全ファイル一覧）を生成する
- `twl audit status` — 現在の audit 状態（active/inactive、run-id）を表示する
- `is_audit_active()` — `TWL_AUDIT=1` env var または `.audit/.active` 存在で audit 有効を判定する
- `resolve_audit_dir()` — `TWL_AUDIT_DIR` env var → `.audit/.active` の順で audit ディレクトリを解決する
- specialist ファイルの自動保全 — PostToolUse hook 内で `/tmp/.specialist-*` を `.audit/<run-id>/specialists/` にコピー
- checkpoint 自動保全 — checkpoint write 時に既存ファイルをタイムスタンプ付きで `.audit/<run-id>/checkpoints/` にコピー
- state 遷移ログ — state write 時に変更前後 diff を `.audit/<run-id>/state-log.jsonl` に JSONL で追記

### Modified Capabilities

- `checkpoint.write()` — audit 有効時に上書き前コピーを追加実行
- `state.py` write 系メソッド — audit 有効時に state-log.jsonl へ追記
- `launcher.py` `env_flags` 生成 — `resolve_audit_dir()` で解決した絶対パスを `TWL_AUDIT_DIR` として Worker に伝搬
- `check-specialist-completeness.sh` — audit コピー処理を既存削除処理より前に追加

## Impact

- 影響コード: `cli/twl/src/twl/cli.py`、`autopilot/` 配下 4 モジュール、`plugins/twl/scripts/hooks/check-specialist-completeness.sh`
- 新規 API: `twl audit` サブコマンド（3 サブコマンド）、`audit.py` の `is_audit_active()` / `resolve_audit_dir()` / `_project_root()`
- 依存方向: `audit.py` → stdlib のみ（循環依存なし）。`checkpoint.py` / `state.py` → `audit.py`（一方向）
- `.audit/` ディレクトリは `.gitignore` で追跡除外
