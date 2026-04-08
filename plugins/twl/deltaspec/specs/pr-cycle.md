# PR Cycle

PR のレビュー・テスト・修正・マージの一連のサイクルを定義するシナリオ。workflow-pr-verify → workflow-pr-fix → workflow-pr-merge の 3 workflow で構成される chain-driven ワークフロー。merge-gate の判定仕組みは merge-gate.md を参照。

## Scenario: PR 検証 chain の正常実行（workflow-pr-verify）

- **WHEN** workflow-pr-verify が実行される
- **THEN** ts-preflight（TypeScript 機械的検証）が chain-runner.sh 経由で実行される
- **AND** TypeScript プロジェクトでない場合は ts-preflight が自動スキップされる
- **AND** phase-review（並列 specialist レビュー）が実行される
- **AND** scope-judge（スコープ判定）が実行される
- **AND** pr-test（テスト実行）が chain-runner.sh 経由で実行される
- **AND** ac-verify（AC↔diff 整合性チェック）が実行され checkpoint が永続化される

## Scenario: AC 検証の前提条件

- **WHEN** ac-verify ステップが実行される
- **AND** workflow-setup の ac-extract で生成された `${SNAPSHOT_DIR}/01.5-ac-checklist.md` が存在する
- **THEN** AC checklist と PR diff・pr-test checkpoint を照合し結果を永続化する
- **WHEN** ac-checklist.md が存在しない
- **THEN** WARN で ac-verify を抜ける

## Scenario: PR 修正 chain の正常実行（workflow-pr-fix）

- **WHEN** workflow-pr-fix が実行される
- **AND** phase-review に CRITICAL findings（confidence >= 80）が存在する
- **THEN** fix-phase（自動修正ループ）が実行される
- **AND** post-fix-verify（fix 後検証）が実行される
- **AND** pr-test が再実行される
- **AND** テスト PASS → warning-fix へ進む
- **AND** テスト FAIL → fix-phase に戻る（最大 1 ループ）

## Scenario: CRITICAL findings がない場合の fix スキップ

- **WHEN** workflow-pr-fix が実行される
- **AND** phase-review に CRITICAL findings が存在しない
- **THEN** fix-phase と post-fix-verify はスキップされる
- **AND** warning-fix（Warning のベストエフォート修正）のみ実行される

## Scenario: PR マージ chain の正常実行（workflow-pr-merge）

- **WHEN** workflow-pr-merge が実行される
- **THEN** e2e-screening（Visual 検証）が実行される（E2E なければスキップ）
- **AND** pr-cycle-report で各ステップの結果が Markdown レポートとして構築される
- **AND** pr-cycle-analysis でパターン分析が実行される
- **AND** all-pass-check で全ステップの結果が判定される
- **AND** 全 PASS の場合、merge-gate が実行される
- **AND** merge-gate PASS の場合、auto-merge で squash merge が実行される

## Scenario: all-pass-check 失敗

- **WHEN** all-pass-check で FAIL ステップが検出される
- **THEN** merge-gate は REJECT として処理される
- **AND** ドメインルールの merge-gate エスカレーション条件に従う

## Scenario: merge-gate エスカレーション（1回目リトライ）

- **WHEN** merge-gate が REJECT を返す
- **AND** issue-{N}.json の retry_count=0
- **THEN** issue-{N}.json の status が failed → running に遷移する
- **AND** fix_instructions に CRITICAL findings が記録される
- **AND** fix-phase → pr-test → post-fix-verify → merge-gate を再実行する
- **AND** retry_count が 1 に更新される

## Scenario: merge-gate エスカレーション（確定失敗）

- **WHEN** merge-gate が再度 REJECT を返す
- **AND** issue-{N}.json の retry_count >= 1
- **THEN** issue-{N}.json の status が failed に確定する（不変条件 E）
- **AND** Pilot に手動介入が要求される
- **AND** ワークフローが停止する

## Scenario: auto-merge 後の後処理

- **WHEN** auto-merge が成功する
- **THEN** DeltaSpec archive が自動実行される（deltaspec archive --yes --skip-specs）
- **AND** tmux window → worktree → remote branch が順次削除される

## Scenario: autopilot 連携時の自動遷移

- **WHEN** IS_AUTOPILOT=true で各 workflow が完了する
- **THEN** workflow-pr-verify 完了後、即座に workflow-pr-fix が自動遷移する
- **AND** workflow-pr-fix 完了後、即座に workflow-pr-merge が自動遷移する
- **AND** プロンプトでの停止は禁止される

## Scenario: 手動実行時の遷移案内

- **WHEN** IS_AUTOPILOT=false で各 workflow が完了する
- **THEN** 次のステップの Skill コマンドが案内される
- **AND** ユーザーが手動で次の workflow を実行する

## Scenario: 動的レビュアー構築

- **WHEN** phase-review が実行される
- **THEN** PR の変更ファイルから動的にレビュアーリストが構築される
- **AND** deps.yaml 変更時は worker-structure と worker-principles が追加される
- **AND** コード変更時は worker-code-reviewer と worker-security-reviewer が追加される
- **AND** Tech-stack 検出により conditional specialist が追加される（例: .tsx → worker-nextjs-reviewer）
- **AND** 全 specialist は並列 Task spawn で実行される

## Scenario: specialist 出力の標準化

- **WHEN** specialist がレビュー結果を返す
- **THEN** 共通出力スキーマ（status, findings[]）に準拠する
- **AND** findings は severity（CRITICAL/WARNING/INFO）、confidence（0-100）、file、line、message、category を含む
- **AND** パース失敗時は出力全文が WARNING finding（confidence=50）として扱われる

## Scenario: compaction 復帰

- **WHEN** workflow 実行中に context window compaction が発生する
- **THEN** ref-compaction-recovery.md に従い chain-runner.sh の checkpoint から現在のステップを特定する
- **AND** LLM ステップ（phase-review, scope-judge, ac-verify 等）は状態を確認してから再実行する
- **AND** 機械的ステップ（ts-preflight, pr-test 等）は chain-runner.sh 経由で再実行する
