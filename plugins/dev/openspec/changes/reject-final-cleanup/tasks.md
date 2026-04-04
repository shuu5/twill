## 1. orchestratorのmerge-gateループ修正

- [x] 1.1 `scripts/autopilot-orchestrator.sh`のlines 869-875（`elif [[ "$_status_after" == "failed" ]]`ブロック）を修正: `failure.reason`を読み取り`merge_gate_rejected_final`の場合もcleanup_workerを呼ぶ

## 2. テスト・検証

- [x] 2.1 修正後のロジックをdry-runで確認（`status=failed`・`retry_count=0`・`failure.reason=merge_gate_rejected_final`のstateファイルを作成してorchestrator動作確認）
- [x] 2.2 既存動作の回帰確認: `retry_count=0`・`failure.reason=merge_gate_rejected`（通常reject）の場合にcleanup_workerが呼ばれないことを確認
