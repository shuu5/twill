## Core Domain Model

コンポーネント間の依存関係と役割を定義する。

```mermaid
classDiagram
    class `cli/twl` {
        +validate()
        +check()
        +chain()
        +spec()
        +loom()
    }

    class `plugins/twl` {
        +co-autopilot
        +co-issue
        +co-project
        +co-architect
        +co-utility
        +co-self-improve
    }

    class `plugins/session` {
        +session:spawn
        +session:fork
        +session:observe
    }

    class `test-fixtures` {
        +sample-plugin/
        +deltaspec-fixtures/
    }

    `plugins/twl` --> `cli/twl` : Open Host Service\n(twl validate/check/chain)
    `plugins/twl` --> `plugins/session` : spawns\n(co-autopilot)
    `plugins/twl` --> `test-fixtures` : test data
```

## 依存方向制約

| From | To | 許可 |
|------|----|------|
| plugins/\* | cli/twl | YES（Open Host Service） |
| plugins/twl | plugins/session | YES（spawns） |
| plugins/\* | test-fixtures | YES（test data のみ） |
| cli/twl | plugins/\* | **NO**（CLI はプラグインを知らない） |
| plugins/session | plugins/twl | **NO**（循環禁止） |
