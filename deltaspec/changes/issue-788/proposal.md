## Why

twill モノリポの不変条件 A-M（13 件）が `autopilot.md`、`CLAUDE.md`、`skills/su-observer/SKILL.md` 等に散在しており、更新時に複数ドキュメントを同期する必要があって変更コストが高く、正典（single source of truth）が存在しない。

## What Changes

- `plugins/twl/refs/ref-invariants.md` を新規作成し、不変条件 A-M の定義・根拠・検証方法・影響範囲を一本化
- `plugins/twl/architecture/domain/contexts/autopilot.md` の不変条件定義本文を `ref-invariants.md` へのリンクに置換
- `plugins/twl/CLAUDE.md` の不変条件 B 言及をリンク参照に更新
- `plugins/twl/skills/su-observer/SKILL.md` に SU-* と不変条件 A-M の境界を明示し `ref-invariants.md` リンクを追加
- `plugins/twl/tests/bats/invariants/autopilot-invariants.bats` の invariant-J/K grep 対象を `autopilot.md` → `refs/ref-invariants.md` に切替
- `plugins/twl/tests/bats/invariants/ref-invariants-structure.bats` を新規作成して 13 件の section 存在と書式を検証
- `plugins/twl/deps.yaml` に `ref-invariants` エントリを `type: reference` として追加
- `plugins/twl/README.md` の Refs 一覧を更新（18 → 19）

## Capabilities

### New Capabilities

- `plugins/twl/refs/ref-invariants.md`: 不変条件 A-M の正典ドキュメント。各条件の定義・根拠（ADR/DeltaSpec spec リンク）・検証方法（bats テスト名）・影響範囲を `## 不変条件 X: <title>` 形式で統一
- `ref-invariants-structure.bats`: `ref-invariants.md` の構造 lint（section 存在・書式・半角コロン強制）を自動検証
- `issue-788` が `plugins/twl/refs/` の参照ドキュメント体系（#789 自動生成ツールの source）を確立

### Modified Capabilities

- `autopilot-invariants.bats` の invariant-J/K: grep 対象を `ref-invariants.md` の新構造（`## 不変条件 J:` / `## 不変条件 K:`）に合わせて更新
- `autopilot.md` / `CLAUDE.md`: 不変条件の定義本文を削除し `ref-invariants.md` へのリンクに統一

## Impact

- **新規ファイル**: `plugins/twl/refs/ref-invariants.md`、`plugins/twl/tests/bats/invariants/ref-invariants-structure.bats`
- **変更ファイル**: `autopilot.md`、`CLAUDE.md`、`su-observer/SKILL.md`、`autopilot-invariants.bats`、`deps.yaml`、`README.md`
- **破壊的変更**: `autopilot.md` から不変条件定義を削除するため、`autopilot-invariants.bats` の J/K grep パターンを同一 PR で必ず更新（FAIL 回避）
- **依存**: `#789`（ref-invariants.md 構造を source として使用）が本 Issue 完了に依存
