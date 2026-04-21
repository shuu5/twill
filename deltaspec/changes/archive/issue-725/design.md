## Context

supervisor hook は Claude Code の PreToolUse / PostToolUse / Stop フックとして動作し、`.supervisor/events/` ディレクトリにイベントファイルを書き出す（#569）。現在の実装は `AUTOPILOT_DIR` 環境変数でゲートしているが、この変数は co-autopilot Worker セッションにのみ設定される。

bare repo 構造（`.bare/` + `main/` + `worktrees/<branch>/`）では：
- observer は `main/.supervisor/events/` を監視
- Worker は `worktrees/<branch>/` で動作
- `AUTOPILOT_DIR` は Worker セッション起動時に `main/.autopilot` を指す形で設定される

`git rev-parse --git-common-dir` はベア・通常両構造で共通の git データ格納先を返す：
- bare repo: `.bare`（`worktrees/<branch>/` 内から実行した場合）
- 通常 git リポ: `.git`

## Goals / Non-Goals

**Goals:**
- 非 autopilot セッション（co-explore / co-issue 等）からもイベントを発火させる
- `git rev-parse --git-common-dir` ベースで EVENTS_DIR を解決する
- autopilot Worker セッションの後方互換を維持する
- git 外セッション（単純な bash 環境）では静かに exit 0 する

**Non-Goals:**
- 通常 git リポ（non-bare）への対応（bare repo 構造を前提）
- cld-spawn の修正（hook 側のみで完結）
- observer 側の変更

## Decisions

### 決定 1: EVENTS_DIR を `${GIT_COMMON_DIR}/../main/.supervisor/events` で解決

```bash
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
```

bare repo 構造では worktree 内での `--git-common-dir` は `.bare` を返す（フルパス）。
`${GIT_COMMON_DIR}/../main/.supervisor/events` で正しいパスに到達。

**代替案（却下）**: `git rev-parse --show-toplevel`
→ worktree ルートを返し、`worktrees/<branch>/.supervisor/events` になるため不適。

### 決定 2: ゲート条件を `git rev-parse --git-common-dir` の成功のみに変更

```bash
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [[ -z "$GIT_COMMON_DIR" ]]; then
  exit 0
fi
```

git 外セッションでは空文字になるため `exit 0` で静かに終了。`AUTOPILOT_DIR` チェックは不要。

### 決定 3: 全 5 hook に同一パターンを適用

`supervisor-input-wait.sh`, `supervisor-input-clear.sh`, `supervisor-heartbeat.sh`, `supervisor-skill-step.sh`, `supervisor-session-end.sh` の全てに同一の変更パターンを適用。

## Risks / Trade-offs

- **bare repo 前提**: `${GIT_COMMON_DIR}/../main/` というパス構造は bare repo 以外では成立しない。通常 git リポでは `main/` ディレクトリが存在しないため EVENTS_DIR が誤ったパスになる。ただし本プロジェクトは bare repo 構造のため許容。
- **`AUTOPILOT_DIR` 廃止の影響**: 既存テストの `_no_autopilot_dir` 群が「AUTOPILOT_DIR 未設定 → イベント未生成」を期待している。これらをすべて「AUTOPILOT_DIR 未設定 + git 内 → イベント生成」に更新する必要がある。
