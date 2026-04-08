---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 10
---
# Worker 起動

tmux window を作成し Worker（cld）を起動する。
autopilot-phase-execute から呼び出される。
決定的ロジックは `scripts/autopilot-launch.sh` に委譲し、本コマンドはコンテキスト構築のみ担当する。

## 前提変数

| 変数 | 説明 | スクリプトフラグ |
|------|------|----------------|
| `$ISSUE` | Issue 番号（数値） | `--issue` |
| `$PROJECT_DIR` | プロジェクトディレクトリ（デフォルトリポジトリ） | `--project-dir` |
| `$CROSS_ISSUE_WARNINGS` | cross-issue 警告の連想配列（Issue番号→警告メッセージ） | `--context` に含める |
| `$PHASE_INSIGHTS` | 前 Phase の retrospective 知見（空の場合あり） | `--context` に含める |
| `$ISSUE_REPO_OWNER` | リポジトリ owner（クロスリポジトリ時） | `--repo-owner` |
| `$ISSUE_REPO_NAME` | リポジトリ name（クロスリポジトリ時） | `--repo-name` |
| `$ISSUE_REPO_PATH` | リポジトリパス（クロスリポジトリ時） | `--repo-path` |
| `$PILOT_AUTOPILOT_DIR` | Pilot 側の .autopilot/ パス（Worker の AUTOPILOT_DIR に設定） | `--autopilot-dir` |

## 実行ロジック（MUST）

### Step 1: コンテキスト注入構築

LLM がコンテキストテキストを構築する（唯一の LLM 担当ステップ）。

```bash
CONTEXT_TEXT=""

# cross-issue 警告（high confidence のみ）
if [ -n "${CROSS_ISSUE_WARNINGS[$ISSUE]:-}" ]; then
  CONTEXT_TEXT="[Cross-Issue Warning] 以下のIssueが関連ファイルを変更済みです（競合に注意）:"$'\n'"${CROSS_ISSUE_WARNINGS[$ISSUE]}"
fi

# retrospective 知見（強度別分岐）
if [ -n "${PHASE_INSIGHTS:-}" ]; then
  # [must] プレフィックスの知見を抽出 → MUST 要件セクションに直接注入
  MUST_INSIGHTS=$(echo "$PHASE_INSIGHTS" | grep '^\[must\]' | sed 's/^\[must\] *//' || true)
  # [warning] / [info] / プレフィックスなしの知見 → 参考情報セクションに注入
  OTHER_INSIGHTS=$(echo "$PHASE_INSIGHTS" | grep -v '^\[must\]' || true)

  if [ -n "$MUST_INSIGHTS" ]; then
    [ -n "$CONTEXT_TEXT" ] && CONTEXT_TEXT="${CONTEXT_TEXT}"$'\n\n'
    CONTEXT_TEXT="${CONTEXT_TEXT}[MUST] 前Phaseで繰り返し検出された失敗パターンに基づく必須要件:"$'\n'"${MUST_INSIGHTS}"
  fi

  # ホスト/コンテナ分離ルール（常時注入）
  [ -n "$CONTEXT_TEXT" ] && CONTEXT_TEXT="${CONTEXT_TEXT}"$'\n\n'
  CONTEXT_TEXT="${CONTEXT_TEXT}[MUST] ホスト/コンテナ分離ルール:
- テスト実行（pytest, bats, npm test）はコンテナ内で行うこと。ホストでの直接実行は禁止
- pip install, apt-get install 等のパッケージ導入はホストで行わないこと
- --break-system-packages フラグの使用は禁止"

  if [ -n "$OTHER_INSIGHTS" ]; then
    [ -n "$CONTEXT_TEXT" ] && CONTEXT_TEXT="${CONTEXT_TEXT}"$'\n\n'
    CONTEXT_TEXT="${CONTEXT_TEXT}[Retrospective] 前Phaseからの参考情報（ワーカーの判断を制約しない）:"$'\n'"${OTHER_INSIGHTS}"
  fi
fi
```

### Step 2: スクリプト呼び出し

```bash
EFFECTIVE_AUTOPILOT_DIR="${PILOT_AUTOPILOT_DIR:-${PROJECT_DIR}/.autopilot}"

# 基本引数
LAUNCH_ARGS="--issue $ISSUE --project-dir $PROJECT_DIR --autopilot-dir $EFFECTIVE_AUTOPILOT_DIR"

# コンテキスト（あれば）
if [ -n "$CONTEXT_TEXT" ]; then
  LAUNCH_ARGS="$LAUNCH_ARGS --context $CONTEXT_TEXT"
fi

# クロスリポジトリ（あれば）
if [ -n "${ISSUE_REPO_OWNER:-}" ] && [ -n "${ISSUE_REPO_NAME:-}" ]; then
  LAUNCH_ARGS="$LAUNCH_ARGS --repo-owner $ISSUE_REPO_OWNER --repo-name $ISSUE_REPO_NAME"
fi
if [ -n "${ISSUE_REPO_PATH:-}" ]; then
  LAUNCH_ARGS="$LAUNCH_ARGS --repo-path $ISSUE_REPO_PATH"
fi

bash "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-launch.sh" $LAUNCH_ARGS
```

## 禁止事項（MUST NOT）

- DEV_AUTOPILOT_SESSION 環境変数を設定してはならない
- マーカーファイル (.pilot-controlled 等) を作成してはならない
- issue-{N}.json を直接作成してはならない（state-write.sh --init に委譲）
- `cld -p` / `cld --print` を使用してはならない（非対話 print モードで起動し、Worker が即終了する）
- バリデーション、cld 解決、tmux 起動、クラッシュ検知フックを直接実行してはならない（スクリプトに委譲済み）
