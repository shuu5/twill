## MODIFIED Requirements

### Requirement: 完了済みセッションの --force 削除

autopilot-init.sh は完了済みセッション（session.json 内の全 issue が done）に対し、`--force` 指定時に経過時間に関係なく即座に削除しなければならない（SHALL）。running status の issue がある場合は従来通り 24h 制限を適用しなければならない（MUST）。

#### Scenario: 全 issue done + --force 指定 + 24h 未満
- **WHEN** session.json が存在し、全 issue の status が "done" で、経過時間が 20h で、`--force` が指定されている
- **THEN** セッションを削除し、初期化を続行する

#### Scenario: 全 issue done + --force 指定 + 24h 超
- **WHEN** session.json が存在し、全 issue の status が "done" で、経過時間が 30h で、`--force` が指定されている
- **THEN** セッションを削除し、初期化を続行する

#### Scenario: running issue あり + --force 指定 + 24h 未満
- **WHEN** session.json が存在し、1つ以上の issue が "running" で、経過時間が 20h で、`--force` が指定されている
- **THEN** ブロックし exit 1 で終了する

#### Scenario: running issue あり + --force 指定 + 24h 超
- **WHEN** session.json が存在し、1つ以上の issue が "running" で、経過時間が 30h で、`--force` が指定されている
- **THEN** stale セッションとして削除し、初期化を続行する

#### Scenario: issues フィールド不在 + --force 指定
- **WHEN** session.json が存在し、issues フィールドがないか空で、`--force` が指定されている
- **THEN** 完了済みとみなし、セッションを削除して初期化を続行する

#### Scenario: --force なし + 24h 未満
- **WHEN** session.json が存在し、経過時間が 24h 未満で、`--force` が指定されていない
- **THEN** 従来通りブロックし exit 1 で終了する
