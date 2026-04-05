## ADDED Requirements

### Requirement: chain-runner.sh ステップディスパッチ

chain-runner.sh はステップ名を第 1 引数として受け取り、対応する処理を bash で実行しなければならない（SHALL）。未知のステップ名が渡された場合は exit 1 で終了しなければならない（MUST）。

#### Scenario: 既知ステップの実行
- **WHEN** `bash chain-runner.sh init` が実行される
- **THEN** init ステップの処理が実行され、結果が stdout に出力される

#### Scenario: 未知ステップの拒否
- **WHEN** `bash chain-runner.sh unknown-step` が実行される
- **THEN** exit code 1 で終了し、エラーメッセージが stderr に出力される

### Requirement: 構造化出力フォーマット

各ステップは完了時に `✓ <step-name>: <summary>` または `⚠️ <step-name>: <reason>` を stdout に出力しなければならない（MUST）。Worker はこの出力のみで結果を判断できなければならない（SHALL）。

#### Scenario: 成功時の出力
- **WHEN** board-status-update ステップが正常完了する
- **THEN** `✓ board-status-update: Project Board Status → In Progress (#119)` のような出力が stdout に出力される（target_status 指定時はそのステータス名）

#### Scenario: スキップ時の出力
- **WHEN** ts-preflight で tsconfig.json が存在しない
- **THEN** `⚠️ ts-preflight: TypeScript プロジェクトではない — スキップ` が出力される

### Requirement: init ステップ

init ステップはブランチ、openspec/、changes/、proposal.md の状態を判定し、recommended_action を JSON で返さなければならない（SHALL）。

#### Scenario: main ブランチでの実行
- **WHEN** 現在のブランチが main
- **THEN** `{"recommended_action": "worktree"}` が出力に含まれる

#### Scenario: feature ブランチで openspec あり・proposal なし
- **WHEN** feature ブランチで openspec/ が存在し、changes/ が空
- **THEN** `{"recommended_action": "propose"}` が出力に含まれる

### Requirement: board-status-update ステップ

ISSUE_NUM を第1引数で受け取り、target_status を第2引数（デフォルト: "In Progress"）で受け取り、Project Board の Status を指定ステータスに更新しなければならない（SHALL）。ISSUE_NUM が未設定の場合は何も出力せず正常終了しなければならない（MUST）。

#### Scenario: Issue 番号ありで正常更新（デフォルトステータス）
- **WHEN** `bash chain-runner.sh board-status-update 119` が実行される
- **THEN** Project Board の Status が "In Progress" に更新され、成功メッセージが出力される

#### Scenario: Issue 番号とステータス指定で正常更新
- **WHEN** `bash chain-runner.sh board-status-update 119 "Todo"` が実行される
- **THEN** Project Board の Status が "Todo" に更新され、`Project Board Status → Todo (#119)` メッセージが出力される

#### Scenario: Issue 番号なしでスキップ
- **WHEN** `bash chain-runner.sh board-status-update` が引数なしで実行される
- **THEN** 何も出力せず exit 0 で終了する

### Requirement: ac-extract ステップ

ブランチ名から Issue 番号を抽出し、parse-issue-ac.sh 経由で AC を取得し、snapshot ディレクトリに保存しなければならない（SHALL）。

#### Scenario: Issue 番号が抽出できる場合
- **WHEN** ブランチ名が `feat/119-chain-runner`
- **THEN** Issue #119 の AC が `${SNAPSHOT_DIR}/01.5-ac-checklist.md` に保存される

#### Scenario: Issue 番号が抽出できない場合
- **WHEN** ブランチ名に Issue 番号が含まれない
- **THEN** スキップメッセージが出力され正常終了する

### Requirement: arch-ref ステップ

Issue body とコメントから `<!-- arch-ref-start -->` タグを検索し、architecture/ パスを抽出しなければならない（SHALL）。`..` を含むパスは拒否しなければならない（MUST）。

#### Scenario: arch-ref タグあり
- **WHEN** Issue body に `<!-- arch-ref-start -->` タグがあり、`architecture/design.md` が含まれる
- **THEN** 該当パスのリストが stdout に出力される

#### Scenario: arch-ref タグなし
- **WHEN** Issue body にタグがない
- **THEN** `⚠️ arch-ref: タグなし — スキップ` が出力される

#### Scenario: パストラバーサル拒否
- **WHEN** タグ内に `../../etc/passwd` が含まれる
- **THEN** 該当パスは無視され、警告が出力される

### Requirement: change-id-resolve ステップ

openspec/changes/ から最新の change-id を自動検出しなければならない（SHALL）。

#### Scenario: 1 つの change がある場合
- **WHEN** openspec/changes/ に `chain-runner` のみ存在する
- **THEN** `chain-runner` が stdout に出力される

#### Scenario: 複数の changes がある場合
- **WHEN** openspec/changes/ に複数のディレクトリがある
- **THEN** 最新（mtime 順）の change-id が出力される

### Requirement: ts-preflight ステップ

tsconfig.json の存在を確認し、TypeScript プロジェクトであれば型チェック・lint・ビルドを実行しなければならない（SHALL）。

#### Scenario: TypeScript プロジェクトでの実行
- **WHEN** tsconfig.json が存在する
- **THEN** `npx tsc --noEmit` 等が実行され、結果が PASS/FAIL で出力される

#### Scenario: 非 TypeScript プロジェクト
- **WHEN** tsconfig.json が存在しない
- **THEN** スキップし PASS を返す

### Requirement: pr-test ステップ

テストランナーを自動検出し、テストスイートを実行しなければならない（SHALL）。

#### Scenario: テスト全パス
- **WHEN** 全テストが成功する
- **THEN** `✓ pr-test: PASS (N/N tests passed)` が出力される

#### Scenario: テスト失敗
- **WHEN** 1 件以上テストが失敗する
- **THEN** `⚠️ pr-test: FAIL (M/N tests failed)` と失敗テスト名が出力される

### Requirement: all-pass-check ステップ

PR-cycle の全ステップ結果を検証し、merge-ready への遷移可否を判定しなければならない（SHALL）。autopilot 配下判定を含めなければならない（MUST）。

#### Scenario: 全ステップ PASS
- **WHEN** 全ステップの status が PASS
- **THEN** issue-{N}.json の status が `merge-ready` に遷移する

#### Scenario: 1 件以上 FAIL
- **WHEN** いずれかのステップが FAIL
- **THEN** issue-{N}.json の status が `failed` に遷移する

### Requirement: pr-cycle-report ステップ（構造化集約部分）

各ステップの結果を Markdown テーブルに集約し、PR コメントとして投稿しなければならない（SHALL）。

#### Scenario: レポート投稿
- **WHEN** PR が存在し、各ステップの結果が利用可能
- **THEN** 構造化された Markdown レポートが PR コメントとして投稿される

### Requirement: worktree-create ステップ（runner 統合）

既存の worktree-create.sh をラップし、chain-runner.sh から呼び出し可能にしなければならない（SHALL）。

#### Scenario: worktree 作成
- **WHEN** `bash chain-runner.sh worktree-create '#119'` が実行される
- **THEN** worktree-create.sh が呼び出され、結果が構造化出力される

## MODIFIED Requirements

### Requirement: workflow SKILL.md の chain 実行指示

各 workflow SKILL.md の chain 実行指示セクションで、機械的ステップは `bash chain-runner.sh <step>` 呼び出しに置換しなければならない（SHALL）。LLM 判断ステップは従来通り command.md Read → 実行のままにしなければならない（MUST）。

#### Scenario: workflow-setup の機械的ステップ
- **WHEN** autopilot worker が workflow-setup chain を実行する
- **THEN** init, board-status-update, ac-extract, arch-ref, worktree-create は chain-runner.sh 経由で実行され、command.md は Read されない

#### Scenario: workflow-setup の LLM 判断ステップ
- **WHEN** autopilot worker が opsx-propose ステップに到達する
- **THEN** 従来通り command.md を Read → 実行する

#### Scenario: 手動実行パスの維持
- **WHEN** ユーザーが直接 `/dev:init` を実行する
- **THEN** 既存の command.md に基づき LLM が実行する（chain-runner.sh は使用しない）
