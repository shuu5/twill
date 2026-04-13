## 1. audit.py 新規モジュール作成

- [x] 1.1 `cli/twl/src/twl/autopilot/audit.py` を新規作成し `_project_root()` ヘルパーを実装する
- [x] 1.2 `is_audit_active()` を実装する（TWL_AUDIT=1 OR .audit/.active 存在で True）
- [x] 1.3 `resolve_audit_dir()` を実装する（TWL_AUDIT_DIR env → .audit/.active → None）
- [x] 1.4 `audit_on(run_id=None)` を実装する（.audit/<run-id>/ 作成 + .audit/.active 書き出し）
- [x] 1.5 `audit_off()` を実装する（.audit/.active 削除 + index.json 生成）
- [x] 1.6 `audit_status()` を実装する（現在状態を dict で返す）

## 2. CLI ディスパッチ追加

- [x] 2.1 `cli/twl/src/twl/cli.py` に `twl audit` サブコマンドのディスパッチを追加する（on/off/status）

## 3. checkpoint.py の audit 分岐追加

- [x] 3.1 `cli/twl/src/twl/autopilot/checkpoint.py` の `write()` に audit 分岐を追加する（上書き前に既存ファイルをタイムスタンプ付きで .audit/<run-id>/checkpoints/ にコピー）

## 4. state.py の audit 分岐追加

- [x] 4.1 `cli/twl/src/twl/autopilot/state.py` の write 系メソッドに audit 分岐を追加する（変更フィールド・前後値・role・ts を state-log.jsonl に JSONL 追記）

## 5. launcher.py の env_flags 追加

- [x] 5.1 `cli/twl/src/twl/autopilot/launcher.py` の `env_flags` 生成に `resolve_audit_dir()` を呼び出して `TWL_AUDIT=1` + `TWL_AUDIT_DIR=<絶対パス>` を追加する

## 6. check-specialist-completeness.sh の修正

- [x] 6.1 `plugins/twl/scripts/hooks/check-specialist-completeness.sh` に TWL_AUDIT 有効時の /tmp/.specialist-* コピー処理を既存削除処理より前に追加する

## 7. gitignore と deps.yaml の更新

- [x] 7.1 `.gitignore` に `.audit/` を追加する
- [x] 7.2 `deps.yaml` に `audit.py` モジュールのエントリを追加する

## 8. テスト確認

- [x] 8.1 既存テスト `pytest tests/` が全て PASS することを確認する（pre-existing 失敗 127 件と同数、新規失敗なし）
