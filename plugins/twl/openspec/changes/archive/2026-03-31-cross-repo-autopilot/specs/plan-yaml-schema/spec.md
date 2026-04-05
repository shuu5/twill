## ADDED Requirements

### Requirement: plan.yaml repos セクション

plan.yaml に repos セクションを追加し、クロスリポジトリプロジェクトで各リポジトリの識別子・owner・name・path を宣言できなければならない（SHALL）。

#### Scenario: クロスリポジトリ plan.yaml 生成
- **WHEN** `autopilot-plan.sh --issues "lpd#42,loom#50"` が実行される
- **THEN** 生成された plan.yaml に repos セクションが含まれ、各 repo_id に owner, name, path が設定される

#### Scenario: 後方互換 — repos セクション省略
- **WHEN** `autopilot-plan.sh --issues "42,43"` が repos 指定なしで実行される
- **THEN** repos セクションは省略され、issues は bare integer のまま従来形式で生成されなければならない（MUST）

### Requirement: Issue のリポジトリ識別子付与

plan.yaml の phases 内の各 Issue に repo フィールドを付与し、どのリポジトリの Issue かを識別できなければならない（SHALL）。

#### Scenario: Issue ごとの repo 識別
- **WHEN** plan.yaml に `{ number: 42, repo: lpd }` と `{ number: 50, repo: loom }` が含まれる
- **THEN** 各 Issue は repos セクションの対応する repo_id で解決される

### Requirement: Issue 参照形式の解決

autopilot-plan.sh は以下の 3 形式を受け付け、内部の repo_id#N 形式に正規化しなければならない（SHALL）。
- `42` → `_default#42`
- `lpd#42` → repo_id 直接参照
- `shuu5/loom-plugin-dev#42` → repos セクションから逆引き

#### Scenario: bare integer の後方互換解決
- **WHEN** `--issues "42"` が repos セクション省略の plan で渡される
- **THEN** カレントリポジトリの Issue #42 として解決される

#### Scenario: owner/repo#N 形式の解決
- **WHEN** `--issues "shuu5/loom#50"` が渡される
- **THEN** repos セクションから `owner=shuu5, name=loom` に一致する repo_id を逆引きし、`loom#50` として解決されなければならない（MUST）

## MODIFIED Requirements

### Requirement: 依存関係の repo_id 修飾

dependencies セクションのキーと値を `repo_id#N` 形式に拡張しなければならない（SHALL）。後方互換として bare integer も許可する。

#### Scenario: クロスリポジトリ依存関係
- **WHEN** `dependencies: { "lpd#42": ["loom#50"] }` が定義される
- **THEN** lpd#42 は loom#50 が完了するまで実行されない
