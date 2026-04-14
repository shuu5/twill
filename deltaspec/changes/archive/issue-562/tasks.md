## 1. orphan 確認

- [x] 1.1 `plugins/twl/` で `twl check` を実行し architect-decompose と architect-issue-create が orphan であることを確認

## 2. deps.yaml からエントリ削除

- [x] 2.1 `plugins/twl/deps.yaml` から `architect-decompose` エントリを削除
- [x] 2.2 `plugins/twl/deps.yaml` から `architect-issue-create` エントリを削除

## 3. コマンドファイル削除

- [x] 3.1 `plugins/twl/commands/architect-decompose.md` を削除
- [x] 3.2 `plugins/twl/commands/architect-issue-create.md` を削除

## 4. 検証

- [x] 4.1 `plugins/twl/` で `twl check` を実行し violations=0、orphans=0 を確認
