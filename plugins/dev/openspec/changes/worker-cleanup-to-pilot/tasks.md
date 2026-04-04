## 1. merge-gate-execute.sh: IS_AUTOPILOT分岐追加

- [x] 1.1 現在のmerge-gate-execute.shのクリーンアップ処理位置を特定（L89, L97, L125-145, L152）
- [x] 1.2 IS_AUTOPILOT判定ロジックを実装: `${AUTOPILOT_DIR:-.autopilot}/issues/issue-${ISSUE_NUM}.json` の存在確認
- [x] 1.3 merge成功後のworktree削除 / リモートブランチ削除 / tmux kill-windowをautopilot時にスキップする分岐を追加
- [x] 1.4 スキップ時に「Pilotへ委譲」のメッセージを出力する

## 2. autopilot-orchestrator.sh: cleanupシーケンス追加

- [x] 2.1 autopilot-orchestrator.shのmerge-gate PASS判定箇所を特定
- [x] 2.2 クリーンアップシーケンスを追加: `tmux kill-window -t "ap-#${ISSUE_NUM}"`
- [x] 2.3 クリーンアップシーケンスを追加: `worktree-delete.sh` 呼び出し（ローカルブランチ込み）
- [x] 2.4 クリーンアップシーケンスを追加: `git push origin --delete "${BRANCH}"` （クロスリポ対応）
- [x] 2.5 各ステップを独立実行し、失敗は警告のみで次ステップ継続するエラーハンドリングを実装
- [x] 2.6 tmux window不在 / worktree既削除を正常扱いにする冪等処理を実装

## 3. クロスリポジトリcleanup対応

- [x] 3.1 issue-{N}.jsonの`repo`フィールド読み取りロジックを実装
- [x] 3.2 `repo`フィールドが存在し異なるリポジトリの場合、リモートブランチ削除を対象リポジトリのパスで実行する処理を追加

## 4. autopilot-phase-execute.md: tmux kill-window重複排除

- [x] 4.1 `commands/autopilot-phase-execute.md`のtmux kill-window呼び出し箇所を特定（L122, L177）
- [x] 4.2 autopilot-orchestrator.shがcleanupを担当するため、重複するtmux kill-window呼び出しを削除

## 5. 動作確認

- [x] 5.1 worktree-delete.shがPilotからの呼び出しで正常動作することを確認（インターフェース互換性）
- [x] 5.2 非autopilot（手動merge）パスの動作が変更されていないことを確認
- [x] 5.3 `loom check` でdeps.yaml整合性を確認
- [x] 5.4 `loom update-readme` でREADME更新
