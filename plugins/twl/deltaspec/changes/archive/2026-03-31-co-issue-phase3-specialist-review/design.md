## Context

co-issue の Phase 3（Per-Issue 精緻化ループ）は現在、同一セッション内で issue-dig → issue-structure → issue-assess を順次実行する。issue-assess は template-validator + context-checker の 2 specialist を並列実行するが、これらは Issue 品質の形式面のみを検証する。Issue の内容・仮定・盲点を検証する issue-dig は同一コンテキストで実行されるため、author ≠ reviewer の原則に反する。

既存の specialist 基盤（ref-specialist-output-schema、ADR-004 findings 形式、Agent tool によるコンテキスト非継承 spawn）はそのまま活用可能。

## Goals / Non-Goals

**Goals:**

- Phase 3 から issue-dig / issue-assess を廃止し、コンテキスト非継承の 2 specialist による並列レビューで代替
- 全 Issue × 2 specialist を一括並列 spawn し、結果を集約
- CRITICAL findings によるブロック機能（Phase 4 進行不可）
- `--quick` フラグで specialist レビュースキップ

**Non-Goals:**

- Phase 1, 2, 4 の変更
- issue-structure の変更
- template-validator / context-checker の変更（issue-assess 廃止に伴い呼び出し元がなくなるのみ）
- specialist の再帰的レビュー（split 後の再レビューは行わない）

## Decisions

### D1: issue-dig と issue-assess を廃止し、issue-critic + issue-feasibility に統合

issue-dig の 4 観点（AC 検証可能性、スコープ境界、依存関係、実装粒度）は issue-critic に吸収。issue-assess の形式チェック（template-validator）と コンテキストチェック（context-checker）は、新 specialist が上位互換として包含する。

**根拠**: 同一コンテキストの issue-dig は盲点排除に効果が薄い。issue-assess の 2 specialist（haiku）の形式チェックは有用だが、内容レビューの specialist に統合する方がトータルコストが低い。

### D2: specialist は Agent tool でコンテキスト非継承 spawn

Agent tool の通常 spawn（subagent_type 指定）を使用。co-issue セッションの会話コンテキストは継承されない。specialist には構造化された Issue body と対象ファイルパスを明示的に渡す。

**根拠**: コードレビューの author ≠ reviewer 原則を適用するための設計上の核心。

### D3: specialist の出力は ADR-004 findings 形式を拡張

既存の ref-specialist-output-schema（severity/confidence/file/line/message/category）をベースに、Issue レビュー向けに category を拡張する:

- `assumption`: 未検証の仮定
- `ambiguity`: 曖昧な記述
- `scope`: スコープ粒度・分割提案
- `feasibility`: 実装可能性・影響範囲

既存の category（vulnerability, bug 等）はコードレビュー specialist 用のため、別枠で追加。

### D4: 並列実行モデル — 全 Issue × 2 specialist を一括 spawn

全 Issue の構造化完了後、単一メッセージで全 specialist を一括 spawn する。5 Issue なら 10 agent 同時実行。Agent tool の並列実行で API 呼び出しを最適化。

### D5: findings severity → action マッピング

| severity | confidence | action |
|----------|-----------|--------|
| CRITICAL | >= 80 | Phase 4 ブロック。Issue 修正必須 |
| WARNING | any | ユーザー提示、修正任意 |
| INFO | any | ログのみ |

### D6: split 提案は最大 1 ラウンド

specialist が split を提案した場合、ユーザー承認後に分割を適用するが、分割後の新 Issue に対して specialist 再レビューは行わない（再帰防止）。

### D7: --quick フラグ

`--quick` 指定時は specialist レビューをスキップし、issue-structure のみで Phase 3 を完了する。trivial Issue 向け。

### D8: 削除対象のファイルと deps.yaml エントリ

- `commands/issue-dig.md`: 削除
- `commands/issue-assess.md`: 削除
- deps.yaml: `issue-dig`, `issue-assess` エントリ削除、`template-validator`, `context-checker` は他の呼び出し元がなければ残置（将来の再利用可能性）

## Risks / Trade-offs

### R1: API コスト増

5 Issue × 2 sonnet agent ≈ 300K tokens/回。ただし `--quick` でスキップ可能。従来の issue-dig + issue-assess（同一コンテキスト）と比較してトークン消費は増加するが、品質向上とのトレードオフ。

### R2: specialist が過剰な CRITICAL を出す可能性

品質基準リファレンス（ref-issue-quality-criteria）で severity 判定基準を明示し、過剰ブロックを防ぐ。

### R3: template-validator / context-checker が孤立

issue-assess 廃止により呼び出し元がなくなる。deps.yaml に残置するが、can_spawn リストからは co-issue が外れる。将来の merge-gate 等での再利用は可能。
