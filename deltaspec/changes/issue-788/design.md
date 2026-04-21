## Context

twill モノリポの不変条件 A-M（13 件）は現在 `autopilot.md`（主箇所）、`CLAUDE.md`、`su-observer/SKILL.md` 等に散在する。`autopilot-invariants.bats` は A-K の 11 件を実装済みで、J/K は `autopilot.md` を直接 grep している。`deps.yaml` 体系における `type: reference` ドキュメントを新設することで、#789 の自動生成ツールが parse できる単一 source を確立する。

## Goals / Non-Goals

**Goals:**

- `plugins/twl/refs/ref-invariants.md` を正典として不変条件 A-M を一本化
- 既存ドキュメントの定義重複を削除しリンク参照に統一
- `autopilot-invariants.bats` の J/K grep パターンを新構造に合わせて更新（テスト FAIL 回避）
- `ref-invariants-structure.bats` で構造 lint を自動化
- `deps.yaml` に `type: reference` エントリ追加

**Non-Goals:**

- 不変条件 L/M の bats テスト生成（#789 スコープ）
- SU-1〜SU-7 の定義移動（`su-observer/SKILL.md` に維持）
- 不変条件 A-M の内容変更・追加・削除

## Decisions

**D1: セクション形式**
`## 不変条件 X: <title>`（半角コロン、半角大文字 A-M）を採用。#789 の `## 不変条件 [A-M]` regex が確実に抽出できる。全角文字混入を `ref-invariants-structure.bats` で lint する。

**D2: 根拠フィールドの分類**
- H/A/C/L: ADR 欄が `autopilot.md` テーブルで空 → "ADR なし — 慣習的制約" と明記
- D/E/G/I/J/K: ADR ではなく `autopilot-lifecycle.md` / `merge-gate.md` 等の DeltaSpec spec ファイルへのリンク

**D3: 検証方法フィールド**
- A-K: 既存 `autopilot-invariants.bats` のテスト関数名を記載
- L/M: "#789 で bats テスト生成予定" と注記し bats 関数名は空欄

**D4: `autopilot-invariants.bats` 更新タイミング**
AC #2（`autopilot.md` 定義削除）と AC #6（bats 参照先切替）を同一 PR でアトミックに実装。先に定義を削除して bats を放置するとテスト FAIL が発生するため、必ず同時変更とする。

**D5: `deps.yaml` 型ルール**
`plugins/twl/refs/` 配下は `type: reference` を使用（`/twl:ref-types` 規約準拠）。

**D6: README 更新**
Refs セクションの合計カウントを 18 → 19 に更新し、`ref-invariants` エントリを追加。

## Risks / Trade-offs

| リスク | 対策 |
|--------|------|
| `autopilot.md` 定義削除後に J/K bats が FAIL | D4 でアトミック更新を保証 |
| 半角/全角混入による #789 parse エラー | `ref-invariants-structure.bats` で lint |
| L/M の検証方法が未定 | "#789 で生成予定" 注記で明示的に scope 外と宣言 |
| 不変条件の内容が `autopilot.md` と乖離する可能性 | 移行時に定義を逐語コピーし、変更しない |
