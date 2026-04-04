## 1. resolve_issue_num 関数の新設

- [x] 1.1 `scripts/resolve-issue-num.sh` を新規作成し `resolve_issue_num()` 関数を実装する
- [x] 1.2 AUTOPILOT_DIR 設定時に `$AUTOPILOT_DIR/issues/issue-*.json` をスキャンして `status=running` の Issue 番号を取得するロジックを実装する
- [x] 1.3 複数 running 時に最小番号を採用するロジックを実装する
- [x] 1.4 壊れた JSON をスキップして stderr に警告を出力するエラーハンドリングを実装する
- [x] 1.5 AUTOPILOT_DIR 未設定または running 0 件時に `git branch --show-current` フォールバックを実装する

## 2. chain-runner.sh の移行

- [x] 2.1 `scripts/chain-runner.sh` に `source scripts/resolve-issue-num.sh` を追加する
- [x] 2.2 `extract_issue_num()` の全呼び出し箇所を `resolve_issue_num()` に置換する
- [x] 2.3 `extract_issue_num()` 関数定義を削除する

## 3. post-skill-chain-nudge.sh の移行

- [x] 3.1 `scripts/hooks/post-skill-chain-nudge.sh` の L27 付近の Issue 番号取得を `resolve_issue_num()` に置換する
- [x] 3.2 `source scripts/resolve-issue-num.sh` を追加する

## 4. refs/ref-dci.md の更新

- [x] 4.1 `refs/ref-dci.md` の ISSUE_NUM 取得標準パターンを `resolve_issue_num()` ベースに更新する
- [x] 4.2 `git branch --show-current` はフォールバックとして明記し推奨パターンから外す

## 5. SKILL.md 群の bash スニペット更新

- [x] 5.1 `skills/workflow-setup/SKILL.md` の IS_AUTOPILOT 判定ブロックを `resolve_issue_num()` 統一パターンに更新する
- [x] 5.2 `skills/workflow-test-ready/SKILL.md` の IS_AUTOPILOT 判定ブロックを統一パターンに更新する（L24, L119, L131, L139, L159 付近）
- [x] 5.3 `skills/workflow-pr-cycle/SKILL.md` の IS_AUTOPILOT 判定ブロックを統一パターンに更新する（L148 付近）

## 6. commands の DCI コンテキスト更新

- [x] 6.1 `commands/merge-gate.md` の ISSUE_NUM 取得記述を `resolve_issue_num()` ベースに更新する
- [x] 6.2 `commands/all-pass-check.md` の ISSUE_NUM 取得記述を更新する
- [x] 6.3 `commands/ac-verify.md` の ISSUE_NUM 取得記述を更新する
- [x] 6.4 `commands/self-improve-propose.md` の L95 付近の ISSUE_NUM 取得を更新する

## 7. 検証

- [x] 7.1 `git branch --show-current` 依存呼び出しがフォールバック以外で 0 件になっていることを確認する（grep で検証）
- [x] 7.2 AUTOPILOT_DIR 設定時に `resolve_issue_num()` が state file から番号を返すことを手動テストする
- [x] 7.3 AUTOPILOT_DIR 未設定時に git branch フォールバックが動作することを確認する
