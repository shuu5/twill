## Why

`co-architect` の責務再定義（#560）により、`architect-decompose` と `architect-issue-create` が `co-architect` の `calls` から削除された。現在これらのコンポーネントはどの controller/workflow からも呼び出されておらず、orphan 状態になっている。orphan コンポーネントは依存グラフの整合性を損ない、メンテナンスコストを増加させるため、廃止して削除する。

## What Changes

- `plugins/twl/deps.yaml` から `architect-decompose` と `architect-issue-create` のエントリを削除
- `plugins/twl/commands/architect-decompose.md` を削除
- `plugins/twl/commands/architect-issue-create.md` を削除

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `plugins/twl` の依存グラフが 2 件のコンポーネント削除により整合性が改善される（`twl check` で 0 violations、0 orphans が通る状態）

## Impact

- `plugins/twl/deps.yaml`: `architect-decompose`・`architect-issue-create` エントリ削除
- `plugins/twl/commands/architect-decompose.md`: ファイル削除
- `plugins/twl/commands/architect-issue-create.md`: ファイル削除
- `plugins/twl/refs/ref-project-model.md`・`ref-gh-read-policy.md`・`architecture/archive/migration/component-mapping.md`: 参照記述は archive/docs のため変更対象外
