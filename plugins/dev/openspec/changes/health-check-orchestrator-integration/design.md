## Context

`autopilot-orchestrator.sh` は `poll_single()` と `poll_phase()` の `running` 分岐で Worker の状態を監視する。現在は crash-detect（exit 2）と check_and_nudge（5パターンのテキストマッチ）の2層で異常を検知するが、パターン外の stall は検知不能。

`health-check.sh` は3種類の時間ベース検知（chain_stall: updated_at 10分超過、error_output、input_waiting: 5分超過）を実装済みで、exit 1 + stdout（検知あり）/ exit 0（正常）/ exit 1 + stderr（引数エラー）の3パターンで結果を返す。

前提: #184（state-write.sh に updated_at 追加）完了済み。

## Goals / Non-Goals

**Goals:**
- `poll_single()` に health-check 呼び出しを追加（60秒間隔 = POLL_INTERVAL 10s × HEALTH_CHECK_INTERVAL 6）
- `poll_phase()` に同様の health-check 統合を追加
- health-check 検知時: `NUDGE_COUNTS` 共有で汎用 Enter nudge を送信（MAX_NUDGE 以内）
- nudge 上限到達時: `status=failed` 遷移（failure: `health_check_stall`）
- health-check.sh の引数エラー（stderr あり）時はスキップ
- crash-detect（exit 2）検知後は health-check をスキップ
- openspec 仕様（health-check.md L55）の MUST NOT → MAY への更新
- bats テストに統合テストを追加

**Non-Goals:**
- `health-check.sh` 自体の修正
- `state-write.sh` の変更（#184 前提済み）
- `check_and_nudge()` のパターン追加
- `_nudge_command_for_pattern()` の修正

## Decisions

### D1: health-check の配置順序（crash-detect の後、check_and_nudge の後）

`poll_single()` の `running` 分岐:
1. crash-detect（exit 2 → return, health-check スキップ）
2. check_and_nudge（パターンマッチ nudge を優先実行）
3. health-check（パターン外 stall を補完検知）

理由: crash-detect は最優先（プロセス消滅は別処理が必要）。check_and_nudge の既存パターンを優先し、パターン不一致の補完として health-check を使う。

### D2: HEALTH_CHECK_COUNTER を NUDGE_COUNTS と同スコープで宣言

```bash
declare -A NUDGE_COUNTS=()
declare -A LAST_OUTPUT_HASH=()
declare -A HEALTH_CHECK_COUNTER=()  # 追加
```

理由: グローバルスコープに統一することで、poll_single と poll_phase 両方から参照可能。

### D3: NUDGE_COUNTS を check_and_nudge と共有

health-check 検知時も `NUDGE_COUNTS[$issue]` をインクリメントし、MAX_NUDGE に達したら `status=failed` へ遷移。

理由: nudge の総数で上限管理することで、check_and_nudge + health-check の二重 nudge を防止。

### D4: crash-detect 検知後は health-check をスキップ

crash_exit=2 の場合は `continue` / `return` で health-check ブロックに到達させない。

理由: クラッシュとして処理中のセッションに対して health-check で追加の nudge を送信するのは無意味。

### D5: health-check の stderr 判定

```bash
health_stderr=$(bash "$SCRIPTS_ROOT/health-check.sh" --issue "$issue" --window "$window_name" 2>&1 1>/dev/null)
health_exit=$?
# stderr なし && exit 1 → 検知
if [[ "$health_exit" -eq 1 && -z "$health_stderr" ]]; then
```

理由: Issue body の技術的アプローチに準拠。引数エラーは stdout 捕捉で除外。

## Risks / Trade-offs

- **poll_phase での HEALTH_CHECK_COUNTER**: poll_phase は複数 issue を並列処理するため、各 issue のカウンタを正しく管理する必要がある。連想配列で issue キーを使用することで対応。
- **check_and_nudge と health-check の二重 nudge**: NUDGE_COUNTS 共有で防止するが、check_and_nudge がパターンマッチして nudge を送信した同じポーリングで health-check も検知する可能性がある。check_and_nudge を先に実行し、health-check は check_and_nudge がパターン不一致（exit 1）の場合のみ実行するよう順序で制御。
- **health-check.sh の実行コスト**: 60秒間隔なので性能影響は軽微。
