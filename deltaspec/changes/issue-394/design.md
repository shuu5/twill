## Context

ADR-014 の Decision 1 により `co-observer` が `su-observer`（Supervisor クラス）に改名された。`plugins/twl/CLAUDE.md` は LLM セッション起動時に参照されるドキュメントであり、旧記述が残ることで Controller 数が7つと誤認識される。

## Goals / Non-Goals

**Goals:**
- `plugins/twl/CLAUDE.md` の Controller 数を6つに修正する
- `su-observer` を Supervisor として明示する

**Non-Goals:**
- コードや他ドキュメントの変更
- ADR-014 本体の変更

## Decisions

- Controller テーブルを6行に縮小し `co-observer` 行を削除
- 「Supervisor は1つ」の見出しと `su-observer` テーブルを追加
- ヘッダー「Controller は7つ」を「Controller は6つ」に変更

## Risks / Trade-offs

- 変更はドキュメントのみのため技術的リスクなし
