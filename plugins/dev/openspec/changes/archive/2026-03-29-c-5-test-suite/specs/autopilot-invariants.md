## ADDED Requirements

### Requirement: 不変条件 A - 状態一意性テスト

各 issue の状態ファイルが常に単一の一貫した状態を保つことをテストしなければならない（SHALL）。

#### Scenario: 並列書き込みでの整合性
- **WHEN** 同一 issue に対して 2 つの state-write プロセスを同時実行する
- **THEN** 最終状態が有効な JSON であり、status が有効な値を持つ

### Requirement: 不変条件 B - Worktree 削除 pilot 専任テスト

worktree-delete.sh が pilot ロール以外の実行を拒否することをテストしなければならない（SHALL）。

#### Scenario: worker ロールでの削除拒否
- **WHEN** `ROLE=worker` で worktree-delete.sh を実行する
- **THEN** 終了コード 1 で「pilot 専任」エラーメッセージが出力される

#### Scenario: pilot ロールでの削除許可
- **WHEN** `ROLE=pilot` で worktree-delete.sh を実行する（git を stub）
- **THEN** 終了コード 0 で正常完了する

### Requirement: 不変条件 C - Worker マージ禁止テスト

merge-gate-execute.sh が worker ロールの実行を拒否することをテストしなければならない（MUST）。

#### Scenario: worker ロールでのマージ拒否
- **WHEN** `ROLE=worker` で merge-gate-execute.sh を実行する
- **THEN** 終了コード 1 でマージ禁止エラーが出力される

### Requirement: 不変条件 D - 依存先 fail skip 伝播テスト

依存先 issue が failed の場合、後続 issue が自動 skip されることをテストしなければならない（SHALL）。

#### Scenario: 単一依存先の fail 伝播
- **WHEN** issue-1 が failed で、issue-2 が issue-1 に依存する
- **THEN** autopilot-should-skip.sh が issue-2 に対して skip=true を返す

#### Scenario: 複数依存先で 1 つが fail
- **WHEN** issue-1 が done、issue-2 が failed で、issue-3 が両方に依存する
- **THEN** autopilot-should-skip.sh が issue-3 に対して skip=true を返す

### Requirement: 不変条件 E - merge-gate リトライ制限テスト

merge-gate のリトライが最大 1 回に制限されることをテストしなければならない（SHALL）。

#### Scenario: 初回リトライ許可
- **WHEN** retry_count=0 かつ status=failed の issue に対して status=running を設定する
- **THEN** 遷移が許可され retry_count=1 に更新される

#### Scenario: 2 回目リトライ拒否
- **WHEN** retry_count=1 かつ status=failed の issue に対して status=running を設定する
- **THEN** 遷移が拒否される

### Requirement: 不変条件 F - rebase 禁止テスト

merge-gate-execute.sh がマージ戦略として squash のみを使用することをテストしなければならない（MUST）。

#### Scenario: squash マージ戦略の確認
- **WHEN** merge-gate-execute.sh のソースコードを解析する
- **THEN** `gh pr merge` 呼び出しに `--squash` フラグが含まれ、`--rebase` が含まれない

### Requirement: 不変条件 G - クラッシュ検知保証テスト

crash-detect.sh が tmux ペイン不在を正しく検知し failed 遷移することをテストしなければならない（SHALL）。

#### Scenario: ペイン不在検知
- **WHEN** tmux を stub してペイン不在を返す状態で crash-detect.sh を実行する
- **THEN** 終了コード 2 で status=failed に遷移済みであること

### Requirement: 不変条件 H - deps.yaml 変更排他性テスト

deps.yaml の構造が排他的に管理されることをテストしなければならない（MUST）。

#### Scenario: deps.yaml の型ルール整合性
- **WHEN** deps.yaml を解析する
- **THEN** 全コンポーネントの type が controller/workflow/composite/atomic/specialist/reference/script のいずれかである

### Requirement: 不変条件 I - 循環依存拒否テスト

autopilot-plan.sh が循環依存を検出して拒否することをテストしなければならない（SHALL）。

#### Scenario: 直接循環依存の検出
- **WHEN** A→B→A の循環依存グラフで autopilot-plan.sh を実行する
- **THEN** 終了コード 1 で循環依存エラーメッセージが出力される

#### Scenario: 間接循環依存の検出
- **WHEN** A→B→C→A の循環依存グラフで autopilot-plan.sh を実行する
- **THEN** 終了コード 1 で循環依存エラーメッセージが出力される
