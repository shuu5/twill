## Context

`autopilot-orchestrator.sh` は `check_and_nudge()` 内で `tmux capture-pane -p -S -5` によって Worker pane の末尾 5 行を取得し `_nudge_command_for_pattern()` に渡す。このパターンは chain 進捗キーワードのみを定義しており、input-waiting（自由テキスト質問・選択 UI）は未定義。また Pilot LLM セッション (`co-autopilot/SKILL.md`) は state file の `status`/`updated_at` と orchestrator log の `PHASE_COMPLETE` しか参照しないため、Worker が入力待ちになっても `AUTOPILOT_STAGNATE_SEC`（デフォルト 600 秒）が経過するまで表面化しない。

Wave 7 観測事例（2026-04-11 23:19 JST）: Issue #470 Worker が自由テキスト質問で停止、3 分以上 Pilot が誤認識し su-observer の外部介入まで停滞した。

## Goals / Non-Goals

**Goals:**

- `autopilot-orchestrator.sh` に `detect_input_waiting()` 関数を追加し、Menu UI + Free-form text の入力待ちパターンを検知する
- `check_and_nudge()` の capture-pane 行数を `-S -5` → `-S -30` に変更し、detection と nudge の両方が同一 pane_output を参照する
- デバウンス機構（同一 issue + 同一 pattern を 2 poll cycle 連続検知で確定）を実装し、誤検知を抑制する
- 検知イベントを trace log に追記する
- `state.py` に `input_waiting_detected` / `input_waiting_at` フィールドを追加し `role=pilot` での書き込みを許可する
- `co-autopilot/SKILL.md` Step 4 に Input-waiting 確認手順（2.5）と Silence heartbeat 節を追加する
- bats テストで detection パターン全種 + デバウンス + false positive を検証する

**Non-Goals:**

- `_nudge_command_for_pattern()` のパターンロジック変更
- `inject_next_workflow()` の変更
- `worker-terminal-guard.sh` の変更
- `deps.yaml` の変更（detect_input_waiting は既存関数への追加のみ）
- state.py の `_validate_role` / `_check_pilot_identity` の改修
- state schema migration スクリプトの作成
- #486 su-observer の `monitor-channel-catalog.md` へのパターン同期（責務分離、別 Issue で検討）

## Decisions

**D1: orchestrator.sh が detection の SSOT**  
`detect_input_waiting()` をシェル関数として `autopilot-orchestrator.sh` 内に実装。同プロセスが既に `capture-pane` を実行しているため最小侵襲。su-observer (#486) は cross-session watchdog として並置するが、pattern の重複は責務レイヤが異なるため許容する。

**D2: デバウンスに `declare -A INPUT_WAITING_SEEN_PATTERN`**  
bash の連想配列をスクリプトスコープで宣言し、`key="<issue>:<pattern>"` で 1 回目 warn / 2 回目 state write を制御。異なる issue または pattern の場合はリセット不要（独立 key）。

**D3: 検知しても nudge/inject は抑止しない**  
`detect_input_waiting` は状態検知と記録のみ行い、既存 nudge 経路（`_nudge_command_for_pattern` → chain-stop 判定 → inject）は現行通り継続する。これにより chain-stop と input-waiting が同時成立しても干渉しない。

**D4: `role=pilot` で state write**  
orchestrator は main worktree から起動され `_check_pilot_identity` が通過できる。`role=orchestrator` は新設せず、既存 `role=pilot` に `input_waiting_detected` / `input_waiting_at` を allowed_keys として追加するのみ。

**D5: Pilot Silence heartbeat を SKILL.md に記述**  
orchestrator が停止している可能性への補完として、Pilot LLM 自身が「全 worker の `updated_at` が 5 分以上無変化」を検知したとき tmux pane を手動確認し input-waiting を検査する手順を追加する。

## Risks / Trade-offs

- **bash 連想配列の永続性**: `INPUT_WAITING_SEEN_PATTERN` はプロセス内のみ有効。orchestrator 再起動時にカウンタがリセットされ、1 回目検知から再カウントされる（許容範囲内）。
- **pane_output の拡張コスト**: `-S -5` → `-S -30` は取得データ量の増加だが、shell 内処理でありパフォーマンス影響は無視できる。
- **Pattern SSOT の将来負債**: #486 と pattern が重複しているため将来的に乖離するリスクがある。別 Issue で `plugins/twl/refs/input-waiting-patterns.md` への統合を検討。
