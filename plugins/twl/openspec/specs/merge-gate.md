# merge-gate

merge-gate ワークフロー（動的レビュアー構築→並列 specialist→結果集約→判定）を定義するシナリオ。

## Scenario: 動的レビュアー構築（deps.yaml + コード変更）

- **WHEN** PR の変更ファイルに deps.yaml と TypeScript ファイルが含まれる
- **THEN** worker-structure と worker-principles が specialist リストに追加される（deps.yaml 変更）
- **AND** worker-code-reviewer と worker-security-reviewer が specialist リストに追加される（コード変更）

## Scenario: 動的レビュアー構築（conditional specialist）

- **WHEN** PR の変更ファイルに `.tsx` ファイルが含まれ Next.js プロジェクトである
- **THEN** worker-nextjs-reviewer が conditional specialist として追加される
- **AND** tech-stack 検出スクリプトが拡張子・パスから判定を行う

## Scenario: 並列 specialist 実行

- **WHEN** specialist リストが決定される
- **THEN** 全 specialist が Task spawn で並列実行される
- **AND** 各 specialist は共通出力スキーマ（status, findings[]）で結果を返す

## Scenario: merge-gate PASS

- **WHEN** 全 specialist の findings に severity=CRITICAL かつ confidence>=80 のエントリがない
- **THEN** merge-gate は PASS を返す
- **AND** Pilot が squash merge を実行する
- **AND** issue-{N}.json の status が `done` に遷移し merged_at にタイムスタンプが記録される

## Scenario: merge-gate REJECT（1回目）

- **WHEN** specialist findings に severity=CRITICAL かつ confidence>=80 のエントリが 1 件以上存在する
- **AND** issue-{N}.json の retry_count=0
- **THEN** merge-gate は REJECT を返す
- **AND** issue-{N}.json の status が failed → running に遷移する
- **AND** fix_instructions に CRITICAL findings が記録される
- **AND** Worker が fix-phase を実行する

## Scenario: merge-gate REJECT（2回目、確定失敗 — リトライ最大1回制限）

- **WHEN** fix-phase 後の再レビューで再度 CRITICAL findings が存在する
- **AND** issue-{N}.json の retry_count=1（最大1回のリトライ上限に到達）
- **THEN** issue-{N}.json の status が failed に確定する（不変条件 E）
- **AND** Pilot に手動介入が要求される

## Scenario: specialist 出力パース失敗

- **WHEN** specialist の出力が共通スキーマに準拠しない
- **THEN** 出力全文が 1 つの WARNING finding（confidence=50）として扱われる
- **AND** 手動レビューが要求される
- **AND** merge-gate のブロック閾値（confidence>=80）には達しないため自動 REJECT にはならない

## Scenario: フォローアップ Issue の project board 自動登録

- **WHEN** merge-gate-issues.sh が tech-debt または self-improve Issue を起票する
- **THEN** 起票された Issue は対象リポジトリにリンクされた Project V2 に自動追加される
- **AND** Project 未リンク時はサイレントスキップする（ワークフロー停止しない）
- **AND** board 登録失敗時は Warning を出力して処理を継続する

## Scenario: standard/plugin パス統一

- **WHEN** merge-gate が起動される
- **THEN** 変更ファイルから動的にレビュアーリストが構築される
- **AND** 旧 standard/plugin 2パスの分岐は存在しない（単一パス）
