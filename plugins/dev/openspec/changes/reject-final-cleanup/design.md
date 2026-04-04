## Context

`autopilot-orchestrator.sh`のmerge-gateループ（lines 858-878）では、`merge-ready`状態のIssueに対してmerge-gateを実行した後、結果に応じてcleanup_workerを呼ぶ。

現状のcleanup呼び出し条件:
```bash
elif [[ "$_status_after" == "failed" ]]; then
  _retry=$(state-read --field retry_count)   # top-level retry_count
  if [[ "${_retry:-0}" -ge 1 ]]; then
    cleanup_worker ...
  fi
```

**バグ**: `--reject-final`は`failure.reason=merge_gate_rejected_final`と`failure.retry_count=2`を設定するが、top-levelの`retry_count`フィールドは変更しない。Issueが一度もリトライされていない場合（`retry_count=0`）、条件`0 >= 1`がFALSEとなりcleanup_workerが呼ばれない。

**意図された動作**:
- `--reject`（リトライ可）: `retry_count=0` → cleanup不要（次回リトライで使う）
- `--reject-final`（確定失敗）: `retry_count`の値に関わらず cleanup必須

## Goals / Non-Goals

**Goals:**
- `--reject-final`後、top-level `retry_count`が0でもcleanup_workerを呼ぶ
- `failure.reason == "merge_gate_rejected_final"` でreject-finalを識別
- 既存の `retry_count >= 1` パスは変更しない（正常系・リトライ後確定失敗に影響なし）

**Non-Goals:**
- `merge-gate-execute.sh`の修正（top-level `retry_count`を変更しない設計は維持）
- `state-read.sh`へのネストフィールド対応追加
- `poll_phase()`の`done|failed` → cleanup ロジック変更（これは正しく動いている）

## Decisions

### D1: failure.reasonをjqで直接読む

`state-read.sh`はwhitelistで単純フィールド名のみ許可（`failure.reason`のようなネストパスは非対応）。
追加オプション実装は影響範囲が広いため、orchestrator内でjqを直接使ってfailure objectを読む。

```bash
local _failure_reason=""
local _state_file="${AUTOPILOT_DIR}/issues/issue-${issue}.json"
if [[ -f "$_state_file" ]]; then
  _failure_reason=$(jq -r '.failure.reason // ""' "$_state_file" 2>/dev/null || echo "")
fi
if [[ "${_retry:-0}" -ge 1 ]] || [[ "$_failure_reason" == "merge_gate_rejected_final" ]]; then
  cleanup_worker "$issue" "$_issue_entry"
fi
```

### D2: 修正箇所はmerge-gateループのみ

`poll_phase()`はすでに`done|failed`で無条件cleanup_workerを呼ぶため問題なし。
修正対象はlines 869-875の`elif [[ "$_status_after" == "failed" ]]`ブロックのみ。

## Risks / Trade-offs

- **jq直接読み取り**: `AUTOPILOT_DIR`パスと`issue`番号はorchestrator内で既検証済みのため、インジェクションリスクなし
- **後方互換**: `failure.reason`フィールドが存在しない古いstateファイルは空文字列→条件FALSE→既存の`retry_count`判定に fallback。動作変化なし
