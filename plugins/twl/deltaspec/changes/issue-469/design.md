## Context

autopilot-orchestrator.sh の `inject_next_workflow()` は `python3 -m twl.autopilot.resolve_next_workflow --issue <N>` を呼ぶが、このモジュールが存在しない。結果、`inject_next_workflow` は常に RESOLVE_FAILED で失敗する。次の fallback として `check_and_nudge()` のパターンマッチが働くが、`>>> 実装完了: issue-<N>`（change-apply.md Step 6 の出力）は登録されていないため、nudge も発火しない。

**二重の欠陥:**
1. `cli/twl/src/twl/autopilot/resolve_next_workflow.py` が存在しない（`inject_next_workflow` 常時失敗）
2. `_nudge_command_for_pattern()` に `>>> 実装完了` パターンが登録されていない（nudge fallback も無効）

また `AUTOPILOT_STAGNATE_SEC` 閾値は複数 Issue（#469、#472、#475）で三重実装されるリスクがある。

## Goals / Non-Goals

**Goals:**

- `resolve_next_workflow.py` を新規作成し、`inject_next_workflow` が正常動作するようにする
- `_nudge_command_for_pattern` に `>>> 実装完了: issue-<N>` パターンを追加し、orchestrator が直接 `workflow_done` を書いてから `inject_next_workflow` を呼ぶ fallback を実装する
- stagnate 閾値を `AUTOPILOT_STAGNATE_SEC` 環境変数に一元化する
- Worker が `workflow_done` を書かずに終了した場合の orchestrator recovery を E2E テストでカバーする

**Non-Goals:**

- `change-apply.md` の修正（Worker 側の指示書変更は別 Issue で扱う）
- `worker-terminal-guard.sh` の根本的な変更（現状の non_terminal_chain_end 検出は維持）
- Wave 観測 AC-5（実装後の運用確認）

## Decisions

### 1. `resolve_next_workflow.py` の作成

**場所**: `cli/twl/src/twl/autopilot/resolve_next_workflow.py`

**インターフェース**:
```
python3 -m twl.autopilot.resolve_next_workflow --issue <N>
```

**内部動作**:
1. state から `workflow_done`、`is_autopilot`（mode=propose/apply/... で判定）、`is_quick` を読む
2. `chain.ChainRunner.resolve_next_workflow(workflow_done, is_autopilot=True, is_quick)` を呼ぶ
3. 次 skill 名（例: `/twl:workflow-test-ready`）を stdout に出力
4. 失敗（workflow_done=null / resolve 失敗）は exit 非ゼロ

**理由**: orchestrator は既存の呼び出し形式を変えないまま fix できる。`chain.py` の resolve ロジックを再利用する。

### 2. `_nudge_command_for_pattern` に fallback パターン追加

**場所**: `plugins/twl/scripts/autopilot-orchestrator.sh`（`_nudge_command_for_pattern` 関数、行 695–741）

**追加パターン**:
```bash
elif echo "$pane_output" | grep -qP ">>> 実装完了: issue-\d+"; then
  # Pilot role で workflow_done=test-ready を書き、inject を促す
  python3 -m twl.autopilot.state write --type issue --issue "$issue" \
    --role pilot --set "workflow_done=test-ready" 2>/dev/null || true
  echo "/twl:workflow-pr-verify #${issue}"
```

**理由**: `check_and_nudge` は pane が静止した（hash が同じ）場合にパターンを評価する。state write を nudge 関数内で行うことで、次のポーリングサイクルで `inject_next_workflow` が `workflow_done` を見つけて正常動作する。Pilot role は `_PILOT_ISSUE_ALLOWED_KEYS` に `workflow_done` を含む（state.py:34 確認済み）。

### 3. stagnate 閾値の env var 一元化

`AUTOPILOT_STAGNATE_SEC`（デフォルト 600）を `autopilot-orchestrator.sh` 上部で宣言し、`inject_next_workflow` の RESOLVE_FAILED 連続カウントに使用する。連続 3 回（`AUTOPILOT_STAGNATE_SEC / POLL_INTERVAL` 以上）で WARN + Supervisor 通知。

### 4. E2E テスト

**場所**: `cli/twl/tests/autopilot/test_nonterminal_chain_recovery.py`

シナリオ:
- `workflow_done=null` 状態で `inject_next_workflow` を呼んだとき RESOLVE_FAILED になることを確認
- `workflow_done=test-ready` を書いた後、`resolve_next_workflow.py` が `/twl:workflow-test-ready` を返すことを確認
- `_nudge_command_for_pattern` が `>>> 実装完了: issue-469` を受け取ったとき state write + コマンド返却することを確認

## Risks / Trade-offs

- **Pilot role による state write**: orchestrator が worker の代わりに `workflow_done` を書く。RBAC 上は許可されているが、Worker が後続で自身の `workflow_done` を書くと二重書き込みになる。影響: `inject_next_workflow` が 2 回発火するが、2 回目は `workflow_done` が null になっているため no-op になる。
- **pattern マッチの誤検知**: `>>> 実装完了: issue-<N>` が変更されると nudge が無効になる。change-apply.md のフォーマット変更時は本ファイルも更新が必要。
- **`resolve_next_workflow.py` と `chain.py` の重複**: resolve ロジックは `chain.py` にあるため、新規モジュールは薄いラッパーとして実装し、ロジックの重複を避ける。
