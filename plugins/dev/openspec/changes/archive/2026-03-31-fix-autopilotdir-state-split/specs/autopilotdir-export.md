## MODIFIED Requirements

### Requirement: co-autopilot SKILL.md で AUTOPILOT_DIR を export する

co-autopilot SKILL.md の Step 0 で PROJECT_DIR 取得直後に `AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"` を export しなければならない（SHALL）。これにより Pilot セッション内の全ステップで統一されたパスが使用される。

#### Scenario: bare repo 構成での AUTOPILOT_DIR 設定
- **WHEN** co-autopilot が bare repo 構成（`.bare/` + worktree）で起動される
- **THEN** AUTOPILOT_DIR が `${PROJECT_DIR}/.autopilot` に設定され、全 Step で参照可能である

#### Scenario: standard repo 構成での AUTOPILOT_DIR 設定
- **WHEN** co-autopilot が standard repo 構成（通常の `.git/`）で起動される
- **THEN** AUTOPILOT_DIR が `${PROJECT_DIR}/.autopilot` に設定され、既存動作と互換である

### Requirement: autopilot-init.md で AUTOPILOT_DIR を伝搬する

autopilot-init.md の全スクリプト呼び出し（autopilot-init.sh, session-create.sh）で `AUTOPILOT_DIR=$AUTOPILOT_DIR` を環境変数として渡さなければならない（MUST）。SESSION_STATE_FILE は `$AUTOPILOT_DIR/session.json` を使用する。

#### Scenario: autopilot-init.sh への AUTOPILOT_DIR 伝搬
- **WHEN** autopilot-init.md が autopilot-init.sh を実行する
- **THEN** `AUTOPILOT_DIR` 環境変数がスクリプトに渡され、.autopilot/ が正しいパスに作成される

#### Scenario: SESSION_STATE_FILE の統一
- **WHEN** autopilot-init.md が SESSION_STATE_FILE を設定する
- **THEN** `$AUTOPILOT_DIR/session.json` を参照し、PROJECT_ROOT/.autopilot/ とのパス不一致が発生しない

### Requirement: autopilot-phase-execute.md で AUTOPILOT_DIR を伝搬する

autopilot-phase-execute.md の全スクリプト呼び出し（state-read.sh, state-write.sh, autopilot-should-skip.sh, crash-detect.sh）で `AUTOPILOT_DIR=$AUTOPILOT_DIR` を環境変数として渡さなければならない（MUST）。

#### Scenario: state-read.sh への AUTOPILOT_DIR 伝搬
- **WHEN** autopilot-phase-execute.md が state-read.sh で Issue 状態を読み取る
- **THEN** `AUTOPILOT_DIR` 環境変数が渡され、Worker が書き込んだ issue-{N}.json を正しく参照する

#### Scenario: state-write.sh への AUTOPILOT_DIR 伝搬
- **WHEN** autopilot-phase-execute.md が state-write.sh で状態を更新する
- **THEN** `AUTOPILOT_DIR` 環境変数が渡され、Worker と同じ .autopilot/ に書き込む

#### Scenario: Pilot と Worker の状態ファイル一致
- **WHEN** Worker が issue-{N}.json を `merge-ready` に更新し、Pilot がポーリングする
- **THEN** Pilot の state-read.sh が Worker の状態変更を検知でき、merge-gate に遷移する
