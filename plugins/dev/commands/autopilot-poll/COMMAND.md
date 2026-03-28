# Issue 状態ポーリング

state-read.sh を使用して Issue 状態をポーリングし、crash-detect.sh でクラッシュ検知を行う。
autopilot-phase-execute から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$ISSUE` | 対象 Issue 番号（single モード） |
| `$ISSUES` | Phase 内の全 Issue 番号リスト（phase モード、スペース区切り） |
| `$POLL_MODE` | `single` or `phase` |
| `$SESSION_STATE_FILE` | session.json のパス |

## 実行ロジック（MUST）

### poll_single（単一 Issue ポーリング）

```bash
MAX_POLL=360  # 360回 × 10秒 = 60分
POLL_COUNT=0
WINDOW_NAME="ap-#${ISSUE}"

while true; do
  sleep 10
  POLL_COUNT=$((POLL_COUNT + 1))

  STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)

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
      # クラッシュ検知
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
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot \
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
    STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)

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
      STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
      if [ "$STATUS" = "running" ]; then
        bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot \
          --set "status=failed" \
          --set "failure={\"message\": \"poll_timeout\", \"step\": \"polling\"}"
      fi
    done
    break
  fi

  sleep 10
done
```

## 禁止事項（MUST NOT）

- マーカーファイル (.done/.fail/.merge-ready) を参照してはならない
- state-write.sh を経由せずに issue-{N}.json を直接書き換えてはならない
- crash-detect.sh を経由せずにクラッシュ判定してはならない
