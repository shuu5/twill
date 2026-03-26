## Core Domain Model

```mermaid
classDiagram
    class Plugin {
        name: string
        version: "2.0" | "3.0"
        entry_points: Path[]
    }
    class Component {
        name: string
        type: Type
        path: Path
        description: string
        calls: Call[]
    }
    class Type {
        name: string
        section: Section
        can_spawn: Type[]
        spawnable_by: Type[]
    }
    class Chain {
        name: string
        type: "A" | "B"
        steps: Component[]
    }
    Plugin "1" --> "*" Component
    Plugin "1" --> "*" Chain
    Component "*" --> "1" Type
    Chain "1" --> "*" Component
```

## 集約

- **Plugin**: deps.yaml 全体。ルート集約
- **Component**: 個別コンポーネント（controller, workflow, atomic, composite, specialist, reference, script）
- **Type**: types.yaml で定義される型ルール
- **Chain**: v3.0 のステップ順序定義
