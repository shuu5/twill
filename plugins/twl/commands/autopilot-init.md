# セッション初期化

.autopilot/ ディレクトリ初期化と session.json 作成を行う。
autopilot-init.sh + session-create.sh のラッパー。
co-autopilot Step 3 から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$PLAN_FILE` | plan.yaml のパス（必須） |

## 実行ロジック（MUST）

### Step 1: 旧マーカーファイル残存チェック

```bash
if [ -d /tmp/dev-autopilot ] && ls /tmp/dev-autopilot/*.done /tmp/dev-autopilot/*.fail /tmp/dev-autopilot/*.merge-ready /tmp/dev-autopilot/*.running 2>/dev/null | head -1 >/dev/null 2>&1; then
  echo "WARN: 旧マーカーファイルが /tmp/dev-autopilot/ に残存しています。新アーキテクチャでは使用されません。"
fi
```

### Step 2: .autopilot/ 初期化

```bash
AUTOPILOT_DIR=$AUTOPILOT_DIR bash $SCRIPTS_ROOT/autopilot-init.sh
```

- 成功時: .autopilot/, .autopilot/issues/, .autopilot/archive/ が作成される
- 排他制御: 既存セッション検出時はエラー終了（24h 以内）
- stale セッション（24h 超）: `--force` で強制削除可
- 完了済みセッション（全 issue done）: `--force` で即座に削除可

### Step 3: Phase 数取得

```bash
PHASE_COUNT=$(grep -c "^  - phase:" "$PLAN_FILE")
```

### Step 4: session.json 作成

```bash
SESSION_OUTPUT=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.session create --plan-path "$PLAN_FILE" --phase-count "$PHASE_COUNT")
SESSION_ID=$(echo "$SESSION_OUTPUT" | grep -oP 'session_id=\K[0-9a-f]+')
```

成功時: 出力 `OK: session.json を作成しました (session_id=XXXX)` から SESSION_ID を取得。

### Step 5: 出力変数設定

co-autopilot に返却する変数:

```bash
SESSION_ID=<Step 4 で取得した値>
PHASE_COUNT=<Step 3 で取得した値>
SESSION_STATE_FILE="$AUTOPILOT_DIR/session.json"
```

## 禁止事項（MUST NOT）

- session.json を直接作成してはならない（python3 -m twl.autopilot.session create に委譲）
- .autopilot/ を直接 mkdir してはならない（autopilot-init.sh に委譲）
- 排他制御を迂回してはならない
