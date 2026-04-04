## ADDED Requirements

### Requirement: auto-merge フォールバックガード（issue-{N}.json 直接確認）

`auto-merge.md` Step 0 は、`IS_AUTOPILOT=false` かつ `ISSUE_NUM` が設定されている場合、main worktree の `.autopilot/issue-{N}.json` を直接確認しなければならない（SHALL）。ファイルが存在する場合は merge を禁止し、`merge-ready` に遷移して正常終了しなければならない（MUST）。

この検証は `state-read.sh` を使用せず、ファイルシステムの直接存在確認で行わなければならない（SHALL）。

#### Scenario: IS_AUTOPILOT=false 誤判定 + issue-{N}.json 存在
- **WHEN** `IS_AUTOPILOT=false` と判定され、かつ main worktree の `.autopilot/issue-${ISSUE_NUM}.json` が存在する
- **THEN** merge を実行せず、`state-write.sh` で `status=merge-ready` に遷移し、警告メッセージを出力して正常終了する

#### Scenario: IS_AUTOPILOT=false + issue-{N}.json 不在（通常利用）
- **WHEN** `IS_AUTOPILOT=false` と判定され、かつ main worktree の `.autopilot/issue-${ISSUE_NUM}.json` が存在しない
- **THEN** 既存の merge フローを維持し、Step 1 以降を通常実行する

#### Scenario: ISSUE_NUM 未設定（通常利用）
- **WHEN** `ISSUE_NUM` が未設定（空文字列）である
- **THEN** フォールバックチェックをスキップし、既存の merge フローを通常実行する

### Requirement: merge-gate-execute Worker ロール検出ガード

`merge-gate-execute.sh` は、tmux window 名が `ap-#*` パターンに一致する場合、merge を拒否しなければならない（MUST）。このガードは CWD ガードの後、merge 実行の前に配置しなければならない（SHALL）。

#### Scenario: autopilot Worker tmux window からの merge 実行
- **WHEN** tmux window 名が `ap-#86` 等の `ap-#*` パターンに一致する
- **THEN** エラーメッセージを出力し、exit 1 で終了する（merge を実行しない）

#### Scenario: 非 autopilot tmux window からの merge 実行
- **WHEN** tmux window 名が `ap-#*` パターンに一致しない（例: `main`, `bash`, 空）
- **THEN** 従来通り merge フローを続行する

#### Scenario: tmux 外からの merge 実行
- **WHEN** `tmux display-message` がエラーを返す（tmux セッション外）
- **THEN** Worker ロール検出をスキップし、従来通り merge フローを続行する

## MODIFIED Requirements

### Requirement: auto-merge-guard 誤判定シナリオ追加

既存の `auto-merge-guard.md` に `IS_AUTOPILOT=false` 誤判定のシナリオを追加しなければならない（SHALL）。フォールバックガードによる防止を検証するシナリオを含めなければならない（MUST）。

#### Scenario: AUTOPILOT_DIR 伝搬バグによる誤判定からのフォールバック防止
- **WHEN** Worker の `AUTOPILOT_DIR` が空で `state-read.sh` が `issue-{N}.json` を発見できず `IS_AUTOPILOT=false` と判定される
- **THEN** フォールバックガードが main worktree の `.autopilot/issue-{N}.json` を検出し、merge を禁止して `merge-ready` に遷移する
