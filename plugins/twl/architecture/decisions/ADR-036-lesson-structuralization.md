# ADR-036: Lesson Structuralization MUST — doobidoo 保存を起点とした構造化チェーン

## Status

Accepted (2026-05-07)

## Context

### 観察された失敗パターン（2026-05-07 セッション）

#### 失敗 case 1: Wave 60 → Wave 63 で同 stuck pattern 再発

- Wave 60 で Pilot が自発的に board-status-update を実行（lesson 23 として doobidoo 保存）
- **SKILL.md / refs に逆移植せず** Wave 63 で observer が同じ計画ミス → orchestrator skip

#### 失敗 case 2: co-explore proxy 25min cycle 不適 検知漏れ

- co-explore B で menu 連発を 25min cycle で見逃し（lesson 24 として doobidoo 保存）
- **SKILL.md / monitor channel に組み込まず** ユーザー指摘で初対応

### 共通真因

- doobidoo 保存 ≠ 構造化
- 個別 lesson は記録されるが **architecture spec に組み込む方針** が文書化されていない
- 同じ lesson が次セッション/次 Wave で再消費される

### ユーザー指摘（2026-05-07、二重指摘）

> lesson を一回限りのものにするのではなく、skill なり hooks なり構造的にその教訓を活かして、うまく動作するように twl plugin に組み込むべき

> この方針そのものも architecture-spec などうまく使ってしっかり twl plugin に刻み込めるように工夫して

## Decision

任意の lesson（observer-pitfall / observer-lesson / observer-wave 等）を doobidoo に保存した後、
以下の 4 ステップのチェーンを完遂しない限り「完遂」と扱わないことを **MUST** とする。

### Lesson Structuralization Chain（4 step MUST）

1. **doobidoo 保存**（短期記憶 — 当セッション内の参照用）
2. **Issue 起票**（構造化候補化 — `gh issue create` で follow-up 実装タスク化）
3. **Wave 実装**（skill/refs/scripts への反映 PR — architecture に組み込む）
4. **永続文書化**（pitfalls-catalog.md / SKILL.md / ADR への正式追記）

doobidoo 保存のみで止まることは **NOT DONE** である。

### Rationale

- doobidoo は短期記憶（セッション内キャッシュ）であり、architecture SSOT ではない
- SKILL.md / refs に反映して初めて次セッション/次 Wave で自動適用される
- ADR / pitfalls-catalog への正式追記で再発防止が完結する

## Consequences

### Positive

- 個別 lesson が再消費されない（同じ失敗パターンの再発を防止）
- architecture-spec が事実上の SSOT として機能する
- 4 ステップ全完遂により：Issue 起票でタスク化 → Wave 実装で skill/refs に反映 → 永続文書化で次セッション以降の自動適用が保証される

### Negative / Trade-offs

- lesson 保存コストが増大する（4 step 完遂が義務）
- 軽微な lesson も Issue 起票が必要になる（将来的に粒度判断が必要な可能性）

## Alternatives Rejected

### 案A: doobidoo 保存のみ（現状維持）

doobidoo に lesson を保存するのみで終了。

**却下理由**: ADR-034 Context で確認済みの再発パターン（「doobidoo memory に lesson 保存しても LLM 内で運用に落ちない」）を解消しない。同セッション内で `memory hash 3ddf2a20` に lesson を保存した直後に同パターンが再発した実例（Wave 46 → 47）がある。

### 案B: doobidoo 保存 + 永続文書化のみ（Issue 起票・Wave 実装を省略）

doobidoo に保存し、その場で直接 SKILL.md / refs を編集する。

**却下理由**: Issue 起票なしでは変更が追跡不可能になる。また、即時編集はレビューなしで SKILL.md 等の重要ファイルを変更するリスクがあり、誤った lesson の伝播を招く可能性がある。Wave 実装（PR review）を経ることで品質を担保する。

## References

- Invariant N: `plugins/twl/refs/ref-invariants.md#invariant-n-lesson-structuralization`
- pitfalls-catalog.md §19: `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md`
- su-observer SKILL.md Step 1: `plugins/twl/skills/su-observer/SKILL.md`
- doobidoo hash: 422c9ee8 (meta-lesson 26)
- 関連 Issue: #1517, #1508, #1516
