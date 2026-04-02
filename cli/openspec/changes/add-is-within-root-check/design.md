## Context

`deep_validate()` は deps.yaml の深層検証を行う関数で、section A〜E の5つの検証セクションを持つ。section E（L2924）には既に `_is_within_root()` チェックが存在するが、section A/B/C にはこのチェックが欠落している。

`_is_within_root(path, root)` は `path.resolve()` が `root.resolve()` 配下にあるかを検証するユーティリティで、パストラバーサルを防止する。

## Goals / Non-Goals

**Goals:**

- section A, B, C の各ファイルアクセス前に `_is_within_root()` チェックを追加
- section E の既存パターン（`if not _is_within_root(path, plugin_root): continue`）を踏襲

**Non-Goals:**

- section D のロジック変更（ファイルアクセスを行わないため不要）
- `_is_within_root()` 関数自体の変更
- 他の検証関数への波及

## Decisions

1. **既存パターンの踏襲**: section E の `if not _is_within_root(path, plugin_root): continue` を A/B/C にそのまま適用する。新たなパターンは導入しない
2. **挿入位置**: パス構築直後、ファイルアクセス（read_text, exists チェック等）の直前に挿入する
   - Section A: `path = plugin_root / spec.get('path', '')` の直後
   - Section B: `ds_path = plugin_root / ds_data[1].get('path', '')` の直後
   - Section C: `path = plugin_root / path_str` の直後

## Risks / Trade-offs

- リスク: 極めて低。既存パターンの機械的適用のみ
- トレードオフ: ルート外パスを持つコンポーネントは検証スキップされるが、これは section E と同一の意図的動作
