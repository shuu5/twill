## 1. autopilot-orchestrator.sh: stdout 限定

- [x] 1.1 line 192, 197 の `echo "[orchestrator] Issue #${ISSUE}: skip..."` に `>&2` を追加
- [x] 1.2 line 251, 254, 257, 264, 274 のループ内 Issue 進捗 echo に `>&2` を追加
- [x] 1.3 line 306, 319, 397, 422, 427, 434, 436 の残り echo に `>&2` を追加
- [x] 1.4 `run_phase` 関数先頭に `mkdir -p "$AUTOPILOT_DIR/logs"` を追加

## 2. co-autopilot/SKILL.md: stderr リダイレクト

- [x] 2.1 `REPORT=$(bash $SCRIPTS_ROOT/autopilot-orchestrator.sh ... $REPOS_ARG)` を `REPORT=$(bash ... $REPOS_ARG 2>"$AUTOPILOT_DIR/logs/phase-${P}.log")` に変更

## 3. autopilot-phase-postprocess.md: token_estimate 記録

- [x] 3.1 実行ロジック冒頭（Step 1 の前）に `START_TIME=$(date +%s)` の記録ステップを追加
- [x] 3.2 全ステップ完了後（cross-issue の後）に `END_TIME=$(date +%s)` と `token_estimate=$((END_TIME - START_TIME))` の計算ステップを追加
- [x] 3.3 session.json の当該 Phase retrospective エントリに `token_estimate` を書き込む手順を追加（`jq` で update）

## 4. 確認

- [x] 4.1 orchestrator.sh の echo 行で `>&2` が漏れていないか grep で全確認
- [x] 4.2 `generate_phase_report` の出力が stdout に残っていることを確認
