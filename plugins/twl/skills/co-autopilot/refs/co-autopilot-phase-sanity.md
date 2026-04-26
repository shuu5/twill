# Phase 完了サニティチェック手順（Step 4.5）

PHASE_COMPLETE 受信後、以下を順次実行する:

1. `commands/autopilot-phase-sanity.md` を Read → 実行
2. `commands/autopilot-pilot-precheck.md` を Read → 実行（`PILOT_ACTIVE_REVIEW_DISABLE=1` 時はスキップ）
3. precheck が WARN (high-deletion) 時 → `commands/autopilot-pilot-rebase.md` を Read → 実行
4. 再 verify 必要時 → `commands/autopilot-multi-source-verdict.md` を Read → 実行
5. `commands/autopilot-phase-postprocess.md` を Read → 実行

TaskUpdate Phase P → completed。`python3 -m twl.autopilot.audit snapshot ...` で状態保全（audit 非アクティブ時は no-op）。
