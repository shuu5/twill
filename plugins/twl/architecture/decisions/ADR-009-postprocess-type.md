# ADR-009: autopilot-phase-postprocess 型維持（atomic）

## Status
Accepted

## Context

Issue #67「co-autopilot コンテキスト整理」の実装時、`autopilot-phase-postprocess` を workflow に昇格させるか（選択肢A）、atomic を維持するか（選択肢B）を検討した。

`autopilot-phase-postprocess` は内部で以下の 4 コマンドを逐次実行する:

1. `autopilot-collect` — Phase 内 Issue の PR 差分収集
2. `autopilot-retrospective` — Phase の成功/失敗パターン分析
3. `autopilot-patterns` — 繰り返しパターン検出
4. `autopilot-cross-issue` — 次 Phase 向け依存チェック（最終 Phase は除く）

## Decision

**選択肢B（atomic 維持）を採用する。**

### 理由

1. **コンテキスト変数への強い依存**: `$P`（Phase番号）、`$SESSION_STATE_FILE`、`$PLAN_FILE`、`$SESSION_ID`、`$PHASE_COUNT` など、呼び出し元 co-autopilot の Phase ループ内変数を直接参照する。workflow に昇格するとこれらを引数として明示的に渡す設計変更が必要になり、co-autopilot SKILL.md の改修コストが高い。

2. **inline 実行はスポーンではない**: 子コマンドを `Read → 実行` する形式は Agent spawn ではなく、LLM コンテキスト内のインライン実行。`can_spawn: []` は型的に正しい。

3. **出力変数の返却**: `$PHASE_INSIGHTS`・`$CROSS_ISSUE_WARNINGS` を呼び出し元に返す必要がある。workflow は呼び出し元との変数共有機構を持たない。

4. **範囲外**: Issue #67 のスコープは "self-improve context の委譲" であり、phase 処理ロジックの変更は含まない。

### 選択肢Aを採用しない理由

- co-autopilot SKILL.md のロジック変更を伴い、Issue スコープ外となる（Issue #67 の制約: "co-autopilot SKILL.md のロジック変更はスコープ外"）
- 変数受け渡しの再設計コストが高く、リグレッションリスクがある

## Consequences

- `autopilot-phase-postprocess` は `type: atomic`、`can_spawn: []` のまま維持
- `autopilot-collect`、`autopilot-retrospective`、`autopilot-patterns`、`autopilot-cross-issue` は co-autopilot の calls に直接列挙された状態を維持（postprocess の間接依存として）
- 将来 Phase ループを大規模リファクタリングする際に再検討可能
