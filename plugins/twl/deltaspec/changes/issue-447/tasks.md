## 1. spec-review-orchestrator.sh 作成

- [x] 1.1 `plugins/twl/scripts/spec-review-orchestrator.sh` を新規作成する
- [x] 1.2 `--issues-dir` / `--output-dir` 引数パーサーを実装する
- [x] 1.3 `MAX_PARALLEL` 環境変数によるバッチ制御ロジックを実装する
- [x] 1.4 `spec-review-session-init.sh` 呼び出しをオーケストレーター内部に組み込む
- [x] 1.5 tmux new-window + cld セッション起動ロジックを実装する（autopilot-orchestrator.sh のパターン流用）
- [x] 1.6 ポーリングループ（全セッション完了検知）を実装する
- [x] 1.7 結果ファイル（`issue-{N}-result.txt`）書き出しを実装する

## 2. workflow-issue-refine SKILL.md 更新

- [x] 2.1 Step 3b の Issue JSON 書き出し処理を追加する
- [x] 2.2 Step 3b の LLM ループ（`/twl:issue-spec-review` N 回呼び出し）を `spec-review-orchestrator.sh` 呼び出しに置き換える
- [x] 2.3 Step 3c の結果読み込みを `--output-dir` からのファイル読み込みに変更する

## 3. deps.yaml 更新

- [x] 3.1 `spec-review-orchestrator` を `plugins/twl/deps.yaml` に script エントリとして追加する
- [x] 3.2 `workflow-issue-refine` の calls に `spec-review-orchestrator` を追加する
- [x] 3.3 `loom --check` で整合性検証をパスすることを確認する

## 4. 動作確認

- [x] 4.1 1 Issue で `spec-review-orchestrator.sh` が正常動作することを確認する
- [x] 4.2 複数 Issue で MAX_PARALLEL バッチ処理が機能することを確認する
- [x] 4.3 #446 の PreToolUse gate が fallback として引き続き機能することを確認する
