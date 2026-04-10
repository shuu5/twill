## 1. 整合性確認

- [x] 1.1 ADR-014 Decision 3 の三層記憶モデル層名称を確認する
- [x] 1.2 `glossary.md` の `Three-Layer Memory` 定義と ADR-014 の層名称を比較する
- [x] 1.3 Supervisor 6 用語（Supervisor, su-observer, SupervisorSession, su-compact, Three-Layer Memory, Wave）が MUST セクションに存在することを確認する
- [x] 1.4 Observer 関連用語（Observer, Observed, Live Observation）の整合性を確認する（MUST テーブルに存在、Context=Observation で Supervisor 用語と重複・矛盾なし）

## 2. 定義修正

- [x] 2.1 `glossary.md` の `Three-Layer Memory` 定義を ADR-014 準拠の層名称に修正する
  - 修正箇所: `Working Memory（context）+ Externalized Memory（doobidoo/ファイル）+ Compressed Memory（compaction後）`
  - 修正後: `Long-term Memory（永続）+ Working Memory Externalization（一時退避）+ Compressed Memory（compaction後）`

## 3. 最終確認

- [x] 3.1 修正後の定義が ADR-014 / supervision.md の記述と整合していることを確認する
- [x] 3.2 `twl check` を実行（既存 Critical: post-change-apply dispatch_mode mismatch — 今回の変更と無関係）
