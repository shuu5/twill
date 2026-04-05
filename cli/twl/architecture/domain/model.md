## Core Domain Model

```mermaid
classDiagram
    class Plugin {
        +name: string
        +version: "1.0" | "2.0" | "3.0"
        +entry_points: Path[]
        +skills: Map~string, Component~
        +commands: Map~string, Component~
        +agents: Map~string, Component~
        +scripts: Map~string, Component~
        +hooks: Map~string, Hook~
        +chains: Map~string, Chain~
    }
    class Component {
        +name: string
        +type: TypeName
        +path: Path
        +description: string
        +spawnable_by: TypeName[]
        +can_spawn: TypeName[]
        +calls: Call[]
        +model: ModelName
        +chain: string
        +parallel: boolean
        +user_invocable: boolean
        +tools: string[]
        +skills: string[]
        +checkpoint: boolean
        +checkpoint_ref: string
    }
    class Type {
        +name: TypeName
        +section: SectionName
        +can_spawn: TypeName[]
        +spawnable_by: TypeName[]
    }
    class Chain {
        +name: string
        +type: "A" | "B"
        +steps: Step[]
    }
    class Step {
        +component: string
        +step_in: StepIn[]
    }
    class Hook {
        +event: string
        +action: "validate" | "notify" | "ignore"
        +validation: string[]
    }
    class Change {
        +name: string
        +schema: "spec-driven"
        +created: date
        +artifacts: Artifact[]
    }
    class Artifact {
        +id: ArtifactId
        +outputPath: string
        +status: ArtifactStatus
        +dependencies: ArtifactId[]
        +unlocks: ArtifactId[]
    }
    Plugin "1" *-- "*" Component : owns
    Plugin "1" *-- "*" Chain : owns
    Plugin "1" *-- "*" Hook : owns
    Component "*" --> "1" Type : conforms to
    Chain "1" *-- "1..*" Step : ordered
    Step "1" --> "1" Component : references
    Component "*" --> "*" Component : calls
    Change "1" *-- "4" Artifact : owns
```

## 集約

### Plugin（ルート集約）
deps.yaml 全体に対応。全てのエンティティへのアクセスは Plugin 経由で行う。

- **境界内エンティティ**: Component, Chain, Step, Hook
- **アクセスルール**: Component は Plugin のセクション（skills/commands/agents/scripts）を経由して参照。直接のグローバルアクセスは禁止

### Type（独立集約）
types.yaml に対応。Plugin とは独立してロードされ、型検証ルールを提供する。

- **境界内エンティティ**: なし（Type 自身がルートかつ唯一のエンティティ）
- **アクセスルール**: TypeName で索引。Plugin の Component が Type を参照する（逆方向の参照なし）

### Change（独立集約）
openspec/changes/<name>/ に対応。Plugin とは独立したライフサイクルを持つ。

- **境界内エンティティ**: Artifact
- **アクセスルール**: Change 名で索引。Artifact は Change 経由でアクセス。Plugin 集約との直接参照なし

## 値オブジェクト

| 値オブジェクト | 型 | 説明 |
|--------------|------|------|
| Path | string | ファイルパス（plugin_root からの相対パス） |
| SectionName | "skills" \| "commands" \| "agents" \| "scripts" | deps.yaml のトップレベルセクション名 |
| TypeName | "controller" \| "workflow" \| "atomic" \| "composite" \| "specialist" \| "reference" \| "script" | コンポーネント型名 |
| Call | {skill: string} \| {command: string} \| {agent: string} \| {composite: string} \| {external: string} | 呼び出し先の参照 |
| StepIn | string | chain step 内のサブステップ参照 |
| ModelName | "sonnet" \| "opus" \| "haiku" \| string | AI モデル指定 |
| ArtifactId | "proposal" \| "design" \| "specs" \| "tasks" | Artifact 識別子 |
| ArtifactStatus | "ready" \| "blocked" \| "done" | Artifact の完了状態 |

## Context Map

```mermaid
flowchart TD
    TS[Type System]
    PS[Plugin Structure]
    CM[Chain Management]
    V[Validation]
    VZ[Visualization]
    R[Refactoring]
    SM[Spec Management]

    TS -->|upstream| PS
    TS -->|upstream| CM
    TS -->|upstream| V
    PS -->|upstream| CM
    PS -->|upstream| V
    PS -->|upstream| VZ
    PS -->|upstream| R
    CM -->|upstream| V
    R -->|downstream| V
```

**凡例**: 矢印は upstream → downstream の関係。upstream Context のエンティティを downstream Context が参照する。

**Spec Management** は現時点では独立した Context（他との依存なし）。openspec/ ディレクトリを操作対象とし、Plugin Structure とはデータを共有しない。
