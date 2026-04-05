## Why

`deep_validate()` の section A（Controller 行数チェック）、B（Reference 配置監査）、C（Frontmatter-Body ツール整合性）が `_is_within_root()` チェックなしにファイルを読み込んでおり、`plugin_root` 外のパスが `deps.yaml` に含まれた場合にルート外ファイルへアクセスする可能性がある。section E には既にこのチェックが存在しており、同一パターンを A/B/C にも適用する。

## What Changes

- section A: ファイルアクセス前に `_is_within_root(path, plugin_root)` チェックを追加
- section B: ファイルアクセス前に `_is_within_root(ds_path, plugin_root)` チェックを追加
- section C: ファイルアクセス前に `_is_within_root(path, plugin_root)` チェックを追加

## Capabilities

### New Capabilities

- なし

### Modified Capabilities

- `deep_validate()` section A/B/C がルート外パスをスキップするようになる

## Impact

- 影響ファイル: `twl-engine.py` の `deep_validate()` 関数内のみ
- API 変更: なし
- 依存関係変更: なし
- リスク: 低（既存パターンの適用のみ）
