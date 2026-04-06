# OpenSpec アーカイブ（change-archive）

完了済み change を archive/ に移動し、delta specs を main specs に統合する。

## 引数

- `change-id`: OpenSpec change ID（省略時は自動検出）

## フロー制御（MUST）

### Step 1: change-id 解決

If no change name provided, prompt for selection.
Run `twl spec list` to get available changes. Use the **AskUserQuestion tool** to let the user select.
Show only active changes (not already archived).

**IMPORTANT**: Do NOT guess or auto-select a change. Always let the user choose.

### Step 2: artifact 完了確認

Run `twl spec status --change "<name>" --json` to check artifact completion.

Parse the JSON to understand:
- `schemaName`: The workflow being used
- `artifacts`: List of artifacts with their status (`done` or other)

**If any artifacts are not `done`:**
- Display warning listing incomplete artifacts
- Use **AskUserQuestion tool** to confirm user wants to proceed
- Proceed if user confirms

### Step 3: タスク完了確認

Read the tasks file (typically `tasks.md`) to check for incomplete tasks.
Count tasks marked with `- [ ]` (incomplete) vs `- [x]` (complete).

**If incomplete tasks found:**
- Display warning showing count of incomplete tasks
- Use **AskUserQuestion tool** to confirm user wants to proceed
- Proceed if user confirms

**If no tasks file exists:** Proceed without task-related warning.

### Step 4: delta spec sync 判定

Check for delta specs at `openspec/changes/<name>/specs/`. If none exist, proceed without sync prompt.

**If delta specs exist:**
- Compare each delta spec with its corresponding main spec at `openspec/specs/<capability>/spec.md`
- Determine what changes would be applied (adds, modifications, removals, renames)
- Show a combined summary before prompting

**Prompt options:**
- If changes needed: "Sync now (recommended)", "Archive without syncing"
- If already synced: "Archive now", "Sync anyway", "Cancel"

If user chooses sync, apply delta specs to main specs manually (read delta, merge into main spec).

### Step 5: CLI でアーカイブ実行

```bash
twl spec archive "<change-id>" --yes --skip-specs
```

### Step 6: チェックポイント出力

```
>>> アーカイブ完了: <change-id>

次のステップ:
  /twl:worktree-delete で開発ブランチをクリーンアップ
```

## 禁止事項（MUST NOT）

- worktree-delete を自動実行してはならない（ユーザー確認が必要）
- Don't block archive on warnings - just inform and confirm
- Preserve .openspec.yaml when moving to archive (it moves with the directory)
