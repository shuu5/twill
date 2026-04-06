## ADDED Requirements

### Requirement: chain generate サブコマンド

`twl chain generate <chain-name>` コマンドで、指定された chain の Template A/B/C を stdout に出力しなければならない（SHALL）。

deps.yaml version が 3.x 未満の場合はエラーメッセージを出力して終了しなければならない（MUST）。

指定された chain-name が deps.yaml の chains セクションに存在しない場合はエラーメッセージを出力して終了しなければならない（MUST）。

#### Scenario: 正常な chain generate 実行
- **WHEN** `twl chain generate dev-pr-cycle` を v3.0 deps.yaml のあるプラグインルートで実行する
- **THEN** dev-pr-cycle chain の Template A/B/C が stdout に出力される

#### Scenario: 存在しない chain 名
- **WHEN** `twl chain generate nonexistent-chain` を実行する
- **THEN** エラーメッセージ "Chain 'nonexistent-chain' not found in deps.yaml" が表示され、終了コード 1 で終了する

#### Scenario: v2.0 deps.yaml
- **WHEN** v2.0 の deps.yaml に対して `twl chain generate` を実行する
- **THEN** エラーメッセージ "chain generate requires deps.yaml v3.0+" が表示され、終了コード 1 で終了する

### Requirement: Template A チェックポイント生成

Chain 参加者ごとに、chains.steps の position+1 から next コンポーネントを解決し、チェックポイント出力テンプレートを生成しなければならない（SHALL）。

最終 step のコンポーネントにはチェーン完了メッセージを生成しなければならない（MUST）。

出力形式:
```markdown
## チェックポイント（MUST）

`/dev:{next}` を Skill tool で自動実行。
```

#### Scenario: 中間 step のチェックポイント
- **WHEN** chain steps が `[workflow-setup, workflow-test-ready, apply, workflow-pr-cycle]` で workflow-setup のテンプレートを生成する
- **THEN** `/dev:workflow-test-ready` を参照するチェックポイントが生成される

#### Scenario: 最終 step のチェックポイント
- **WHEN** chain の最終 step（例: workflow-pr-cycle）のテンプレートを生成する
- **THEN** チェーン完了メッセージ「チェーン完了」が生成される

### Requirement: Template B called-by 宣言行生成

step_in を持つコンポーネントに対し、parent 名と step 番号から called-by 宣言行を生成しなければならない（SHALL）。

出力形式: `{parent} Step {step} から呼び出される。`

step_in に step フィールドがない場合は step 番号を省略しなければならない（MUST）。

#### Scenario: step_in を持つコンポーネント
- **WHEN** コンポーネントが `step_in: {parent: workflow-pr-cycle, step: "3.5"}` を持つ
- **THEN** `workflow-pr-cycle Step 3.5 から呼び出される。` が生成される

#### Scenario: step フィールドなしの step_in
- **WHEN** コンポーネントが `step_in: {parent: controller-autopilot}` を持つ（step なし）
- **THEN** `controller-autopilot から呼び出される。` が生成される

### Requirement: Template C ライフサイクル図テーブル生成

chain の全 step を、番号・型・コンポーネント名・説明のテーブルとして生成しなければならない（SHALL）。

各コンポーネントの description は deps.yaml の description フィールドから取得しなければならない（MUST）。

出力形式:
```markdown
| # | 型 | コンポーネント | 説明 |
|---|---|---|---|
| 1 | workflow | workflow-setup | 開発準備ワークフロー |
```

#### Scenario: 4 step の chain
- **WHEN** chain steps が `[workflow-setup, workflow-test-ready, apply, workflow-pr-cycle]` の場合
- **THEN** 4行のテーブルが番号 1〜4 で生成され、各行に型と説明が含まれる
