## Context

`glossary.md` の Supervisor 6 用語（Supervisor, su-observer, SupervisorSession, su-compact, Three-Layer Memory, Wave）は ADR-014 策定に伴い追加済み。ただし `Three-Layer Memory` の定義が ADR-014 Decision 3 の正式層名称と乖離している。変更対象は `glossary.md` の 1 行（Three-Layer Memory 行の定義列）のみ。

ADR-014 Decision 3 の正式名称:
- `Long-term Memory`: sharp/fixed、永続。Memory MCP + auto-memory 実装
- `Working Memory Externalization`: sharp/fixed、一時的。PreCompact→ファイル→PostCompact で実現
- `Compressed Memory`: dynamic/fuzzy、セッション内。compaction 後の圧縮コンテキスト

## Goals / Non-Goals

**Goals:**
- `Three-Layer Memory` の定義を ADR-014 / supervision.md の正式層名称に整合させる
- Supervisor 6 用語全体の ADR-014 整合性を最終確認する
- Observer 関連用語が SHOULD に残ることが意図的であると確認する

**Non-Goals:**
- SHOULD 用語の追加・削除
- 照合ポリシーの変更
- glossary.md 以外のファイルの編集

## Decisions

**決定 1: Three-Layer Memory 定義の層名称を ADR-014 準拠に修正**

現状の定義 `Working Memory（context）+ Externalized Memory（doobidoo/ファイル）+ Compressed Memory（compaction後）` は ADR-014 Decision 3 の正式名称と一致しない。MUST 用語はドメインモデルの SSOT であるため、ADR-014 の最終名称に統一する。

修正後: `Long-term Memory（永続）+ Working Memory Externalization（一時退避）+ Compressed Memory（compaction後）`

**決定 2: Observer 関連用語は SHOULD のまま維持**

Observer/Observed/Live Observation 等の Observation context 用語は co-self-improve の責務に属し、Supervisor の責務とは異なるレイヤー。MUST 昇格は不要。supervision.md の co-self-improve との境界定義と一致する。

**決定 3: co-observer 参照の有無を確認**

glossary.md に `co-observer` 用語は存在しない（ADR-013 時代に追加されなかった）。su-observer が MUST に存在するため、旧 co-observer 参照の残存はなし。

## Risks / Trade-offs

- **リスク低**: 変更は 1 行の定義文のみ。他の artifact・コード・テストへの影響なし
- **参照整合性**: `Three-Layer Memory` 定義内で各層名を変更することで、supervision.md や ADR-014 を参照するユーザーが一致を確認できる
