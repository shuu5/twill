## Context

vision.md は architecture spec の living document として co-issue・co-architect が直接参照する設計意図の前方参照。ADR-014 Decision 6 により su-observer が Supervisor 型として分離されたが、vision.md はまだ Meta-cognitive / co-observer 表記のままである。変更対象は `plugins/twl/architecture/vision.md` の1ファイルのみで、コード変更は伴わない。

## Goals / Non-Goals

**Goals:**
- Supervisor カテゴリを Controller 操作カテゴリ表に追加する
- Meta-cognitive カテゴリの表記を Supervisor に更新する
- co-observer を su-observer に更新する
- Constraints セクションの controller 一覧から co-observer を除き、controller 数の記述を整合させる

**Non-Goals:**
- CLAUDE.md（plugins/twl/CLAUDE.md）の「Controller は7つ」記述の更新（別 Issue で対応）
- su-observer の実装変更
- ADR の新規作成（ADR-014 が既存）

## Decisions

1. **controller 数の表記**: `Controller は7つ（...co-observer）` を `Controller は6つ（...）+ Supervisor は1つ（su-observer）` に変更する。co-observer は controller ではなく Supervisor 型であるため、一覧から除外する
2. **カテゴリ表の更新**: `Meta-cognitive` 行を削除し `Supervisor` 行を追加。`該当 Controller` 列を `該当コンポーネント` に変更することも検討するが、最小変更として `co-observer` → `su-observer` の文字列置換のみ実施する
3. **説明文の整合**: `Non-implementation controller は co-autopilot を spawn しない` の文脈で co-observer が出てくる場合は su-observer に更新する

## Risks / Trade-offs

- vision.md を参照している他のドキュメントや CLAUDE.md が追従していない場合、一時的に乖離が生じる（次 Wave で修正予定）
- `Controller は6つ` という数の正確性は Issue #348 の types.yaml 変更内容に依存するため、先行 Issue の完了を確認すること
