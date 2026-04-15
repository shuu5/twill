## Context

`issue-lifecycle-orchestrator.sh` の `wait_for_batch()` 関数内 inject ロジック（L380-L419）が対象。`session-state.sh` が processing 中の Worker を `input-waiting` と誤報告する false positive（#708）により、実際には不要な inject が連続実行され、inject 上限（3回）を使い切って `inject_exhausted` に陥る。

現在の問題点：
1. L380 で `input-waiting` 検出後、即座に inject フローへ進む（debounce なし）
2. inject 上限が 3 回と低い
3. inject 間に待機なし（progressive delay なし）
4. inject 実行直前の再確認なし
5. inject メッセージが詳細すぎる（chain-runner の自律判断を妨げるリスク）

## Goals / Non-Goals

**Goals:**
- transient false positive を debounce で排除し、inject が本当に必要な場合のみ実行する
- inject 上限を 5 回に緩和して、false positive 消費後も本来の inject を届けられるようにする
- inject 間に progressive delay を設けて Worker の処理時間を確保する
- inject 直前再確認で unnecessary inject をさらに抑制する
- inject メッセージを簡潔にして Worker の chain 自律判断を妨げない

**Non-Goals:**
- `session-state.sh` の false positive 自体の修正（#708 が担当）
- `autopilot-orchestrator.sh` の inject 修正（#707 が担当）
- inject ロジックの共通 lib 化（機構が異なるため見送り）

## Decisions

**1. debounce 実装**: `input-waiting` 検出直後に `sleep 5` を挿入し、`session-state.sh` を再度呼び出す。再確認が `input-waiting` でない場合は `all_done=false` で次ポーリングサイクルへ。再確認も `input-waiting` なら inject フロー継続。

**2. inject 上限 3 → 5**: `inject_count -lt 3` を `-lt 5` に変更。エラーメッセージ内の `3` も `5` に更新。

**3. progressive delay**: inject 実行後に `sleep $((5 * inject_count))` を追加（1回目: 5秒、2回目: 10秒、3回目: 15秒…）。

**4. inject 前再確認**: inject 実行直前（session-comm.sh 呼び出し前）に `session-state.sh` で状態を再取得し、`input-waiting` でなければ `continue`。

**5. inject メッセージ簡素化**: ワークフロー分岐（`existing-issue.json` 有無）を廃止し、単一メッセージ `"処理を続行してください。"` に統一。

## Risks / Trade-offs

- debounce の `sleep 5` はポーリング全体を遅延させるが、false positive 排除の効果の方が大きい
- inject 上限を 5 に増やすと genuine stagnation の検出が遅くなるが、false positive 対策として許容範囲内
- progressive delay により recovery 時間が伸びるが、Worker への過剰 inject 防止を優先
