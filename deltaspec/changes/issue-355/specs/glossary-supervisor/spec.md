## MODIFIED Requirements

### Requirement: Three-Layer Memory 定義の ADR-014 整合

`glossary.md` の `Three-Layer Memory` 定義は ADR-014 Decision 3 の正式層名称（Long-term Memory / Working Memory Externalization / Compressed Memory）と一致しなければならない（SHALL）。

#### Scenario: Three-Layer Memory 定義更新
- **WHEN** `glossary.md` の `Three-Layer Memory` 行の定義列を確認する
- **THEN** `Long-term Memory（永続）+ Working Memory Externalization（一時退避）+ Compressed Memory（compaction後）` と記述されている（SHALL）

#### Scenario: ADR-014 との整合確認
- **WHEN** ADR-014 Decision 3 の層名称と `glossary.md` の `Three-Layer Memory` 定義を比較する
- **THEN** 3 層すべての名称が ADR-014 の正式名称と完全一致している（SHALL）

## ADDED Requirements

### Requirement: Supervisor 6 用語の MUST セクション存在確認

`glossary.md` の MUST セクションに Supervisor 関連 6 用語（Supervisor, su-observer, SupervisorSession, su-compact, Three-Layer Memory, Wave）が存在しなければならない（SHALL）。

#### Scenario: 6 用語の存在確認
- **WHEN** `glossary.md` の MUST テーブルを参照する
- **THEN** Supervisor, su-observer, SupervisorSession, su-compact, Three-Layer Memory, Wave の 6 用語すべてが行として存在する（SHALL）

### Requirement: Observer 用語の MUST 外維持

Observer 関連用語（Observer, Observed, Live Observation）は MUST セクションに追加してはならない（SHALL）。これらは Observation context の用語であり、Supervisor context とは独立した層に属する。

#### Scenario: Observer 用語の SHOULD 維持
- **WHEN** `glossary.md` の MUST テーブルを参照する
- **THEN** Observer, Observed, Live Observation の各用語が MUST テーブルに存在しない（SHALL）

#### Scenario: Observer 用語の SHOULD 存在確認
- **WHEN** `glossary.md` の SHOULD テーブルを参照する
- **THEN** observer-evaluator 等の Observation context 用語が SHOULD テーブルに存在する（SHALL）
