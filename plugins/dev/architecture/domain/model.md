## Core Domain Model

### クラス図

```mermaid
classDiagram
    class Controller {
        name: co-*
        type: controller
    }
    class Workflow {
        name: workflow-*
        chain: Chain
    }
    class AtomicCommand {
        name: string
        type: atomic
    }
    class Specialist {
        name: worker-*
        model: haiku|sonnet
        output_schema: standard|custom
    }
    class Script {
        name: string
        path: scripts/*.sh
    }
    class IssueState {
        issue: number
        status: running|merge-ready|done|failed
        branch: string
        pr: number|null
        window: string
        started_at: string
        current_step: string
        retry_count: number
        fix_instructions: string|null
        merged_at: string|null
        files_changed: string[]
        failure: object|null
    }
    class SessionState {
        session_id: string
        plan_path: string
        current_phase: number
        phase_count: number
        cross_issue_warnings: CrossIssueWarning[]
        phase_insights: PhaseInsight[]
        patterns: Map
        self_improve_issues: number[]
    }
    class Phase {
        number: number
        issues: number[]
        depends_on: number[]
        status: pending|running|done|failed
    }
    class AutopilotPlan {
        phases: Phase[]
        total_issues: number
        critical_path: number[]
    }
    Controller --> Workflow : spawns
    Workflow --> AtomicCommand : calls (chain steps)
    Workflow --> Specialist : spawns (parallel)
    AtomicCommand --> Script : executes (Bash)
    Controller ..> IssueState : manages
    Controller ..> SessionState : manages
    SessionState --> AutopilotPlan : references
    AutopilotPlan *-- Phase : contains
    Phase ..> IssueState : tracks
```

### Issue 状態遷移図

```mermaid
stateDiagram-v2
    [*] --> running : Issue割り当て
    running --> merge_ready : 全ステップ完了
    running --> failed : crash/timeout/ステップ失敗
    merge_ready --> done : merge-gate PASS
    merge_ready --> failed : merge-gate REJECT
    failed --> running : retry (retry_count < 1)
    done --> [*]
```

#### 状態遷移表

| From | Event | To | 条件 |
|------|-------|----|------|
| (初期) | Issue 割り当て | running | -- |
| running | 全ステップ完了 | merge-ready | merge-gate に進む |
| running | ステップ失敗 / crash | failed | 不変条件 G: クラッシュは必ず検知 |
| merge-ready | merge-gate PASS | done | 終端状態 |
| merge-ready | merge-gate REJECT | failed | review findings あり |
| failed | retry 判定 | running | retry_count < 1（不変条件 E） |
| failed | retry 上限到達 | failed (確定) | retry_count >= 1、Pilot に報告 |

- `done` は完全終端状態（逆行不可）
- `failed (確定)` からの復帰は Pilot による手動介入のみ
- merge 失敗時に rebase は試みない（停止のみ、不変条件 F）
