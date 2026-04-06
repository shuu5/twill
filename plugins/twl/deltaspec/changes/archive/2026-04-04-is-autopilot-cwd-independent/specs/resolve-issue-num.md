## ADDED Requirements

### Requirement: resolve_issue_num 関数の新設
`scripts/resolve-issue-num.sh` に `resolve_issue_num()` 関数を実装しなければならない（SHALL）。この関数は AUTOPILOT_DIR が設定されている場合は state file スキャンを優先し、未設定またはスキャン結果が0件の場合は `git branch --show-current` にフォールバックしなければならない（SHALL）。

#### Scenario: AUTOPILOT_DIR 設定時に running issue から番号取得
- **WHEN** AUTOPILOT_DIR が設定されており、`$AUTOPILOT_DIR/issues/issue-42.json` に `status=running` が存在する
- **THEN** `resolve_issue_num()` が `42` を返す

#### Scenario: running issue が複数件存在する場合に最小番号を採用
- **WHEN** AUTOPILOT_DIR 配下に `issue-42.json`（running）と `issue-100.json`（running）が存在する
- **THEN** `resolve_issue_num()` が `42`（最小番号）を返す

#### Scenario: running issue が0件の場合にフォールバック
- **WHEN** AUTOPILOT_DIR 配下に running 状態の issue が存在しない
- **THEN** `resolve_issue_num()` が `git branch --show-current` のパース結果を返す

#### Scenario: AUTOPILOT_DIR 未設定時にフォールバック
- **WHEN** AUTOPILOT_DIR 環境変数が未設定
- **THEN** `resolve_issue_num()` が `git branch --show-current` のパース結果を返す

#### Scenario: 壊れた JSON をスキップして続行
- **WHEN** AUTOPILOT_DIR 配下に JSON 解析不能なファイルが存在する
- **THEN** `resolve_issue_num()` がそのファイルをスキップし stderr に警告を出力して続行する

## MODIFIED Requirements

### Requirement: chain-runner.sh の Issue 番号解決を resolve_issue_num に移行
`scripts/chain-runner.sh` の `extract_issue_num()` 呼び出し箇所を `resolve_issue_num()` に置換しなければならない（SHALL）。`extract_issue_num()` は廃止する（SHALL）。

#### Scenario: chain-runner.sh が AUTOPILOT_DIR から Issue 番号を取得する
- **WHEN** AUTOPILOT_DIR が設定された状態で chain-runner.sh が実行される
- **THEN** `git branch --show-current` を呼ばずに state file から Issue 番号を解決する

### Requirement: post-skill-chain-nudge.sh の Issue 番号解決を resolve_issue_num に移行
`scripts/hooks/post-skill-chain-nudge.sh` の Issue 番号取得箇所を `resolve_issue_num()` に置換しなければならない（SHALL）。

#### Scenario: nudge フックが CWD に依存せず Issue 番号を取得する
- **WHEN** nudge フックが worktree 外の CWD から実行される
- **THEN** AUTOPILOT_DIR から正しい Issue 番号を取得する

### Requirement: refs/ref-dci.md の DCI 標準パターン更新
`refs/ref-dci.md` の ISSUE_NUM 取得パターンを state file ベース優先に変更しなければならない（SHALL）。`git branch --show-current` はフォールバックとして明記する（SHALL）。

#### Scenario: ref-dci.md のサンプルコードが新パターンを示す
- **WHEN** 開発者が ref-dci.md を参照して IS_AUTOPILOT 判定を実装する
- **THEN** `resolve_issue_num()` の使用例が示されており git branch はフォールバックとして記述されている

### Requirement: SKILL.md 群の bash スニペット更新
`skills/workflow-setup/SKILL.md`、`skills/workflow-test-ready/SKILL.md`、`skills/workflow-pr-cycle/SKILL.md` の IS_AUTOPILOT 判定ブロックを `resolve_issue_num()` を使う統一パターンに更新しなければならない（SHALL）。

#### Scenario: SKILL.md の bash スニペットが新パターンを使用する
- **WHEN** workflow-setup の bash スニペットが実行される
- **THEN** `source scripts/resolve-issue-num.sh` → `resolve_issue_num()` の順で Issue 番号を取得する

### Requirement: commands の DCI コンテキスト更新
`commands/merge-gate.md`、`commands/all-pass-check.md`、`commands/ac-verify.md`、`commands/self-improve-propose.md` の ISSUE_NUM 取得記述を `resolve_issue_num()` ベースに更新しなければならない（SHALL）。

#### Scenario: merge-gate コマンドが state file から Issue 番号を取得する
- **WHEN** merge-gate が autopilot セッション内で実行される
- **THEN** AUTOPILOT_DIR から Issue 番号を解決する
