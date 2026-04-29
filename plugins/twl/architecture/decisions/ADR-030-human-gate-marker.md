---
status: accepted
---

# ADR-030: ★HUMAN GATE マーカー規約

## Status

Accepted (2026-04-29)

## Context

twl の autonomous development は su-observer が核となり、controller を spawn + 監督し、ユーザーへの hand-off ポイントを判断する。既存規約に統一マーカーがなく、observer が「ユーザーへ escalate すべきポイント」を pitfalls-catalog / intervention-catalog から都度参照する必要があり、grep 不可・認知統一が困難であった。

feature-dev plugin が Phase 3 `CRITICAL: DO NOT SKIP` / Phase 5 `DO NOT START WITHOUT USER APPROVAL` の大文字強調マーカーを採用している先行事例がある。

## Decision

`★HUMAN GATE` を統一マーカーとして規約化する。

**記号**: `★HUMAN GATE`（U+2605 BLACK STAR + 半角スペース + 大文字 ASCII）

**主目的**: su-observer の Layer 1 (Confirm) / Layer 2 (Escalate) 介入境界の明示（intervention-catalog.md の 3 層プロトコルと整合）

**副目的**: autopilot / co-issue / co-architect 系の AskUserQuestion 直前 / merge-gate REJECT エスカレーション等の人介入ポイントの統一マーキング

**適用条件**: ユーザーの判断・承認が**必ず**必要なポイント（Layer 1 Confirm 以上の介入）

**適用しない条件**:
- AUTO モードで bypass される自動承認（Layer 0 Auto）
- 進捗報告
- 警告の単純表示

**段階導入方針**: 本 ADR で規約化し、observer 主体 3 箇所 + autopilot 補助 3 箇所 = 6 箇所のみ試験導入（Issue #1084）。横展開は別 Issue で運用知見後に判断する。

## Consequences

**ポジティブ**:
- `grep -rn '★HUMAN GATE'` で全 hand-off ポイントを一覧可能
- observer が介入境界を grep で確認でき、pitfalls-catalog の都度参照が不要になる
- autopilot 系のユーザー介入ポイントが視覚的に統一される

**ネガティブ**:
- 規約だけ作って実装で守られない場合、ノイズになる（→ ADR で明文化 + 段階導入で緩和）
- `★`（U+2605）はファイル編集者が意識してコピーする必要がある

## Alternatives

1. **大文字テキストのみ**（`DO NOT SKIP` 形式）: 先行事例だが grep での集約が困難
2. **コードコメント形式**（`<!-- HUMAN_GATE -->`）: grep 可能だが視認性が低い
3. **マーカーなし（現状維持）**: 認知コスト高・grep 不可

`★HUMAN GATE` はファイル種別（.md/.sh/.py）を問わず grep 可能で、U+2605 は BMP 範囲・UTF-8 3 bytes（`\xe2\x98\x85`）で全ツール対応済みのため採用した。
