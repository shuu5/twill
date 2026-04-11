## Context

`plugins/twl/skills/su-observer/SKILL.md` の Step 6 は現在「後続 Issue で詳細実装される」というプレースホルダーのみ記述されている。
`plugins/twl/commands/su-compact.md` は既に実装済みであり、`plugins/twl/architecture/designs/su-observer-skill-design.md` にも Step 6 の詳細設計が存在する。

設計仕様（`su-observer-skill-design.md`）によると、Step 6 は:
- `Skill(twl:su-compact)` 経由で su-compact コマンドに委譲する
- ユーザー指示のバリエーション: `compact`（自動）、`compact --wave`、`compact --task`、`compact --full`
- SU-5: context 50% 到達時に自動的に Step 6 を提案
- SU-6: Wave 完了時に su-compact を実行

## Goals / Non-Goals

**Goals:**
- su-observer SKILL.md Step 6 の詳細実装記述を追加する
- su-compact コマンドへの委譲フローを Step 6 に明記する
- SU-5（50% 閾値）と SU-6（Wave 完了時 compaction）制約を記述する
- 呼出シグネチャ（`--wave`、`--task`、`--full`）を Step 6 に明示する
- 禁止事項セクションに SU-5/SU-6 関連の禁止事項を追記する

**Non-Goals:**
- su-compact コマンド本体の変更
- su-observer 以外のスキルの変更
- context 消費量監視の実装コード追加

## Decisions

1. **委譲方式**: `Skill(twl:su-compact)` を直接呼び出す（コマンド実行の一貫性のため）
2. **呼出パターン記述**: 既存の設計ドキュメント（su-observer-skill-design.md）の Step 6 記述を SKILL.md に移植する形で実装
3. **禁止事項の追記場所**: 既存の `## 禁止事項（MUST NOT）` セクションに SU-5/SU-6 制約を追加する
4. **NOTE プレースホルダー削除**: 「後続 Issue で詳細実装される」NOTE を削除し、実際の内容に置き換える

## Risks / Trade-offs

- `su-compact.md` コマンドの仕様変更時に SKILL.md も更新が必要になる（二重管理のリスク）。ただし現時点では許容範囲。
- Step 6 の context 自動監視（SU-5）は Stop hook や定期チェックとの連携を前提とするが、本 Issue ではドキュメント記述のみで実装は対象外。
