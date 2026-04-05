## MODIFIED Requirements

### Requirement: merge-gate-execute.sh reject 時の window cleanup

`merge-gate-execute.sh` は `--reject` および `--reject-final` モードで `status=failed` を設定した後に tmux window を kill しなければならない（SHALL）。

#### Scenario: --reject モードの window cleanup
- **WHEN** `merge-gate-execute.sh --reject` が実行される
- **THEN** `state-write.sh` で `status=failed` を設定した後に `tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true` を実行する

#### Scenario: --reject-final モードの window cleanup
- **WHEN** `merge-gate-execute.sh --reject-final` が実行される
- **THEN** `state-write.sh` で `status=failed` を設定した後に `tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true` を実行する

#### Scenario: window が存在しない場合
- **WHEN** `tmux kill-window` の対象 window が既に存在しない
- **THEN** エラーを無視して処理を続行する
