## Context

`rename_component()` は現在 5 箇所（deps.yaml キー/calls/v3.0 フィールド/frontmatter/body）を更新する。しかし path フィールド・entry_points・実ファイルが未更新のため、rename 後に `loom check` が path 不在で失敗する。

`promote_component()` が既にファイル移動ロジック（`Path.rename()` + 空ディレクトリ削除 + ロールバック）を持ち、参考実装として利用可能。

## Goals / Non-Goals

**Goals:**

- path フィールド内の old_name → new_name 文字列置換
- entry_points リスト内のパス更新
- ディレクトリ/ファイルの実 rename
- dry-run での全変更プレビュー
- 部分一致を防ぐ境界マッチ（`co-auto` が `co-autopilot` に波及しない）

**Non-Goals:**

- README.md / openspec/ / tests/*.bats / scripts/*.sh の参照更新
- rename のアンドゥ機能
- 複数コンポーネントの一括 rename

## Decisions

1. **実行順序**: ディレクトリ rename → deps.yaml 書き戻し → frontmatter/body 更新。ディレクトリを先に移動することで、deps.yaml 更新失敗時にファイルシステムのロールバックが可能（promote と同一パターン）。

2. **path 置換の境界マッチ**: path 文字列内で old_name を置換する際、`/old_name/` または `old_name/` のようなパス区切りを含む形でマッチさせ、部分文字列への波及を防ぐ。具体的には `old_name` がパスコンポーネントとして完全一致する場合のみ置換。

3. **entry_points 更新**: entry_points リストの各エントリに対し、path と同じ境界マッチルールで old_name → new_name を置換。

4. **ディレクトリ rename の条件**: path フィールドが存在し、そのパスの親ディレクトリ名に old_name が含まれる場合のみ実行。パスが存在しない場合（commands/ の単一ファイル等）はスキップ。移動先が既に存在する場合はエラーで中断。

5. **ロールバック**: promote_component() と同様に、deps.yaml バックアップ + ファイル移動のロールバックを実装。

## Risks / Trade-offs

- **部分一致リスク**: パスコンポーネント境界マッチで緩和するが、`/` 区切りの位置によっては edge case が残る可能性あり。テストで網羅。
- **rename 先存在チェック**: ディレクトリ rename 前に存在チェックを行うが、TOCTOU 競合のリスクは許容（CLI ツールのため並行実行は想定外）。
- **entry_points の空リスト**: entry_points が未定義の場合は空リストとして安全にスキップ。
