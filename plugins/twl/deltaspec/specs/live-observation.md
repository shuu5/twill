# Live Observation

co-self-improve と workflow-observe-loop による能動的ライブセッション観察を定義するシナリオ。受動的 self-improvement（autopilot 後処理）は self-improve.md を参照。

## Scenario: モード判定

- **WHEN** co-self-improve が実行される
- **THEN** 引数またはユーザー入力から observe / scenario-run / retrospect / test-project-manage のモードが判定される
- **AND** 引数なしまたは曖昧な場合は AskUserQuestion で 4 モードから選択される

## Scenario: observe モード（ライブセッション観察）

- **WHEN** observe モードが選択される
- **THEN** `tmux list-windows` で観察可能 window 一覧が取得され、自 window が除外される
- **AND** 複数候補がある場合は AskUserQuestion で選択される
- **AND** workflow-observe-loop に対象 window が渡されて observation loop が起動される

## Scenario: scenario-run モード（テストプロジェクト壁打ち）

- **WHEN** scenario-run モードが選択される
- **THEN** test-target worktree が無ければ作成される
- **AND** シナリオ一覧が表示されユーザーが選択する
- **AND** シナリオの Issue 群が test-target にロードされる
- **AND** `session:spawn` で observed session が `worktrees/test-target` で起動される
- **AND** spawn 後の window 名が取得され observation loop が起動される

## Scenario: observation loop のサイクル実行

- **WHEN** workflow-observe-loop が起動される
- **THEN** bash ループで INTERVAL 秒間隔（デフォルト 30 秒）のポーリングが開始される
- **AND** 各サイクルで observe-wrapper.sh で capture を取得し、パターンマッチで問題検出する
- **AND** 検出パターンは Error/APIError/MergeGateError/CRITICAL/silent deletion/AC 矮小化等
- **AND** 検出結果は JSONL ファイルに追記される
- **AND** MAX_CYCLES（デフォルト 60、合計 30 分）到達で終了する

## Scenario: observation loop の終了条件

- **WHEN** observation loop が実行中
- **THEN** observed session が終了した場合、ループを終了する
- **AND** ユーザーが Ctrl-C で停止した場合、ループを終了する
- **AND** STOP_ON_DETECT=true の場合、1 件検出で停止する
- **AND** MAX_CYCLES に到達した場合、ループを終了する

## Scenario: observation loop の集約

- **WHEN** observation loop が終了する
- **THEN** 全サイクルの detections が統合される
- **AND** 同一パターンの重複が除去される
- **AND** severity 別に集計され top 10 検出が抽出される
- **AND** observe-retrospective で過去 observation とのパターン照合が実行される

## Scenario: retrospect モード（過去の振り返り）

- **WHEN** retrospect モードが選択される
- **THEN** doobidoo memory から過去の observation 結果が検索される
- **AND** observe-retrospective で集約分析が実行される
- **AND** Issue draft 生成の有無がユーザーに確認される

## Scenario: Issue 起票確認フロー

- **WHEN** observation で問題が検出される（observe / retrospect 経由）
- **THEN** 検出結果が全件提示される（severity / category / source / capture excerpt）
- **AND** AskUserQuestion で Issue draft 生成の可否が確認される（全件 / 一部 / なし）
- **AND** 承認時のみ Issue draft が生成されユーザーに最終確認される
- **AND** 最終承認時のみ `gh issue create` で起票される（label: from-observation, ctx/observation）

## Scenario: test-project-manage モード

- **WHEN** test-project-manage モードが選択される
- **THEN** init / reset / scenario-load / status のいずれかが実行される
- **AND** テストプロジェクト worktree から実 main branch にコミットすることは禁止

## Scenario: read-only 観察の厳守

- **WHEN** observed session が観察される
- **THEN** observed session に inject / send-keys してはならない
- **AND** 検出結果をユーザー確認なしで自動 Issue 起票してはならない
- **AND** 同時に 4 個以上の observed session を観察してはならない

## Scenario: context budget 維持

- **WHEN** observation loop が実行中
- **THEN** 各サイクルの生 capture は context に retain されない（集約 JSON のみ保持）
- **AND** capture tmp ファイルは各サイクル終了時に削除される
