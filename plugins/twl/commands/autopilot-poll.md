# Issue 状態ポーリング

state-read.sh を使用して Issue 状態をポーリングし、crash-detect.sh でクラッシュ検知を行う。
autopilot-phase-execute から呼び出される。

session-state.sh が利用可能な場合は wait サブコマンドを活用してポーリング効率を改善する。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$ISSUE` | 対象 Issue 番号（single モード） |
| `$ISSUES` | Phase 内の全 Issue 番号リスト（phase モード、スペース区切り） |
| `$POLL_MODE` | `single` or `phase` |
| `$SESSION_STATE_FILE` | session.json のパス |

## session-state.sh 検出

```bash
SESSION_STATE_CMD="${SESSION_STATE_CMD-$HOME/ubuntu-note-system/scripts/session-state.sh}"
# パス安全性検証: 相対パス・空文字列・.. を含むパスを拒否
if [[ -n "$SESSION_STATE_CMD" && "$SESSION_STATE_CMD" == /* && "$SESSION_STATE_CMD" != *..* && -x "$SESSION_STATE_CMD" ]]; then
  USE_SESSION_STATE=true
else
  USE_SESSION_STATE=false
fi
```

## 実行ロジック（MUST）

### poll_single（単一 Issue ポーリング）

```bash
MAX_POLL=360  # session-state: 360回 × 10秒wait = 60分 / fallback: 360回 × 10秒sleep = 60分
POLL_COUNT=0
WINDOW_NAME="ap-#${ISSUE}"

while true; do
  # session-state.sh 利用時: wait で効率的にポーリング
  # フォールバック時: 従来の sleep 10
  if [ "$USE_SESSION_STATE" = "true" ]; then
    "$SESSION_STATE_CMD" wait "$WINDOW_NAME" exited --timeout 10 2>/dev/null || true
  else
    sleep 10
  fi
  POLL_COUNT=$((POLL_COUNT + 1))

  STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)

  case "$STATUS" in
    done)
      echo "Issue #${ISSUE}: 完了"
      break ;;
    failed)
      echo "Issue #${ISSUE}: 失敗"
      break ;;
    merge-ready)
      echo "Issue #${ISSUE}: merge-ready"
      break ;;
    running)
      # クラッシュ検知（crash-detect.sh が session-state.sh 統合済み）
      bash $SCRIPTS_ROOT/crash-detect.sh --issue "$ISSUE" --window "$WINDOW_NAME"
      CRASH_EXIT=$?
      if [ "$CRASH_EXIT" -eq 2 ]; then
        echo "Issue #${ISSUE}: ワーカークラッシュ検知"
        break
      fi
      ;;
  esac

  if [ "$POLL_COUNT" -ge "$MAX_POLL" ]; then
    echo "Issue #${ISSUE}: タイムアウト（${MAX_POLL}回×10秒）"
    python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
      --set "status=failed" \
      --set "failure={\"message\": \"poll_timeout\", \"step\": \"polling\"}"
    break
  fi
done
```

### poll_phase（Phase 全体ポーリング）

```bash
MAX_POLL=360
POLL_COUNT=0

while true; do
  ALL_RESOLVED=true

  for ISSUE in $ISSUES; do
    STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)

    case "$STATUS" in
      done|failed)
        continue ;;
      merge-ready)
        echo "Issue #${ISSUE}: merge-ready"
        continue ;;
      running)
        ALL_RESOLVED=false
        WINDOW_NAME="ap-#${ISSUE}"
        bash $SCRIPTS_ROOT/crash-detect.sh --issue "$ISSUE" --window "$WINDOW_NAME"
        if [ $? -eq 2 ]; then
          echo "Issue #${ISSUE}: ワーカークラッシュ検知"
        fi
        ;;
      *)
        ALL_RESOLVED=false ;;
    esac
  done

  $ALL_RESOLVED && break

  POLL_COUNT=$((POLL_COUNT + 1))
  if [ "$POLL_COUNT" -ge "$MAX_POLL" ]; then
    echo "Phase: タイムアウト — 未完了 Issue を failed に変換"
    for ISSUE in $ISSUES; do
      STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
      if [ "$STATUS" = "running" ]; then
        python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
          --set "status=failed" \
          --set "failure={\"message\": \"poll_timeout\", \"step\": \"polling\"}"
      fi
    done
    break
  fi

  # session-state.sh 利用時: wait で効率的にポーリング
  # フォールバック時: 従来の sleep 10
  if [ "$USE_SESSION_STATE" = "true" ]; then
    # Phase モードでは最初の running issue の window で wait
    FIRST_RUNNING_WINDOW=""
    for ISSUE in $ISSUES; do
      STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
      if [ "$STATUS" = "running" ]; then
        FIRST_RUNNING_WINDOW="ap-#${ISSUE}"
        break
      fi
    done
    if [ -n "$FIRST_RUNNING_WINDOW" ]; then
      "$SESSION_STATE_CMD" wait "$FIRST_RUNNING_WINDOW" exited --timeout 10 2>/dev/null || true
    else
      sleep 10
    fi
  else
    sleep 10
  fi
done
```

## 禁止事項（MUST NOT）

- マーカーファイル (.done/.fail/.merge-ready) を参照してはならない
- state-write.sh を経由せずに issue-{N}.json を直接書き換えてはならない
- crash-detect.sh を経由せずにクラッシュ判定してはならない
