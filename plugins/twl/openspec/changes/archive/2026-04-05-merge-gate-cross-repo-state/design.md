## Context

`autopilot-orchestrator.sh` の `poll_phase`（L417/487/507）は `_state_read_repo_args` パターンを使ってクロスリポ対応済み。merge-gate ループと `run_merge_gate()` は同パターンが未適用。

## Goals / Non-Goals

**Goals:**
- `run_merge_gate()` を entry ベースに変更し、クロスリポ state 読み取りを可能にする
- merge-gate ループの state-read.sh 呼び出しに `_state_read_repo_args` を適用

**Non-Goals:**
- `merge-gate-execute.sh` の変更
- `generate_phase_report()` の変更（別途対応）

## Decisions

### 1. `run_merge_gate` シグネチャ: `issue` → `entry`

`entry` から `repo_id` と `issue_num` を分解する。`poll_phase` と同一パターン:
```bash
local entry="$1"
local repo_id="${entry%%:*}"
local issue="${entry#*:}"
local -a _state_read_repo_args=()
[[ "$repo_id" != "_default" ]] && _state_read_repo_args=(--repo "$repo_id")
```

### 2. merge-gate ループ側: `_batch_issue_to_entry` を活用

既存の `_batch_issue_to_entry[$issue]` マップから entry を取得し、`_state_read_repo_args` を構築する:
```bash
for issue in "${BATCH_ISSUES[@]}"; do
  local _entry="${_batch_issue_to_entry[$issue]:-_default:${issue}}"
  local _repo_id="${_entry%%:*}"
  local -a _repo_args=()
  [[ "$_repo_id" != "_default" ]] && _repo_args=(--repo "$_repo_id")
  status=$(bash "$SCRIPTS_ROOT/state-read.sh" --type issue "${_repo_args[@]}" --issue "$issue" --field status ...)
  ...
  run_merge_gate "$_entry"
```

### 3. 後方互換: `_default` repo_id

entry が `_default:123` の場合、`_state_read_repo_args` は空配列となり、既存の動作と同じになる。
