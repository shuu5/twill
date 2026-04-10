## 1. autopilot.md に不変条件 L を追加

- [ ] 1.1 `architecture/autopilot.md` の Constraints セクションを確認する
- [ ] 1.2 不変条件 L「autopilot 時のマージ実行は Orchestrator の mergegate.py 経由のみ。Worker chain の auto-merge ステップは merge-ready 宣言のみを行い、マージは実行しない」を追加する

## 2. autopilot-orchestrator.sh の fallback パスのコメント修正

- [ ] 2.1 `plugins/twl/scripts/autopilot-orchestrator.sh` の line 868 付近の fallback パスを確認する
- [ ] 2.2 「auto-merge.sh にフォールバック」などの誤解を招くコメントを実態（`return 1` のみ）に合わせて修正する

## 3. 検証

- [ ] 3.1 `git diff` で変更ファイルが `architecture/autopilot.md` と `autopilot-orchestrator.sh` のみであることを確認する
- [ ] 3.2 auto-merge.sh、mergegate.py、chain-runner.sh に変更がないことを確認する
