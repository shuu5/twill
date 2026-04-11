## Context

ADR（Architecture Decision Record）は Markdown ファイルで管理されており、ステータスフィールドとヘッダー注記によって有効/廃止状態を表現する。ADR-013 が ADR-014 に置き換えられたため、両ファイルの更新が必要。

## Goals / Non-Goals

**Goals:**
- ADR-014 の Status フィールドを `Proposed` → `Accepted` に変更する
- ADR-013 の Status フィールドを `Accepted` → `Superseded by ADR-014` に変更する
- ADR-013 冒頭に Superseded 注記ブロックを追加する

**Non-Goals:**
- ADR のリナンバー（ADR-014 番号重複の解消は別 Issue）
- ADR の内容（本文）の変更

## Decisions

1. **Superseded 注記の形式**: `> **[SUPERSEDED]** This ADR has been superseded by [ADR-014](ADR-014-supervisor-redesign.md).` をドキュメント先頭に追加する
2. **Status フィールドの場所**: 各 ADR の YAML フロントマター（またはテーブル形式）の Status 行を直接編集する

## Risks / Trade-offs

- ADR-014 番号重複（`ADR-014-pilot-driven-workflow-loop.md` が別途存在）は本 Issue のスコープ外。変更対象ファイルのパスで明確に区別する
