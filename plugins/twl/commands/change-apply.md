---
type: atomic
tools: [AskUserQuestion, Bash, Read, Skill, Task]
effort: low
maxTurns: 10
---
# DeltaSpec 実装（change-apply）

DeltaSpec change の tasks.md に沿ってタスクを実装する。完了後に PR サイクルへの誘導を出力する。

## 引数

- `change-id`: DeltaSpec change ID（省略時は自動検出）

## フロー制御（MUST）

### Step 1: change-id 解決

If a name is provided, use it. Otherwise:
- Infer from conversation context if the user mentioned a change
- Auto-select if only one active change exists
- If ambiguous, run `twl spec list` to get available changes and use the **AskUserQuestion tool** to let the user select

Always announce: "Using change: <name>".

### Step 2: ステータス確認
```bash
twl spec status --change "<name>" --json
```
Parse the JSON to understand:
- `schemaName`: The workflow being used (e.g., "spec-driven")
- Which artifact contains the tasks (typically "tasks" for spec-driven)

### Step 3: apply 指示取得

```bash
twl spec instructions apply --change "<name>" --json
```

This returns:
- Context file paths (varies by schema)
- Progress (total, complete, remaining)
- Task list with status
- Dynamic instruction based on current state

**Handle states:**
- If `state: "blocked"` (missing artifacts): show message, suggest creating artifacts first
- If `state: "all_done"`: congratulate, suggest archive
- Otherwise: proceed to implementation

### Step 4: コンテキストファイル読み込み

Read the files listed in `contextFiles` from the apply instructions output.
The files depend on the schema being used:
- **spec-driven**: proposal, specs, design, tasks
- Other schemas: follow the contextFiles from CLI output

### Step 5: タスク実装（完了またはブロックまでループ）

For each pending task:
- Show which task is being worked on
- Make the code changes required
- Keep changes minimal and focused
- Mark task complete in the tasks file: `- [ ]` → `- [x]`
- Continue to next task

**Pause if:**
- Task is unclear → ask for clarification
- Implementation reveals a design issue → suggest updating artifacts
- Error or blocker encountered → report and wait for guidance
- User interrupts

### Step 6: チェックポイント出力（MUST）

全タスク完了後、以下を表示して停止:

```
>>> 実装完了: <change-id>

次のステップ:
  /twl:workflow-pr-verify --spec <change-id> で PR サイクル開始
```

On completion or pause, show status:
- Tasks completed this session
- Overall progress: "N/M tasks complete"
- If all done: suggest archive
- If paused: explain why and wait for guidance

## 禁止事項（MUST NOT）

- tasks.md にないタスクを勝手に追加してはならない
- Keep code changes minimal and scoped to each task
- Update task checkbox immediately after completing each task
- Pause on errors, blockers, or unclear requirements - don't guess
- Use contextFiles from CLI output, don't assume specific file names

## Fluid Workflow Integration

This command supports the "actions on a change" model:

- **Can be invoked anytime**: Before all artifacts are done (if tasks exist), after partial implementation, interleaved with other actions
- **Allows artifact updates**: If implementation reveals design issues, suggest updating artifacts - not phase-locked, work fluidly
