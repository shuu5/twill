# ADR-019: co-architect を Spec Implementation controller に再分類

**Status**: Accepted  
**Date**: 2026-04-13  
**Issue**: #557  
**Supersedes**: —  
**Related**: ADR-001 (autopilot-first), ADR-002 (controller consolidation), ADR-014 (supervisor redesign — co-architect was previously classified as Non-implementation)

---

## Context

`co-architect` は `vision.md` の「Controller 操作カテゴリ」テーブルで "Non-implementation" に分類されていた。Non-implementation の定義は「Issue 作成・設計・プロジェクト管理（コード変更・PR 作成を伴わない）」である。

しかし `co-architect` の実際の動作は以下を含む:

- `architecture/` ディレクトリへのファイル直接 Write（`vision.md`, `context-map.md`, `glossary.md`, ADR ファイル等）
- main worktree へのコミット
- （#5 対応後）PR 作成フロー

これは「コード変更・PR 作成を伴わない」という Non-implementation の定義と明確に矛盾する。また #5（co-architect branch/PR 化）で PR 作成フローを追加すると、Non-implementation 定義との乖離がさらに拡大する。

## Decision

**新カテゴリ「Spec Implementation」を導入し、co-architect をこのカテゴリに再分類する。**

Spec Implementation の定義: **Architecture spec（`architecture/` 配下のドキュメント）の変更・PR 作成を担う controller カテゴリ。**

- `vision.md` の Controller 操作カテゴリテーブルに「Spec Implementation」行を追加する
- `co-architect` を Non-implementation から Spec Implementation に移動する
- `glossary.md` の MUST 用語に「Spec Implementation」を登録する

## Consequences

### vision.md 変更

Controller 操作カテゴリテーブルが 5行 → 6行に拡大する:

| カテゴリ | 定義 | 該当 Controller |
|---|---|---|
| Implementation | コード変更・PR 作成を伴う操作 | co-autopilot のみ |
| **Spec Implementation** | **Architecture spec 変更・PR 作成** | **co-architect** |
| Non-implementation | Issue 作成・設計・プロジェクト管理 | co-issue, co-project |
| Utility | スタンドアロンユーティリティ操作 | co-utility |
| Observation | ライブセッション観察・問題検出・Issue 起票 | co-self-improve |
| Supervisor | controller の動作を監視・介入するメタレイヤー | su-observer |

テーブル直下の説明文を更新:「Non-implementation controller と Spec Implementation controller は co-autopilot を spawn しない。」

### glossary.md 変更

MUST 用語テーブルに「Spec Implementation」を追加する（ADR-019 参照付き）。

### SKILL.md・deps.yaml への影響

本 ADR は分類の記録のみ。co-architect の SKILL.md 変更は #4 で、deps.yaml の変更は #4・#5 で対応する。

## Alternatives

### Alternative A: 既存「Implementation」カテゴリに統合

co-architect を co-autopilot と同じ Implementation カテゴリに統合する案。

**採用しなかった理由**: Implementation は「コード変更・PR 作成を伴う操作」であり co-autopilot のみが担う設計（ADR-001）。co-architect を統合すると co-autopilot の責務が膨らみ過ぎ、「単一の実装 controller」という原則（ADR-002）が崩れる。また co-architect が扱う対象は Architecture spec ドキュメントであり、アプリケーションコードとは性質が異なる。

### Alternative B: ADR 例外として対応（分類変更せず記録のみ）

カテゴリテーブルは変更せず、co-architect が Non-implementation の例外である旨を注記で記録する案。

**採用しなかった理由**: 例外扱いは co-issue Step 1.5 の glossary 照合や他の LLM コンポーネントが「Non-implementation = PR 作成しない」と誤解するリスクを残す。明示的なカテゴリ定義によってドキュメントと実態を一致させることが ADR の本来の目的であり、注記による回避は技術的負債を増やす。
