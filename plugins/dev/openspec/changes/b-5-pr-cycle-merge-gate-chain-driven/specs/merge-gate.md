## ADDED Requirements

### Requirement: 動的レビュアー構築

merge-gate は PR diff のファイルリストから specialist を動的に構築しなければならない（SHALL）。旧 standard/plugin 2 パスの分岐は存在しない。

#### Scenario: deps.yaml 変更時の specialist 追加
- **WHEN** PR の変更ファイルに deps.yaml が含まれる
- **THEN** worker-structure と worker-principles が specialist リストに追加される

#### Scenario: コード変更時の specialist 追加
- **WHEN** PR の変更ファイルにソースコード（.ts, .py, .md 等）が含まれる
- **THEN** worker-code-reviewer と worker-security-reviewer が specialist リストに追加される

#### Scenario: conditional specialist 追加
- **WHEN** tech-stack-detect スクリプトが該当する tech-stack を検出する
- **THEN** 対応する conditional specialist（worker-nextjs-reviewer, worker-fastapi-reviewer 等）がリストに追加される

#### Scenario: specialist リストが空
- **WHEN** PR の変更ファイルがレビュー対象外（.gitignore 等のみ）
- **THEN** specialist リストは空となり merge-gate は自動 PASS する

### Requirement: merge-gate 単一パス統合

merge-gate は動的レビュアーリストに基づく単一パスで実行しなければならない（MUST）。standard/plugin の分岐コードは存在してはならない。

#### Scenario: 単一パスでの merge-gate 実行
- **WHEN** merge-gate が起動される
- **THEN** 動的レビュアー構築 → 並列 specialist 実行 → 結果集約 → PASS/REJECT 判定の単一フローで処理される
- **AND** 「standard」「plugin」等のパス識別子や分岐条件が存在しない

### Requirement: merge-gate severity フィルタ

merge-gate は `severity == CRITICAL && confidence >= 80` の機械的フィルタで PASS/REJECT を判定しなければならない（SHALL）。AI 推論による判定は禁止する。

#### Scenario: PASS 判定
- **WHEN** 全 specialist の findings に severity=CRITICAL かつ confidence>=80 のエントリがない
- **THEN** merge-gate は PASS を返す
- **AND** issue-{N}.json の status が `merge-ready` から `done` に遷移する

#### Scenario: REJECT 判定（1回目）
- **WHEN** findings に severity=CRITICAL かつ confidence>=80 のエントリが存在する
- **AND** issue-{N}.json の retry_count が 0
- **THEN** merge-gate は REJECT を返す
- **AND** status が failed → running に遷移し fix_instructions に CRITICAL findings が記録される（SHALL）

#### Scenario: REJECT 判定（2回目、確定失敗）
- **WHEN** fix-phase 後の再レビューで再度 CRITICAL findings が存在する
- **AND** retry_count が 1 以上（不変条件 E: リトライ最大1回）
- **THEN** status が failed に確定する（MUST）
- **AND** Pilot に手動介入が要求される

### Requirement: tech-stack-detect スクリプト

変更ファイルのパス・拡張子から tech-stack を判定し、該当する conditional specialist を返す script 型コンポーネントを実装しなければならない（SHALL）。

#### Scenario: Next.js プロジェクトの TSX 変更検出
- **WHEN** 変更ファイルに `.tsx` ファイルが含まれ、next.config.* が存在する
- **THEN** worker-nextjs-reviewer が specialist リストに追加される

#### Scenario: 該当 tech-stack なし
- **WHEN** 変更ファイルがいずれの tech-stack 判定ルールにも該当しない
- **THEN** conditional specialist は追加されない（空リスト）

## REMOVED Requirements

### Requirement: standard/plugin 2パス分岐

merge-gate の standard パスと plugin パスの分岐ロジックを廃止する（SHALL）。全てのレビューは動的レビュアー構築による単一パスで処理する。

#### Scenario: 旧パス分岐コードの不在
- **WHEN** merge-gate の実装を検査する
- **THEN** GATE_TYPE, standard_gate, plugin_gate 等のパス識別変数が存在しない
