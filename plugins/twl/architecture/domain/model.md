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
        status: running|merge-ready|done|failed|conflict
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
    class Supervisor {
        name: su-*
        type: supervisor
        supervised: Controller[]
    }
    class InterventionRecord {
        intervention_id: string
        supervisor: string
        target_controller: string
        layer: string
        status: detected|intervening|resolved
        detected_at: string
        resolved_at: string|null
        reason: string
    }
    class Protocol {
        participants: string[]
        pinned_sha: string
        interface_contract: string
    }
    class CrossRepoDependency {
        provider_repo: string
        consumer_repo: string
        protocol_name: string
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
    Supervisor ..> Controller : supervises
    Supervisor *-- InterventionRecord : records
    Protocol "Provider" --> "Consumer" CrossRepoDependency : pins
```

### Controller Spawning 関係図

```mermaid
graph TD
    subgraph "Controllers (entry_points)"
        CA["co-autopilot<br/>(Implementation)"]
        CI["co-issue<br/>(Non-implementation)"]
        CP["co-project<br/>(Non-implementation)"]
        CR["co-architect<br/>(Spec Implementation)"]
        CU["co-utility<br/>(Utility)"]
        CS["co-self-improve<br/>(Observation)"]
        SO["su-observer<br/>(Meta-cognitive)"]
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

    CU -->|spawns| AT
    CU -->|spawns| RF

    CS -->|spawns| AT
    CS -->|spawns| SP
    CS -.->|orchestrates| WF

    SO -.->|supervises| CA
    SO -.->|supervises| CI
    SO -.->|supervises| CP
    SO -.->|supervises| CR
    SO -.->|supervises| CU
    SO -.->|supervises| CS
    SO -->|spawns| WF
    SO -->|spawns| AT
    SO -->|spawns| CM
    SO -->|spawns| SP
    SO -->|spawns| RF

    CA -.->|orchestrates| WF
    WF -->|chain steps| AT
    WF -->|chain steps| CM
    CM -->|delegates| AT
    CM -->|delegates| SP
    AT -->|executes| SC["script<br/>(bash/python)"]
```

**Spawning ルール**:
- co-autopilot は Implementation workflow を orchestrate できる（レビュー・テスト）
- co-self-improve は Observation workflow を orchestrate できる（ADR-011: ライブ観察ループ）
- co-issue は workflow-issue-lifecycle Worker を spawn する。specialist の実行は各 Worker セッション内に閉じる（ADR-017）
- co-project は composite + atomic（構成変更の最小単位で操作）
- co-architect は atomic + reference のみ（設計情報の参照・評価）
- su-observer は全 controller を supervise できる（ADR-013: Observer 型）。spawn 関係は controller と同等（workflow, atomic, composite, specialist, reference）
- co-self-improve と su-observer の共存: co-self-improve は Observation workflow を orchestrate し内部状態を改善する。su-observer は全 controller を meta-cognitive レイヤーで supervise し介入記録（InterventionRecord）を管理する

### Issue 状態遷移図

```mermaid
stateDiagram-v2
    [*] --> running : Issue割り当て
    running --> merge_ready : 全ステップ完了（Worker が宣言）
    running --> failed : crash/timeout/ステップ失敗
    merge_ready --> done : merge-gate PASS（Pilot がマージ後に設定）
    merge_ready --> failed : merge-gate REJECT 2回目（リトライ上限）
    merge_ready --> conflict : deps.yaml コンフリクト検出
    failed --> running : retry（retry_count < 1）
    failed --> done : --force-done（緊急時のみ、override_reason 必須）
    conflict --> merge_ready : Pilot リベース後（conflict_retry_count < 1）
    conflict --> failed : conflict リトライ上限超過
    done --> [*]
```

#### 状態遷移表

| From | Event | To | 条件 |
|------|-------|----|------|
| (初期) | Issue 割り当て | running | -- |
| running | 全ステップ完了 | merge-ready | merge-gate に進む |
| running | ステップ失敗 / crash | failed | 不変条件 G: クラッシュは必ず検知 |
| merge-ready | merge-gate PASS | done | 終端状態 |
| merge-ready | merge-gate REJECT 2回目 | failed | リトライ上限（不変条件 E） |
| merge-ready | deps.yaml コンフリクト検出 | conflict | Pilot がリベースを試行 |
| conflict | Pilot リベース成功 | merge-ready | conflict_retry_count < 1 |
| conflict | conflict リトライ上限超過 | failed | 回復不可 |
| failed | retry 判定 | running | retry_count < 1（不変条件 E） |
| failed | retry 上限到達 | failed (確定) | retry_count >= 1、Pilot に報告 |
| failed | --force-done | done | 緊急時のみ（override_reason 必須） |

- `done` は完全終端状態（逆行不可）
- `failed (確定)` からの復帰は Pilot による手動介入のみ
- merge 失敗時に rebase は試みない（停止のみ、不変条件 F）
- `conflict` は deps.yaml 変更 Issue の並列実行時に発生しうる（不変条件 H）

> **SSOT ルール（ADR-018）**: 外部観察者は `status` のみを参照する。`current_step` は orchestrator inject 機構の内部フィールド

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
| failure | null \| { message, step, timestamp, reason? } | Yes | 失敗情報。reason: `merge_gate_rejected` \| `merge_gate_rejected_final` \| `merge_failed` |

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

#### intervention-{N}.json（per-Observer-intervention）

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| intervention_id | string | Yes | 介入一意識別子 |
| supervisor | string | Yes | Supervisor 名（例: `su-observer`） |
| target_controller | string | Yes | 対象 controller 名（例: `co-autopilot`） |
| layer | string | Yes | 介入レイヤー（例: `meta-cognitive`, `observation`） |
| status | `detected` \| `intervening` \| `resolved` | Yes | 介入状態 |
| detected_at | string (ISO 8601) | Yes | 検出時刻 |
| resolved_at | null \| string (ISO 8601) | Yes | 解決時刻（未解決時は null） |
| reason | string | Yes | 介入理由の説明 |

**アクセスルール**: Supervisor = write, Pilot = read only。介入ごとに独立ファイルを生成する（per-intervention ファイル）。

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

<!-- CHAIN-FLOW:all START -->
```mermaid
flowchart TD

    subgraph setup["setup chain"]
        setup__init["init"]:::script
        setup__project_board_status_update["project-board-status-update"]:::script
        setup__crg_auto_build["crg-auto-build"]:::llm
        setup__arch_ref["arch-ref"]:::script
        setup__ac_extract["ac-extract"]:::script
    end

    subgraph test_ready["test-ready chain"]
        test_ready__test_scaffold["test-scaffold"]:::llm
        test_ready__check["check"]:::script
    end

    subgraph pr_verify["pr-verify chain"]
        pr_verify__prompt_compliance["prompt-compliance"]:::script
        pr_verify__ts_preflight["ts-preflight"]:::script
        pr_verify__phase_review["phase-review"]:::llm
        pr_verify__scope_judge["scope-judge"]:::llm
        pr_verify__pr_test["pr-test"]:::script
        pr_verify__ac_verify["ac-verify"]:::llm
    end

    subgraph pr_fix["pr-fix chain"]
        pr_fix__fix_phase["fix-phase"]:::llm
        pr_fix__post_fix_verify["post-fix-verify"]:::llm
        pr_fix__warning_fix["warning-fix"]:::llm
    end

    subgraph pr_merge["pr-merge chain"]
        pr_merge__e2e_screening["e2e-screening"]:::llm
        pr_merge__pr_cycle_report["pr-cycle-report"]:::script
        pr_merge__pr_cycle_analysis["pr-cycle-analysis"]:::llm
        pr_merge__all_pass_check["all-pass-check"]:::script
        pr_merge__merge_gate["merge-gate"]:::llm
        pr_merge__auto_merge["auto-merge"]:::script
    end

    setup__init --> setup__project_board_status_update
    setup__project_board_status_update --> setup__crg_auto_build
    setup__crg_auto_build --> setup__arch_ref
    setup__arch_ref --> setup__ac_extract
    test_ready__test_scaffold --> test_ready__check
    pr_verify__prompt_compliance --> pr_verify__ts_preflight
    pr_verify__ts_preflight --> pr_verify__phase_review
    pr_verify__phase_review --> pr_verify__scope_judge
    pr_verify__scope_judge --> pr_verify__pr_test
    pr_verify__pr_test --> pr_verify__ac_verify
    pr_fix__fix_phase --> pr_fix__post_fix_verify
    pr_fix__post_fix_verify --> pr_fix__warning_fix
    pr_merge__e2e_screening --> pr_merge__pr_cycle_report
    pr_merge__pr_cycle_report --> pr_merge__pr_cycle_analysis
    pr_merge__pr_cycle_analysis --> pr_merge__all_pass_check
    pr_merge__all_pass_check --> pr_merge__merge_gate
    pr_merge__merge_gate --> pr_merge__auto_merge

    setup__ac_extract --> test_ready__test_scaffold
    test_ready__check --> pr_verify__prompt_compliance
    pr_verify__ac_verify --> pr_fix__fix_phase
    pr_fix__warning_fix --> pr_merge__e2e_screening

    classDef script fill:#2e7d32,stroke:#1b5e20,color:#ffffff
    classDef llm fill:#1565c0,stroke:#0d47a1,color:#ffffff
    classDef composite fill:#7b1fa2,stroke:#4a148c,color:#ffffff
    classDef marker fill:#616161,stroke:#424242,color:#ffffff
```
<!-- CHAIN-FLOW:all END -->

**Chain の役割**: deps.yaml の chains セクションがステップ順序を宣言的に定義する。Workflow は chain 定義を読み取り、各ステップに対応する atomic/composite コマンドを逐次実行する。順序変更は deps.yaml の編集のみで完結し、Workflow のコード変更は不要。

### Project Board 統合

```mermaid
flowchart LR
    subgraph "GitHub Projects V2"
        PB["twill-ecosystem (project-links.yaml参照)"]
        PB -->|"linked"| R1["shuu5/twill"]
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
