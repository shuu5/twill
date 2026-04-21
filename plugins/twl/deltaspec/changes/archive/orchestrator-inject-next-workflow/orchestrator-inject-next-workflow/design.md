## Context

`plugins/twl/scripts/autopilot-orchestrator.sh` の polling ループ（シングルモード `poll_issue`・並列モード `poll_phase`）は、現状 `status=running` ブランチ内でクラッシュ検知と `check_and_nudge()` のみを実行する。ADR-021 では Worker が workflow 完了時に `workflow_done` フィールドを state に書き込み、Orchestrator がこれを検知して次の workflow skill を tmux inject する設計を定義している。

依存関係:
- #335: `workflow_done` フィールドの IssueState 定義と `_PILOT_ISSUE_ALLOWED_KEYS` への追加（必須）
- #337: `resolve_next_workflow` CLI の実装（必須）

## Goals / Non-Goals

**Goals:**

- `status=running` ブランチ内で `workflow_done` を追加読み取りする
- `inject_next_workflow()` 関数を実装する
- `check_and_nudge()` との共存ルール（inject 優先）を実装する
- inject 安全機構（pane 入力待ち確認、3回リトライ）を実装する
- inject 履歴（`workflow_injected`, `injected_at`）を state に記録する
- terminal workflow (`pr-merge`) の場合は inject せず既存フローに委譲する
- inject 失敗時の WARNING ログ + 10秒後再チェックを実装する
- inject 成功時に `NUDGE_COUNTS` をリセットする

**Non-Goals:**

- `workflow_done` フィールドの IssueState 定義（#335 の責務）
- `resolve_next_workflow` CLI の実装（#337 の責務）
- `check_and_nudge()` の境界 nudge 削除（#345 の責務）
- `poll_phase` における inject ロジック（シングルモードのみが対象。並列モードは別途検討）

## Decisions

### workflow_done 検出位置

`status=running` の case ブランチ内、クラッシュ検知の後、`check_and_nudge()` の前に追加読み取りを配置する。`workflow_done` が非空の場合は `inject_next_workflow()` を呼び、成功時は `check_and_nudge()` をスキップする。

**理由**: case 文に新しい case を追加すると状態遷移が複雑になる。`running` ブランチ内で追加条件として処理することで既存構造を保持できる。

### tmux pane 確認ロジック

`tmux capture-pane -p -t "$window_name"` の出力末尾を確認し、`> ` または `$ ` プロンプトが存在すれば inject 実行。最大3回、2秒間隔でリトライする。

**理由**: Claude が応答中に inject すると入力が混在するリスクがある。pane 確認でこれを防ぐ。

### terminal workflow の扱い

`resolve_next_workflow` が `pr-merge` を返した場合、inject せず `workflow_done` のクリアのみ行い、Worker が `status=merge-ready` を書き込む自然な遷移に委譲する。Orchestrator は次のポーリングで `merge-ready` を検出して処理する。

**理由**: `pr-merge` は merge-gate フロー（既存実装）があり、inject では扱いきれない複雑な条件判定が含まれる。

### NUDGE_COUNTS リセット

inject 成功後に `NUDGE_COUNTS[$issue]=0` でリセットする。inject により新しい workflow が開始されたため、stall カウンターをゼロクリアすることが適切。

## Risks / Trade-offs

- **`poll_phase` に inject を追加しない**: シングルモード限定実装のため、並列モードでは `workflow_done` が無視される。ADR-021 実験フェーズ（Pilot = 1 Worker）では問題ないが、将来の並列拡張時に対応が必要。
- **inject タイミングの競合**: Worker がまだ実行中なのに `workflow_done` が書き込まれた場合（バグ）、inject が早すぎる可能性がある。pane 確認でリスクを低減するが完全には防げない。
- **`resolve_next_workflow` CLI 依存**: #337 が未マージの場合、inject ロジックが動作しない。依存関係の順序制御が必要。
