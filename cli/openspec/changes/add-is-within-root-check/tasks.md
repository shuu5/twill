## 1. _is_within_root() チェック追加

- [x] 1.1 Section A（L2825-2826）: `path = plugin_root / spec.get('path', '')` の直後に `if not _is_within_root(path, plugin_root): continue` を追加
- [x] 1.2 Section B（L2857-2858）: `ds_path = plugin_root / ds_data[1].get('path', '')` の直後に `if not _is_within_root(ds_path, plugin_root): continue` を追加
- [x] 1.3 Section C（L2881）: `path = plugin_root / path_str` の直後に `if not _is_within_root(path, plugin_root): continue` を追加

## 2. テスト

- [x] 2.1 ルート外パスを含む deps.yaml でのテスト: section A/B/C がスキップされることを確認
- [x] 2.2 正常パスでの既存テスト: 回帰がないことを確認
- [x] 2.3 Section E の既存チェック（L2924付近）が変更されていないことを確認
