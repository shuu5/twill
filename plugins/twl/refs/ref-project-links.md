---
type: reference
---

# project-links.yaml — 外部リンク集約ガイド

## 概要

`project-links.yaml`（リポジトリルート配置）は、Project Board 番号・URL・リポジトリ名など、複数 CLAUDE.md / SKILL.md にハードコードされていた外部リンク情報の SSOT。
番号変更時は `project-links.yaml` のみ編集すれば全体に反映される。

## スキーマ

```yaml
project_board:
  owner: shuu5
  number: 6
  name: twill-ecosystem
  url: https://github.com/users/shuu5/projects/6
repo:
  owner: shuu5
  name: twill
```

## CLI — twl config get

```bash
twl config get project-board.number   # → 6
twl config get project-board.owner    # → shuu5
twl config get project-board.name     # → twill-ecosystem
twl config get project-board.url      # → https://github.com/users/shuu5/projects/6
twl config get repo.owner             # → shuu5
twl config get repo.name              # → twill
```

キーはハイフン（`project-board.number`）・アンダースコア（`project_board.number`）どちらでも可。

## 使用例

```bash
# Board アイテム取得（グローバル CLAUDE.md の推奨コマンド）
gh project item-list "$(twl config get project-board.number)" \
  --owner "$(twl config get project-board.owner)" \
  --format json --limit 200 \
  | jq -r '.items[] | select(.status != "Done") | "\(.content.number) [\(.status)] \(.content.title)"'
```

## 更新ルール

- Project Board 番号・URL が変更された場合: `project-links.yaml` のみ編集してコミット
- CLAUDE.md / SKILL.md に `(#N)` 形式でハードコードしてはならない（代わりに本ファイル参照）
