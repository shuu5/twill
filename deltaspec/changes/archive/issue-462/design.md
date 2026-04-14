## Context

`mergegate.py` は 954 行（CRITICAL 閾値 500 行超過）。モジュールレベルの guard 関数群（`_check_worktree_guard`, `_check_worker_window_guard`, `_check_running_guard`, `_check_phase_review_guard`）は `self` 依存がなく、独立モジュールへの抽出に最適。一方、`MergeGate` クラスの内部 checks（`_check_base_drift`, `_check_deps_yaml_conflict_and_rebase`）はインスタンス属性に強依存するため、Phase A だけで閾値を下回れない場合にのみ Phase B を検討する。

## Goals / Non-Goals

**Goals:**
- `mergegate.py` を 500 行以下に削減する
- `self` 非依存の guard 関数 4 つを `mergegate_guards.py` に抽出する（Phase A）
- テストファイルのインポートパスを更新する
- `deps.yaml` に `autopilot-mergegate-guards` エントリを追加する
- 公開 API (`MergeGate.execute`, `reject`, `reject_final`, `from_env`) のシグネチャ・動作を不変に保つ

**Non-Goals:**
- `MergeGate` クラスの論理的責務の再設計
- 公開 API の追加・削除
- Phase B（`_check_base_drift` 等の mixin 化）は Phase A 後の行数が 500 超の場合のみ

## Decisions

1. **抽出対象**: `_check_worktree_guard`（行 98-104）, `_check_worker_window_guard`（行 107-118）, `_check_running_guard`（行 121-127）, `_check_phase_review_guard`（行 130-197）の 4 関数。これらは `self` 非依存で副作用が明確。
2. **インポート方針**: `mergegate.py` から `mergegate_guards` を `from twl.autopilot.mergegate_guards import (...)` でインポートする。再エクスポートは行わない。
3. **Phase B 判定**: Phase A 実装後に `wc -l mergegate.py` で行数確認。500 以下なら Phase B 不要。超過した場合のみ Phase B を検討する。
4. **deps.yaml 更新**: 既存エントリ `autopilot-mergegate`（約 2309 行付近）の後に `autopilot-mergegate-guards` を追加。`consumed_by: [autopilot-mergegate]` を設定。

## Risks / Trade-offs

- **循環インポートリスク**: `mergegate_guards.py` が `mergegate.py` を import しない限り、循環依存は発生しない。guard 関数群は `sys`, `subprocess`, `json`, `re`, `pathlib` のみを使用するため安全。
- **後方互換性**: `mergegate.py` からの直接インポートパス（`from twl.autopilot.mergegate import _check_phase_review_guard`）に依存するコードが `test_merge_gate_phase_review.py` 以外にないことを確認してから進める。
- **Phase A 後の行数予測**: guard 4 関数 + `_PHASE_REVIEW_SKIP_LABELS` 定数で約 100 行の削減が見込まれる。残り行数は約 854 行（Phase B が必要な可能性が高い）。
