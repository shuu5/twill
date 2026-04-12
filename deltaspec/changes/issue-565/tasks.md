## 1. スクリプト作成

- [x] 1.1 `plugins/twl/scripts/hooks/` ディレクトリが存在することを確認（必要なら作成）
- [x] 1.2 `plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh` を新規作成
  - stdin JSON から `tool_name` を取得し Write/Edit を判定
  - Write: `tool_input.content` → YAML parse（`python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"`）
  - Edit: `old_string`/`new_string` で simulated apply（`set -f`、bash 文字列置換）→ YAML parse
  - YAML syntax エラー時: exit 2 + stderr にメッセージ出力
  - 正常時: exit 0
- [x] 1.3 スクリプトに実行権限を付与（`chmod +x`）

## 2. hooks.json への PreToolUse エントリ追加

- [x] 2.1 `plugins/twl/hooks/hooks.json` を読み込み、現在の構造を確認
- [x] 2.2 PreToolUse セクションに以下のエントリを追加
  ```json
  {
    "matcher": "Edit|Write",
    "hooks": [
      {
        "type": "command",
        "if": "Edit(deps.yaml)|Write(deps.yaml)",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/hooks/pre-tool-use-deps-yaml-guard.sh",
        "timeout": 3000
      }
    ]
  }
  ```

## 3. deps.yaml へのコンポーネント登録

- [x] 3.1 `plugins/twl/deps.yaml` を読み込み、scripts セクションの構造を確認
- [x] 3.2 scripts セクションに `pre-tool-use-deps-yaml-guard.sh` のエントリを追加

## 4. 動作検証

- [x] 4.1 `twl --check` を実行し deps.yaml の整合性を確認
- [x] 4.2 hook スクリプトのユニットテスト（不正 YAML での exit 2、正常 YAML での exit 0）
