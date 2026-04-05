## 1. run_merge_gate シグネチャ変更と内部修正

- [x] 1.1 `run_merge_gate()` の引数を `issue` から `entry` に変更し、`repo_id` と `issue_num` を分解する
- [x] 1.2 `_state_read_repo_args` を構築するコードを追加（`_default` 以外の場合のみ `--repo` 付与）
- [x] 1.3 関数内の全 `state-read.sh` 呼び出しに `"${_state_read_repo_args[@]}"` を追加

## 2. merge-gate ループの修正

- [x] 2.1 ループ先頭で `_entry` を `_batch_issue_to_entry[$issue]` から取得し `_repo_args` を構築する
- [x] 2.2 L866 の `state-read.sh`（status 読み取り）に `"${_repo_args[@]}"` を追加
- [x] 2.3 L871 の `state-read.sh`（_status_after 読み取り）に `"${_repo_args[@]}"` を追加
- [x] 2.4 L879 の `state-read.sh`（retry_count 読み取り）に `"${_repo_args[@]}"` を追加
- [x] 2.5 L882 の `state-read.sh`（failure.reason 読み取り）に `"${_repo_args[@]}"` を追加
- [x] 2.6 `run_merge_gate "$issue"` を `run_merge_gate "$_entry"` に変更

## 3. 検証

- [x] 3.1 `loom check` を実行してエラーがないことを確認
