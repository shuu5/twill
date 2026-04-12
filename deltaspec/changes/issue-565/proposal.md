## Why

deps.yaml の検証は PostToolUse（書き込み後）でのみ行われているため、壊れた YAML が一旦 disk に書き込まれると後続の `twl --check` 自体が YAML parse エラーでクラッシュし、有用なフィードバックを返せない。Write/Edit ツール実行前に YAML syntax を事前検証することで、この問題を根本的に防止する。

## What Changes

- 新規スクリプト `plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh` を追加
  - Write: `tool_input.content` から全文を取得し YAML parse
  - Edit: `tool_input.old_string`/`new_string` で simulated apply を行い YAML parse
  - YAML syntax エラー時 exit 2 + stderr にメッセージ出力
- `plugins/twl/hooks/hooks.json` に PreToolUse エントリを追加（matcher: `Edit|Write`, if: `deps.yaml`）
- `plugins/twl/deps.yaml` の scripts セクションに新規スクリプトのコンポーネントエントリを追加

## Capabilities

### New Capabilities

- deps.yaml への Write/Edit が実行される前に YAML syntax を検証し、不正な YAML を disk に書き込む前にブロックできる
- `python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"` による軽量（~0.05s）な YAML 検証

### Modified Capabilities

- `plugins/twl/hooks/hooks.json`: PreToolUse hook エントリが追加され、deps.yaml を対象とした Edit/Write の事前ガードが有効になる
- `plugins/twl/deps.yaml`: 新規スクリプトが scripts セクションに登録される

## Impact

- 影響コード: `plugins/twl/hooks/hooks.json`, `plugins/twl/deps.yaml`, 新規ファイル `plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh`
- deps.yaml 以外のファイルへの Edit/Write には影響なし（`if` 条件で除外）
- PostToolUse hook の動作には変更なし
