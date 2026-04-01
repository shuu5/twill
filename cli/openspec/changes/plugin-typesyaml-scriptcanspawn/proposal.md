## Why

loom-plugin-dev が loom-plugin-session に依存する構造が発生しているが、現在の deps.yaml v3 には cross-plugin 参照の表現手段がない。また types.yaml の `script.can_spawn` が空集合 `[]` で、bash script が別 script を呼ぶ実態と乖離しており、`loom validate` で script→script edge violations が発生している。

## What Changes

- deps.yaml で他 plugin のコンポーネントを参照する構文を定義（`plugin:component` 形式）
- `loom validate` が cross-plugin 参照を検証（参照先 plugin の deps.yaml を解決）
- `loom check` が cross-plugin 参照先のファイル存在を検証
- types.yaml の `script.can_spawn` に `script` を追加

## Capabilities

### New Capabilities

- **Cross-plugin 参照構文**: deps.yaml の calls 内で `{plugin}:{component}` 形式で他 plugin のコンポーネントを参照可能
- **Cross-plugin 参照検証**: `loom validate` が参照先 plugin の deps.yaml を解決し、型整合性を検証
- **Cross-plugin ファイル存在検証**: `loom check` が参照先 plugin 内のファイル存在を確認

### Modified Capabilities

- **script.can_spawn 拡張**: types.yaml の script 型が `can_spawn: [script]` に変更され、script→script 呼び出しが型ルール上で正式サポート
- **validate_types 拡張**: cross-plugin 参照を含むエッジの型整合性チェックに対応
- **check 拡張**: cross-plugin 参照先の path 解決とファイル存在チェックに対応

## Impact

- **types.yaml**: `script.can_spawn` を `[]` → `[script]` に変更
- **loom-engine.py**: `validate_types()`, `validate_body_refs()`, check 関連関数に cross-plugin 解決ロジックを追加
- **deps.yaml パーサー**: calls 内の `plugin:component` 形式を認識し、外部 plugin の deps.yaml を読み込む解決ロジック
- **既存テスト**: 変更後も全テスト PASS を維持する必要あり
- **下流影響**: 各 plugin の deps.yaml で cross-plugin 参照を記述可能になる（各 plugin 側の対応は別 Issue）
