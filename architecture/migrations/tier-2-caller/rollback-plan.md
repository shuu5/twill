# Tier-2 Caller Rollback Plan (Issue #1032)

## 緊急 Rollback 手順

### Phase 1 Rollback（session_msg → tmux backend に戻す）

```bash
# 即時 rollback: tmux backend を強制使用
export TWILL_MSG_BACKEND=tmux
```

環境変数 `TWILL_MSG_BACKEND` のデフォルトは `tmux`（Phase 1 時点）。
設定を明示しなければ自動的に tmux backend が使用される。

### Phase 2 Rollback（mcp_with_fallback → tmux）

```bash
# shadow モードを無効化して tmux のみに戻す
unset TWILL_MSG_BACKEND
# または
export TWILL_MSG_BACKEND=tmux
```

### Phase 3 Rollback（mcp default → tmux emergency fallback）

```bash
# autopilot/orchestrator 設定で override
export TWILL_MSG_BACKEND=tmux
```

`session-comm-backend-tmux.sh` は Phase 3 以降も whitelist として保持されるため、
tmux backend への rollback は常に可能（ADR-029 Decision 5 の安全保証）。

## Mismatch 検出時の対応

```bash
# shadow log 確認
bash plugins/twl/scripts/mcp-shadow-compare.sh --log-file .autopilot/mailbox/shadow-$(date +%Y%m%d).jsonl

# mismatch 多発時: shadow モード停止
export TWILL_MSG_BACKEND=tmux
```

## 影響範囲

- `session_msg send` API は `TWILL_MSG_BACKEND` env var で backend を切替
- env var を設定しなければデフォルト（Phase 1: `tmux`）に戻る
- caller スクリプト自体の変更は不要（env var override のみで rollback 完了）
