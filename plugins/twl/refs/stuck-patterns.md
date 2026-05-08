# Stuck Patterns — SSoT Reference

> **SSoT**: このドキュメントは `stuck-patterns.yaml` から人間可読形式で生成した参照資料。
> 正典は YAML ファイルであり、本 MD は補助的な説明を追加したもの。
> コード上の参照は必ず `stuck-patterns-lib.sh` 経由で行う。

## パターン一覧

### Recovery Patterns（操作待ち UI の自動復旧）

| id | regex | recovery_action | owner_layer | confidence |
|----|-------|-----------------|-------------|------------|
| `queued_message_residual` | `Press up to edit queued messages` | Enter送信（queued message をクリア） | orchestrator+observer | high |

> **Note**: `queued_message_residual` は Issue #1034 mailbox Phase 3 完遂後に deprecate 候補。

### Menu Patterns（インタラクティブ選択 UI）

| id | regex | recovery_action | owner_layer | confidence |
|----|-------|-----------------|-------------|------------|
| `menu_enter_select` | `Enter to select` | 番号 inject + Enter (auto_inject_menu) | observer | high |
| `menu_arrow_navigate` | `↑/↓ to navigate` | 番号 inject + Enter (auto_inject_menu) | observer | high |
| `menu_prompt_number` | `` `❯[[:space:]]*[0-9]+\.` `` | 番号 inject + Enter (auto_inject_menu) | observer | high |

### Freeform Patterns（自然言語の確認要求）

> **Note**: Freeform patterns は自動 recovery なし。`state write only` で observer 通知のみ行う。

| id | regex | recovery_action | owner_layer | confidence |
|----|-------|-----------------|-------------|------------|
| `freeform_kaishi` | `(開始\|始め)(て\|します)[^？?]*[？?]?` | state write only (manual) | orchestrator | medium |
| `freeform_yoroshii` | `よろしいですか[？?]` | state write only (manual) | orchestrator | medium |
| `freeform_tsuzukemasu` | `続けますか\|進んでよいですか\|実行しますか` | state write only (manual) | orchestrator | medium |
| `freeform_yn_bracket` | `\[[Yy]/[Nn]\]` | state write only (manual) | orchestrator | medium |

## Consumer 一覧

本 YAML を SSoT として参照するスクリプト（`stuck-patterns-lib.sh` 経由）:

| consumer | 参照方法 | 役割 |
|----------|----------|------|
| `autopilot-orchestrator.sh` | `source stuck-patterns-lib.sh` | メイン orchestrator の stuck 検知ループ |
| `observer-auto-inject.sh` | `source stuck-patterns-lib.sh` | observer サイドの menu auto-inject |
| `cld-observe-any` | `source stuck-patterns-lib.sh` | tmux pane 観察デーモン |
| `step0-monitor-bootstrap.sh` | `_load_stuck_patterns` 呼び出し | su-observer 起動時の pattern ロード |

## 関連

- YAML SSoT: [stuck-patterns.yaml](stuck-patterns.yaml)
- ライブラリ: [../scripts/lib/stuck-patterns-lib.sh](../scripts/lib/stuck-patterns-lib.sh)
- ADR: [../architecture/decisions/ADR-037-stuck-pattern-ssot.md](../architecture/decisions/ADR-037-stuck-pattern-ssot.md)
- Issue: #1582
