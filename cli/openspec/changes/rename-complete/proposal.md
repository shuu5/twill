## Why

`loom rename` は deps.yaml キー名・calls 参照・v3.0 フィールド・frontmatter・body 参照の 5 箇所を更新するが、`path` フィールド・`entry_points` リスト・実ファイル/ディレクトリの rename が未対応。rename 後にプラグインが壊れる（`loom check` で path 不在エラー）。

## What Changes

- `rename_component()` に path フィールドの old_name → new_name 文字列置換を追加
- `rename_component()` に entry_points リスト内の対応パス更新を追加
- `rename_component()` にディレクトリ/ファイルの実 rename（`Path.rename()`）を追加
- `--dry-run` モードで上記 3 項目のプレビュー表示を追加

## Capabilities

### New Capabilities

- path フィールドの自動更新（old_name を含むパス文字列を new_name に置換）
- entry_points リスト内のパス自動更新
- ディレクトリ rename（path が示すディレクトリの移動）
- dry-run での path/entry_points/directory 変更プレビュー

### Modified Capabilities

- `rename_component()` 関数の拡張（既存の 5 箇所更新に 3 箇所追加）
- dry-run 表示に新規変更項目を追加

## Impact

- 変更ファイル: `loom-engine.py`（`rename_component()` 関数）
- 既存テスト: rename 関連テストに path/entry_points/directory のアサーション追加が必要
- 前例: `promote_component()` が同様のファイル移動ロジックを持つ（`Path.rename()` + 空ディレクトリ削除）
- 部分一致リスク: `co-auto` rename が `co-autopilot` に波及しないよう境界マッチが必要
