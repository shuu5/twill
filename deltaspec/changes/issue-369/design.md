## Context

ADR-014 による supervisor 再設計で `co-observer` が `su-observer` に改名された（Issue #356 で SKILL.md 作成済み）。`co-self-improve` SKILL.md は旧名称を9箇所参照しており、`deps.yaml` の `spawnable_by` も古い値を持つ。変更は純粋なテキスト置換であり、機能ロジックへの影響はない。

## Goals / Non-Goals

**Goals:**
- `co-self-improve/SKILL.md` 内の全 `co-observer` 参照を `su-observer` に更新する
- `deps.yaml` の `co-self-improve` エントリ `spawnable_by` を `su-observer` に更新する

**Non-Goals:**
- `co-self-improve` の動作変更
- 他のスキルの参照更新
- アーキテクチャや依存関係の変更

## Decisions

1. **一括置換**: SKILL.md 内の全 `co-observer` をテキスト置換で `su-observer` に変更する。対象行: L5, L7, L13, L20, L27, L28, L41, L47, L49
2. **deps.yaml 更新**: `loom` CLI ではなく直接 Edit ツールで `spawnable_by` を更新する（構造変更ではないため）
3. **検証方法**: 変更後に `grep co-observer` で残存参照がないことを確認する

## Risks / Trade-offs

- **リスク**: なし（純粋なテキスト置換、機能変更なし）
- **トレードオフ**: なし
