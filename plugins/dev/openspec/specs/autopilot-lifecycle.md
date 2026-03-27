# Autopilot Lifecycle

co-autopilot のライフサイクル全体を定義するシナリオ。

## Scenario: 単一 Issue の autopilot 実行

- **WHEN** ユーザーが `co-autopilot #42` を実行する
- **THEN** plan.yaml に Phase 1（issues: [42]）が生成される
- **AND** Worker が worktree `worktrees/feat/42-xxx/` を作成する
- **AND** Worker が chain ステップを逐次実行する
- **AND** Worker が issue-42.json の status を `merge-ready` に更新する
- **AND** Pilot が merge-gate を実行する
- **AND** merge-gate PASS で squash merge が実行される
- **AND** Pilot が worktree を削除し autopilot-summary を出力する

## Scenario: 複数 Phase の逐次実行

- **WHEN** 依存関係 #10→#11→#12 を持つ 3 Issue で co-autopilot を実行する
- **THEN** plan.yaml に 3 Phase が生成される（Phase 1: [#10], Phase 2: [#11], Phase 3: [#12]）
- **AND** Phase 1 が完了してから Phase 2 が開始される
- **AND** Phase 2 が完了してから Phase 3 が開始される

## Scenario: Phase 内並列実行

- **WHEN** 互いに依存しない #10 と #11 が同一 Phase に含まれる
- **THEN** #10 と #11 の Worker が並列に起動される
- **AND** 両方の Worker が merge-ready になるまで Phase は完了しない

## Scenario: Phase 内 Issue 失敗時の skip 伝播

- **WHEN** Phase 1 の Issue #10 が failed になる
- **AND** Phase 2 の Issue #11 が #10 に依存している
- **THEN** Issue #11 は自動 skip される（不変条件 D）
- **AND** skip は連鎖的に伝播し、#11 に依存する Phase 3 以降の全 Issue も再帰的に skip される
- **AND** issue-11.json の status が `failed` に遷移し failure.message に skip 理由が記録される

## Scenario: session.json 初期化

- **WHEN** co-autopilot セッションが開始される
- **THEN** session.json が作成され session_id, plan_path, current_phase=1 が設定される
- **AND** 既存の session.json がある場合はエラー終了する（同時実行禁止）

## Scenario: Worker crash 検知

- **WHEN** Worker の tmux pane が予期せず終了する
- **THEN** Pilot の poll ループが pane 死亡を検知する（不変条件 G）
- **AND** issue-{N}.json の status が `failed` に遷移する
- **AND** failure に { message, step, timestamp } が記録される

## Scenario: retry 制限

- **WHEN** merge-gate が REJECT を返し retry_count=0 の場合
- **THEN** issue-{N}.json の status が failed → running に遷移する
- **AND** fix_instructions に findings が記録され Worker が fix-phase を実行する
- **WHEN** 再度 merge-gate が REJECT を返し retry_count=1 の場合
- **THEN** issue-{N}.json の status が failed に確定する（不変条件 E）
- **AND** Pilot に手動介入が要求される

## Scenario: Phase 完了時の後処理

- **WHEN** Phase 内の全 Issue が done または failed になる
- **THEN** autopilot-collect で変更ファイルを収集する
- **AND** autopilot-retrospective で Phase 振り返りを実行する
- **AND** autopilot-patterns でパターン検出を実行する
- **AND** 最終 Phase でなければ autopilot-cross-issue で影響分析を実行する

## Scenario: Emergency Bypass

- **WHEN** co-autopilot 自体の SKILL.md にバグがあり起動に失敗する
- **THEN** Emergency Bypass で main/ から直接実装→PR→merge が許可される
- **AND** セッション後に retrospective で理由を記録する義務がある

## Scenario: self-improve 統合

- **WHEN** autopilot-patterns が自リポジトリの Issue で繰り返しパターンを検出する
- **THEN** ECC 照合を自動追加し self-improve Issue を起票する
- **AND** session.json の self_improve_issues に Issue 番号が記録される
