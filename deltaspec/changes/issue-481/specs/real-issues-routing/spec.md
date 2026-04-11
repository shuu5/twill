## MODIFIED Requirements

### Requirement: scenario-run モードの --real-issues フラグ受け入れ

co-self-improve の scenario-run モードは `--real-issues --repo <owner>/<name>` フラグを受け取り、適切なモードで test-project-init と test-project-scenario-load を呼び出さなければならない（SHALL）。

#### Scenario: real-issues モードでの end-to-end 実行
- **WHEN** ユーザーが `/twl:co-self-improve scenario-run smoke-001 --real-issues --repo shuu5/test-repo` を実行する
- **THEN** `test-project-init.md` が `--mode real-issues --repo shuu5/test-repo` で呼び出される
- **THEN** `test-project-scenario-load.md` が `--scenario smoke-001 --real-issues` で呼び出される
- **THEN** `session:spawn` が `--cd worktrees/test-target` と co-autopilot 起動 prompt で実行される

#### Scenario: local モードのデフォルト動作維持
- **WHEN** ユーザーが `--real-issues` フラグなしで scenario-run を実行する
- **THEN** `test-project-init.md` がフラグなし（local モード）で呼び出される
- **THEN** 既存の動作が変わらない（SHALL）

## ADDED Requirements

### Requirement: ambiguous 入力時の明示的モード選択

co-self-improve は引数から `--real-issues` / local モードが判断できない場合、ユーザーに AskUserQuestion でモードを選択させなければならない（MUST）。

#### Scenario: --repo なしで --real-issues が指定された場合
- **WHEN** `--real-issues` フラグはあるが `--repo` が省略されている
- **THEN** AskUserQuestion で「専用テストリポのオーナー/リポ名を入力してください（例: shuu5/twill-test）」と質問する

#### Scenario: フラグなしで ambiguous な場合
- **WHEN** scenario 名のみで local / real-issues が不明な場合
- **THEN** AskUserQuestion で「ローカルモードと real-issues モードのどちらで実行しますか？」と選択させる

### Requirement: co-autopilot の test-target worktree 起動

session:spawn は co-autopilot を test-target worktree で起動する経路を明文化しなければならない（SHALL）。

#### Scenario: co-autopilot が test-target で起動される
- **WHEN** Step 1 Step 5 で session:spawn が呼ばれる
- **THEN** `--cd worktrees/test-target` が指定され co-autopilot が test-target 内で起動する
- **THEN** spawn 後の window 名が Step 2 に渡される
