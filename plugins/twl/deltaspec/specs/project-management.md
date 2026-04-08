# Project Management

co-project の migrate / snapshot / plugin モードを定義するシナリオ。create モードは project-create.md を参照。

## Scenario: モード判定

- **WHEN** co-project が引数またはユーザー入力で呼び出される
- **THEN** キーワードから create / migrate / snapshot / plugin-create / plugin-diagnose のモードが判定される
- **AND** 判定不能時は AskUserQuestion で選択を求める

## Scenario: migrate モード正常実行

- **WHEN** co-project migrate が実行される
- **AND** CWD が `~/projects/` 配下にある
- **THEN** bare repo / worktree 構造が検出される
- **AND** `/twl:project-migrate` でテンプレート移行が実行される
- **AND** `/twl:project-governance --update` でガバナンスが再適用される
- **AND** コミット提案（`chore: migrate to latest template`）が行われる

## Scenario: migrate dry-run

- **WHEN** `co-project migrate --dry-run` が実行される
- **THEN** 変更内容が表示されるのみで実際の変更は行われない

## Scenario: snapshot モード正常実行

- **WHEN** co-project snapshot が実行される
- **THEN** ソースプロジェクトパスとテンプレート名が確認される（未指定時は AskUserQuestion）
- **AND** テンプレート名衝突時は上書き確認される
- **AND** `/twl:snapshot-analyze` でスタック情報・コンテナ依存・ファイル一覧が出力される
- **AND** `/twl:snapshot-classify` で AI Tier 分類 → ユーザー確認が行われる
- **AND** `/twl:snapshot-generate` で manifest.yaml + テンプレートファイルが生成される
- **AND** テンプレートパスと Tier 別ファイル数が報告される

## Scenario: snapshot のソースプロジェクト保護

- **WHEN** snapshot モードが実行される
- **THEN** ソースプロジェクトは read-only で扱われ変更されない

## Scenario: plugin-create モード委譲

- **WHEN** co-project が plugin-create モードで実行される
- **THEN** `/twl:workflow-plugin-create` に委譲される（interview → research → design → generate）

## Scenario: plugin-diagnose モード委譲

- **WHEN** co-project が plugin-diagnose モードで実行される
- **THEN** `/twl:workflow-plugin-diagnose` に委譲される（migrate-analyze → diagnose → fix → verify）

## Scenario: Project Board クロスリポクエリ

- **WHEN** Project Board の Issue リストを取得する
- **THEN** `gh project item-list` を使用する（`gh issue list` は単一リポ専用のため不可）
- **AND** `--limit 200` を明示指定する（デフォルト件数は不足するため）

## Scenario: ガバナンス適用の必須性

- **WHEN** create または migrate モードが完了する
- **THEN** ガバナンス適用（project-governance）は必ず実行される
- **AND** ガバナンス適用のスキップは禁止
