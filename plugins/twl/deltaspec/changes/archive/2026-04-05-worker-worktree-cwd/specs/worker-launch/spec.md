## ADDED Requirements

### Requirement: worktree ディレクトリでの Worker 起動

autopilot-launch.sh は `--worktree-dir DIR` 引数を受け取り、Worker の cld セッションを worktree ディレクトリから起動しなければならない（SHALL）。

#### Scenario: --worktree-dir 引数が渡された場合
- **WHEN** `autopilot-launch.sh --issue N --project-dir DIR --autopilot-dir DIR --worktree-dir /path/to/worktree` が呼ばれる
- **THEN** cld セッションが `/path/to/worktree` を CWD として起動される

#### Scenario: --worktree-dir 引数がない場合（後方互換）
- **WHEN** `autopilot-launch.sh --issue N --project-dir DIR --autopilot-dir DIR` が `--worktree-dir` なしで呼ばれる
- **THEN** 従来の LAUNCH_DIR 計算ロジック（bare repo → main/、通常 → project-dir）が適用される

---

### Requirement: Pilot による worktree 事前作成

autopilot-orchestrator.sh は `autopilot-launch.sh` 呼び出し前に `worktree-create.sh` を実行し、worktree パスを `--worktree-dir` 引数として渡さなければならない（MUST）。

#### Scenario: 新規 Issue の Worker 起動
- **WHEN** Pilot が新規 Issue の Worker を起動する
- **THEN** worktree-create.sh が先に実行され、作成された worktree パスが --worktree-dir として autopilot-launch.sh に渡される

#### Scenario: リトライ時（既存 worktree あり）
- **WHEN** 既存の worktree が存在する状態で Pilot が Worker を再起動する
- **THEN** worktree-create.sh が冪等に処理し既存パスを返し、--worktree-dir として渡される

## MODIFIED Requirements

### Requirement: Worker の chain から worktree-create を除去

chain-steps.sh の `CHAIN_STEPS` 配列は `worktree-create` を含んではならない（MUST NOT）。Worker は起動時点で既に worktree ディレクトリにいるため、chain 内での worktree 作成は不要である（SHALL）。

#### Scenario: Worker が chain を実行する
- **WHEN** Worker が chain-steps.sh を参照して chain を実行する
- **THEN** `worktree-create` ステップが chain に存在せず、init → board-status-update → ... と続く

#### Scenario: next-step の解決
- **WHEN** `chain-runner.sh next-step $ISSUE "init"` が呼ばれる
- **THEN** 返り値は `board-status-update`（worktree-create ではない）

### Requirement: 不変条件B の更新

architecture/domain/contexts/autopilot.md の不変条件B は「Worktree の作成・削除は Pilot が行う。Worker は使用のみ」と定義されなければならない（SHALL）。

#### Scenario: 不変条件B の参照
- **WHEN** autopilot.md の Constraints セクションを参照する
- **THEN** 不変条件B が「作成・削除ともに Pilot 専任。Worker は使用のみ（ADR-008）」と記述されている
