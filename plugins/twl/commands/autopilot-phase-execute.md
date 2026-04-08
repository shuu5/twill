---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 30
---
# Phase Issue ループ実行

1 Phase 分の全 Issue に対して launch → poll → merge-gate → window 管理を実行する。
state-read.sh / state-write.sh で状態管理。co-autopilot の Phase ループから呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$P` | 現在の Phase 番号 |
| `$SESSION_STATE_FILE` | session.json のパス |
| `$MODE` | `sequential` or `parallel` |
| `$PLAN_FILE` | plan.yaml のパス |
| `$SESSION_ID` | autopilot セッション ID |
| `$PROJECT_DIR` | プロジェクトディレクトリ（デフォルトリポジトリ） |
| `$REPO_MODE` | `standard` or `worktree` |
| `$CROSS_ISSUE_WARNINGS` | cross-issue 警告の連想配列 |
| `$PHASE_INSIGHTS` | 前 Phase の知見（空の場合あり） |
| `$REPOS_JSON` | repos セクション JSON（クロスリポジトリ時。空の場合は単一リポジトリ） |

## 実行ロジック（MUST）

### Step 0: MAX_PARALLEL の決定

```bash
MAX_PARALLEL=${DEV_AUTOPILOT_MAX_PARALLEL:-4}
if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_PARALLEL=4
fi
```

### Step 1: Phase 内 Issue リスト取得

`plan.yaml` から Phase ブロックを `sed` で抽出し、フォーマット判定:
- **クロスリポジトリ** (`{ number: N, repo: id }`): `ISSUES_WITH_REPO` 配列に `"repo_id:number"` 形式で格納。混合フォーマットの bare int は `_default:N` として追加
- **レガシー** (bare int): 全て `_default:N` として ISSUES_WITH_REPO に格納

`resolve_issue_repo_context(entry)` で `ISSUES_WITH_REPO` エントリから以下の変数をセット:
- `ISSUE` (番号), `ISSUE_REPO_ID` (repo_id)
- `_default` → 空文字セット（単一リポジトリ）
- それ以外 → `$REPOS_JSON` から jq で `ISSUE_REPO_OWNER`, `ISSUE_REPO_NAME`, `ISSUE_REPO_PATH` を取得
- `PILOT_AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"` を常にセット

### Step 2: 実行モード分岐

#### 2a. sequential モード（standard repo）

各 Issue を順に処理:
1. done → スキップ、should_skip → skipped
2. `commands/autopilot-launch.md` Read → Worker 起動
3. `commands/autopilot-poll.md` Read → POLL_MODE=single でポーリング
4. running なら `health-check.sh --issue $ISSUE --window "ap-#${ISSUE}"` で異常検知
5. merge-ready → `commands/merge-gate.md` Read → merge-gate 実行
6. done → 状態記録、failed → 残り全 Issue を skipped → break

#### 2b. parallel モード（worktree repo）

1. done/skip を除外して ACTIVE_ISSUES を構築
2. MAX_PARALLEL 個ずつバッチ分割
3. バッチ内を並列 launch（`commands/autopilot-launch.md`）
4. POLL_MODE=phase でバッチ全体ポーリング（`commands/autopilot-poll.md`）
5. running Issue に health-check 実行
6. merge-ready Issue に merge-gate 順次実行（`commands/merge-gate.md`）
7. 各 Issue の状態記録（done/failed）

**共通**: state read/write は `AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state` 経由。tmux kill-window は orchestrator が担当（不変条件B）。

### Step 3: 状態ファイル更新

各 Issue の完了状態を state-write.sh で記録:

```bash
# done の場合
AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
  --set "status=done" --set "pr_number=$PR_NUMBER"

# skipped の場合
AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
  --set "status=failed" --set "failure={\"message\": \"dependency_failed\", \"step\": \"skip\"}"

# fail 情報は crash-detect.sh / autopilot-poll が既に記録済み
```

## 不変条件の遵守（MUST）

- **不変条件 D**: 依存先 fail 時は後続 Issue を自動 skip
- **不変条件 E**: merge-gate リジェクト → 再実行は 1 Issue 最大 1 回。2 回目は確定失敗
- **不変条件 F**: merge-gate 失敗時に rebase を試みてはならない

## 禁止事項（MUST NOT）

- マーカーファイルを参照してはならない
- `.fail` window を自動クローズしてはならない
- merge-gate 失敗時に rebase を試みてはならない（停止のみ）
- merge-gate リジェクト後の再実行を 2 回以上行ってはならない
