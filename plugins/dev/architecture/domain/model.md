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
    class ProjectBoard {
        project_number: number
        owner: string
        linked_repos: string[]
    }
    class Orchestrator {
        poll_interval: number
        nudge_timeout: number
        health_check: HealthCheck
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
    Controller ..> ProjectBoard : queries (Issue 選択)
    Orchestrator --> IssueState : polls
    Orchestrator --> Script : executes (health-check, crash-detect)
```

### Controller Spawning 関係図

```mermaid
graph TD
    subgraph "Controllers (entry_points)"
        CA["co-autopilot<br/>(Implementation)"]
        CI["co-issue<br/>(Non-implementation)"]
        CP["co-project<br/>(Non-implementation)"]
        CR["co-architect<br/>(Non-implementation)"]
    end

    subgraph "Spawnable Types"
        WF["workflow<br/>(chain-driven)"]
        CM["composite<br/>(multi-step)"]
        AT["atomic<br/>(single-step)"]
        SP["specialist<br/>(parallel AI)"]
        RF["reference<br/>(read-only)"]
    end

    CA -->|spawns| CM
    CA -->|spawns| AT
    CA -->|spawns| SP

    CI -->|spawns| CM
    CI -->|spawns| AT
    CI -->|spawns| SP
    CI -->|spawns| RF

    CP -->|spawns| CM
    CP -->|spawns| AT
    CP -->|spawns| RF

    CR -->|spawns| AT
    CR -->|spawns| RF

    CA -.->|orchestrates| WF
    WF -->|chain steps| AT
    WF -->|chain steps| CM
    CM -->|delegates| AT
    CM -->|delegates| SP
    AT -->|executes| SC["script<br/>(bash/python)"]
```

**Spawning ルール**:
- co-autopilot のみが workflow を orchestrate できる（Implementation 操作のレビュー・テスト）
- co-issue は specialist を spawn できる（issue-critic, issue-feasibility, worker-codex-reviewer）
- co-project は composite + atomic（構成変更の最小単位で操作）
- co-architect は atomic + reference のみ（設計情報の参照・評価）

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

### 統一状態ファイルスキーマ

#### issue-{N}.json（per-Issue）

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| issue | number | Yes | GitHub Issue 番号 |
| status | `running` \| `merge-ready` \| `done` \| `failed` | Yes | 状態遷移図の状態値 |
| branch | string | Yes | worktree のブランチ名 |
| pr | null \| number | Yes | PR 番号（未作成時は null） |
| window | string | Yes | tmux ウィンドウ名（例: `ap-#42`） |
| started_at | string (ISO 8601) | Yes | 開始時刻 |
| current_step | string | Yes | chain の現在ステップ名 |
| retry_count | number (0-1) | Yes | merge-gate リトライ回数 |
| fix_instructions | null \| string | Yes | fix-phase 用修正指示テキスト |
| merged_at | null \| string (ISO 8601) | Yes | マージ完了時刻 |
| files_changed | string[] | Yes | 変更されたファイルパス配列 |
| failure | null \| { message, step, timestamp } | Yes | 失敗情報 |

**アクセスルール**: Pilot = read only, Worker = write。同一 Issue の並行書き込みは発生しない（per-Issue ファイル）。

#### session.json（per-autopilot-run）

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| session_id | string | Yes | セッション一意識別子 |
| plan_path | string | Yes | plan.yaml のパス |
| current_phase | number | Yes | 現在の Phase 番号 |
| phase_count | number | Yes | 全 Phase 数 |
| cross_issue_warnings | { issue, target_issue, file, reason }[] | Yes | cross-issue 警告 |
| phase_insights | { phase, insight, timestamp }[] | Yes | Phase 完了時の知見 |
| patterns | { [name]: { count, last_seen } } | Yes | 検出パターン集約 |
| self_improve_issues | number[] | Yes | 自己改善で起票された Issue 番号 |

**排他制御**: session.json は Pilot のみが書き込む。複数 autopilot セッションの同時実行は禁止（session.json 存在チェックで排他）。

### Orchestrator パターン

Pilot 内で Issue 実行ループを管理するコンポーネント。

```mermaid
flowchart TD
    O["Orchestrator (Pilot)"] --> WT["worktree-create.sh"]
    WT --> L["autopilot-launch --worktree-dir"]
    L --> P["autopilot-poll (10秒間隔)"]
    P --> HC["health-check.sh"]
    P --> CD["crash-detect.sh"]
    P --> SR["state-read.sh"]
    P -->|停滞検出| N["nudge (プロンプト再注入)"]
    P -->|完了検出| MG["merge-gate"]
    MG -->|PASS| CL["cleanup<br/>(tmux → worktree → remote branch)"]
```

**Orchestrator の責務**:
- Worktree 事前作成（Worker 起動前に worktree-create.sh を実行、不変条件 B）
- Worker の起動（worktree ディレクトリで cld セッション開始、`--worktree-dir`）
- 状態ポーリング（state-read.sh で issue-{N}.json を監視）
- クラッシュ検知（crash-detect.sh で tmux window 消失を検出）
- ヘルスチェック（health-check.sh で chain_stall を検出）
- nudge（停滞 Worker へのプロンプト再注入）
- クリーンアップ（merge-gate 成功後: tmux kill-window → worktree-delete → git push --delete）

### Chain 定義と実行フロー

```mermaid
flowchart TD
    subgraph "Chain 定義 (deps.yaml chains)"
        CH["chain: pr-cycle"]
        S1["step 1: verify"]
        S2["step 2: parallel-review"]
        S3["step 3: test"]
        S4["step 4: fix (conditional)"]
        S5["step 5: report"]
        CH --> S1 --> S2 --> S3 --> S4 --> S5
    end

    subgraph "実行時"
        W["Workflow (chain runner)"]
        W -->|"step 1"| A1["atomic: ts-preflight"]
        W -->|"step 2"| A2["composite: phase-review"]
        A2 -->|"parallel spawn"| SP1["specialist: worker-code-reviewer"]
        A2 -->|"parallel spawn"| SP2["specialist: worker-security-reviewer"]
        W -->|"step 3"| A3["atomic: pr-test"]
        W -->|"step 4"| A4["composite: fix-phase"]
        W -->|"step 5"| A5["atomic: pr-cycle-report"]
    end

    S1 -.->|maps to| A1
    S2 -.->|maps to| A2
    S3 -.->|maps to| A3
    S4 -.->|maps to| A4
    S5 -.->|maps to| A5
```

**Chain の役割**: deps.yaml の chains セクションがステップ順序を宣言的に定義する。Workflow は chain 定義を読み取り、各ステップに対応する atomic/composite コマンドを逐次実行する。順序変更は deps.yaml の編集のみで完結し、Workflow のコード変更は不要。

### Project Board 統合

```mermaid
flowchart LR
    subgraph "GitHub Projects V2"
        PB["loom-dev-ecosystem (#3)"]
        PB -->|"linked"| R1["shuu5/loom-plugin-dev"]
        PB -->|"linked"| R2["shuu5/loom"]
    end

    subgraph "Autopilot"
        PI["Pilot"]
        PI -->|"gh project item-list<br/>Status=Todo"| PB
        PI -->|"gh project item-edit<br/>Status=In Progress/Done"| PB
    end

    subgraph "co-issue"
        IS["Issue 作成"]
        IS -->|"project-board-sync"| PB
    end
```

**二層構造**: ローカル状態ファイル（即時性）+ Project Board（永続化・可視化）。
Board 同期失敗は autopilot をブロックしない（WARNING のみ）。
