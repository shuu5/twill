## Context

`workflow-issue-refine` の Step 3b では LLM が N Issue を順次 `/twl:issue-spec-review` に渡す。Issue 数が多い（5+）と LLM のコンテキストが圧迫され、全 Issue を処理しきれずに forward progression gate deny を繰り返すリスクがある。`autopilot-orchestrator.sh` は「Bash for ループで N 回の tmux cld セッション spawn → ポーリング → 結果収集」パターンを確立済みであり、同パターンを spec-review に転用する。

## Goals / Non-Goals

**Goals:**

- `spec-review-orchestrator.sh` を新規作成し、Issue ごとに独立した tmux cld セッションを Bash ループで spawn する
- `workflow-issue-refine` Step 3b をオーケストレーター呼び出しに変更して LLM ループを排除する
- `MAX_PARALLEL` 環境変数でバッチサイズを制御できるようにする（デフォルト: 3）
- 1 Issue の場合もバッチサイズ 1 で正常動作する

**Non-Goals:**

- PreToolUse gate の変更（#446 対応済み。fallback として残す）
- autopilot-orchestrator.sh 本体の変更
- マニフェスト追跡修復（#445 対応済み）

## Decisions

### D1: autopilot-orchestrator.sh パターンを直接流用

autopilot-orchestrator.sh の「tmux new-window + cld セッション起動 + ポーリング」パターンをそのまま spec-review に適用する。異なる点は入力が plan.yaml ではなく `--issues-dir` 内の `issue-*.json` ファイル群であること、worker コマンドが `/twl:issue-spec-review` であること。

### D2: I/O は一時ディレクトリ経由でファイル受け渡し

- 入力: `--issues-dir` 内の `issue-{N}.json`（1 ファイル = 1 Issue。Issue 番号・body・scope_files・related_issues を格納）
- 出力: `--output-dir` 内の `issue-{N}-result.txt`（specialist_results をそのまま書き出し）
- 親セッションが結果ファイルを読み込み Step 3c に渡す

### D3: workflow-issue-refine は Step 3b をオーケストレーター委譲に置き換える

Step 3b の全 `/twl:issue-spec-review` 呼び出しロジックを削除し、以下に置き換える:
1. Issue JSON ファイルを `--issues-dir` に書き出す
2. `spec-review-orchestrator.sh --issues-dir ... --output-dir ...` を呼び出す
3. 結果ファイルを読み込んで Step 3c に渡す

セッション初期化（`spec-review-session-init.sh`）はオーケストレーター内部で行う。

## Risks / Trade-offs

- **tmux 依存**: tmux が起動していない環境では動作しない。ただし現プロジェクト環境では tmux 使用を前提としている
- **ポーリングオーバーヘッド**: Issue 数が少ない（1-2）場合は LLM ループの方が軽量だが、一貫性のためオーケストレーター経由とする
- **デバッグ複雑化**: 各セッションが独立しているため、失敗時のログは各 tmux ウィンドウを参照する必要がある
