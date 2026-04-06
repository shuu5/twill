## MODIFIED Requirements

### Requirement: backfill は新規 Issue を Todo で追加し、既存アイテムをスキップしなければならない（SHALL）

`project-board-backfill.sh` は未登録 Issue を Project Board に追加する際、Status を Todo に設定しなければならない（SHALL）。既存 Board アイテムとして登録済みの Issue は Status を変更せずスキップしなければならない（SHALL）。

#### Scenario: 未登録 Issue のバックフィル

- **WHEN** `project-board-backfill.sh` が未登録 Issue を処理する
- **THEN** Status=Todo で Board に追加される

#### Scenario: 登録済み Issue のスキップ

- **WHEN** `project-board-backfill.sh` が既存 Board アイテムを処理する
- **THEN** アイテムの Status は変更されず、スキップされる
