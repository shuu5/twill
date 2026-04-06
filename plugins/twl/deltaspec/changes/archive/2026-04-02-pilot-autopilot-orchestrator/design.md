## Context

現在 co-autopilot の Step 4（Phase ループ）は Pilot LLM が autopilot-phase-execute.md / autopilot-poll.md / autopilot-summary.md を Read → 解釈 → 実行している。これらは全て決定的ロジック（batch 分割、sleep ループ、state-read/write、tmux 操作）であり、LLM が介入する必要がない。

既存スクリプト群:
- `autopilot-launch.sh`: Worker 起動（tmux new-window + cld）
- `crash-detect.sh`: Worker crash 検知（session-state.sh 統合 + tmux フォールバック）
- `merge-gate-execute.sh`: squash merge + worktree/branch cleanup + state 遷移
- `state-read.sh` / `state-write.sh`: issue state の読み書き
- `autopilot-should-skip.sh`: 依存先 fail 時の skip 判定
- `auto-merge.sh`（#122）: merge-gate の判定ロジック

## Goals / Non-Goals

**Goals:**

- Phase ループ・ポーリング・merge-gate・window 管理・サマリー集計を単一スクリプトで完結させる
- crash-detect と window kill の順序競合を解消する（原子的実行）
- chain 遷移停止を検知して自動 nudge する
- Pilot LLM の責務を「計画承認」「retrospective」「cross-issue 影響分析」に限定する
- PHASE_COMPLETE シグナルで Pilot に制御を返し、LLM 判断が必要な処理を実行させる

**Non-Goals:**

- Worker 側 chain-runner のスクリプト化（#119 の責務）
- retrospective / patterns / cross-issue analysis のスクリプト化（LLM 判断が必要）
- auto-merge スクリプトの修正（#122 で完了済み）
- ポーリング間隔やタイムアウトの動的調整

## Decisions

### D1: orchestrator は Phase 単位で実行し、PHASE_COMPLETE で Pilot に制御を返す

orchestrator が全 Phase を一括実行すると、Pilot が retrospective/cross-issue を挟めない。Phase 単位で実行し、stdout に `PHASE_COMPLETE:<phase_num>` を出力して終了。Pilot が LLM 判断を実行した後、次 Phase で再度 orchestrator を呼ぶ。

### D2: 既存コマンド（autopilot-phase-execute.md / autopilot-poll.md）のロジックをスクリプトに移植

現在の .md ファイルに記述された疑似コードを bash に変換する。.md ファイル自体は削除せず、orchestrator への委譲を案内する形に更新する（後方互換性）。

### D3: chain 遷移停止検知は tmux capture-pane + パターンマッチ

Worker の tmux pane 出力から「chain 完了パターン」を検出する。具体的には Worker が出力する `setup chain 完了` や `>>> 提案完了` のようなメッセージを検知し、一定時間経過しても次の入力がなければ tmux send-keys で nudge する。

### D4: crash-detect → window kill を原子的に実行

現在 Pilot LLM が crash-detect と window kill を別々に実行しているため順序競合が起きる。orchestrator 内で crash-detect 結果を確認後、即座に window kill を行う単一関数にまとめる。

### D5: サマリー集計は jq ベースで state ファイルを集約

全 issue-{N}.json を jq でパースし、done/failed/skipped の集計とタイムスタンプ集約を行う。フォーマットは既存 autopilot-summary.md の出力形式を踏襲。

## Risks / Trade-offs

- **chain 遷移停止検知の精度**: tmux capture-pane のパターンマッチは Worker の出力フォーマットに依存する。Worker 側の出力が変わると検知漏れが起きる可能性がある。パターンは設定可能にする
- **PHASE_COMPLETE シグナル方式**: stdout ベースのため、Pilot LLM が出力を正しくパースする必要がある。構造化出力（JSON）で返すことで誤認リスクを低減
- **後方互換性**: co-autopilot SKILL.md を orchestrator 呼び出しに変更するため、Emergency Bypass 時の手動パスは .md ファイルを直接参照する形で残す
