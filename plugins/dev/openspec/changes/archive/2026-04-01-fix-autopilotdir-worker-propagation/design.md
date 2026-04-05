## Context

autopilot の Worker プロセス起動パスには2つの環境変数注入ポイントがある:

1. **autopilot-phase-execute.md** `resolve_issue_repo_context()`: Issue ごとにリポジトリコンテキストを解決し、`PILOT_AUTOPILOT_DIR` を設定
2. **autopilot-launch.md** Step 5: `PILOT_AUTOPILOT_DIR` を `AUTOPILOT_ENV` として tmux new-window の env プレフィックスに変換

単一リポジトリ時、`resolve_issue_repo_context()` の else 分岐で `PILOT_AUTOPILOT_DIR="$AUTOPILOT_DIR"` と設定するが、`$AUTOPILOT_DIR` は LLM の会話コンテキスト内で `export` されるため、bash 実行時に参照できない。結果として `PILOT_AUTOPILOT_DIR` が空になり、autopilot-launch.md の条件分岐で `AUTOPILOT_ENV` がスキップされる。

## Goals / Non-Goals

**Goals:**

- 単一リポジトリ時に Worker の tmux 環境に `AUTOPILOT_DIR` を確実に設定する
- クロスリポジトリ時の既存動作を変更しない
- LLM コンテキスト依存を排除し、明示的な絶対パスで設定する

**Non-Goals:**

- autopilot-poll.md の `AUTOPILOT_DIR` 伝搬（Pilot 側で実行されるため別 Issue）
- state-read.sh 自体の修正（呼び出し元の環境変数が正しければ動作する）

## Decisions

### D1: resolve_issue_repo_context() の else 分岐修正

単一リポジトリ時の else 分岐で `PILOT_AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"` と明示設定する。`$AUTOPILOT_DIR` への参照を排除し、`$PROJECT_DIR`（スクリプト冒頭で確定済み）から導出する。

**理由**: `$AUTOPILOT_DIR` は LLM コンテキスト内の export に依存するため不安定。`$PROJECT_DIR` はスクリプト実行時に確定しており信頼性が高い。

### D2: autopilot-launch.md の AUTOPILOT_ENV フォールバック

`PILOT_AUTOPILOT_DIR` が空の場合、`${PROJECT_DIR}/.autopilot` をフォールバックとして使用する。条件分岐を「空でなければ使う」から「常にデフォルト付きで設定」に変更する。

**理由**: 防御的設計として、PILOT_AUTOPILOT_DIR が何らかの理由で空になっても Worker が正しく動作するようにする。

## Risks / Trade-offs

- **リスク**: `PROJECT_DIR` が worktree パス（`worktrees/feat-xxx/`）を指す場合、`.autopilot/` は `main/` 配下にあるため不整合が発生する可能性 → autopilot-phase-execute では `PROJECT_DIR` は常に main worktree のルートを指すことを確認済み
- **トレードオフ**: D2 のフォールバックにより autopilot-launch.md に冗長なロジックが増えるが、安全性を優先する
