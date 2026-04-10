## Why

ADR-014 の採択により、observer 型は supervisor 型へ完全置換され、`co-observer` は `su-observer` にリネームされる。
現在の `co-observer/SKILL.md` は ADR-013 の設計に基づいており、ADR-014 が定義する「プロジェクト常駐ライフサイクル」「`su-` prefix 命名」「supervisor 型」への更新が必要。

## What Changes

- `plugins/twl/skills/co-observer/` ディレクトリを `plugins/twl/skills/su-observer/` にリネーム
- `plugins/twl/skills/su-observer/SKILL.md` を ADR-014 設計に基づいて完全書き直し
  - frontmatter: `type: supervisor`, name: `twl:su-observer`, `spawnable_by: [user]`
  - Step 0〜7 の基本構造を定義（ADR-014 の Decision 2 プロジェクト常駐ライフサイクル準拠）
  - Step 4〜7 は後続 Issue で詳細化される基本構造のみ記載
- `deps.yaml` の `co-observer` → `su-observer` 参照更新

## Capabilities

### New Capabilities

- `supervisor` 型として `twl:su-observer` が登録される
- プロジェクト常駐ライフサイクル（main ディレクトリで起動、セッション横断で継続）
- Step 0〜7 の基本フロー構造（モード判定・セッション起動・監視・介入・Wave 管理・compaction・終了）

### Modified Capabilities

- 既存 `co-observer` の Step 0〜3 フロー（モード判定・pair 起動・supervise モード・delegate-test モード）が `su-observer` に移行・再設計
- `spawnable_by: [user]`（controller から独立した起動モデル）

## Impact

- `plugins/twl/skills/co-observer/` → 削除（`su-observer/` に置換）
- `plugins/twl/skills/su-observer/SKILL.md` → 新規作成
- `plugins/twl/deps.yaml` → `co-observer` 参照を `su-observer` に更新
- `twl validate` の通過が必須（type: supervisor が types.yaml に定義済み — #348 先行 Issue で対応）
