## ADDED Requirements

### Requirement: 状態ファイルのリポジトリ名前空間化

状態ファイルを `.autopilot/repos/{repo_id}/issues/issue-{N}.json` に格納し、リポジトリ間の Issue 番号衝突を回避しなければならない（SHALL）。

#### Scenario: 異なるリポジトリの同一 Issue 番号
- **WHEN** lpd#10 と loom#10 が同一 autopilot セッションで管理される
- **THEN** `.autopilot/repos/lpd/issues/issue-10.json` と `.autopilot/repos/loom/issues/issue-10.json` が個別に作成される

#### Scenario: 後方互換 — repos 未使用時のフォールバック
- **WHEN** repos セクションが省略された plan.yaml で autopilot が実行される
- **THEN** 従来の `.autopilot/issues/issue-{N}.json` パスが使用されなければならない（MUST）

## MODIFIED Requirements

### Requirement: state-read.sh のリポジトリ対応

state-read.sh は repo_id 引数を受け取り、対応する名前空間ディレクトリから状態ファイルを読み取らなければならない（SHALL）。

#### Scenario: repo_id 指定での読み取り
- **WHEN** `state-read.sh --repo lpd --issue 42 --key status` が実行される
- **THEN** `.autopilot/repos/lpd/issues/issue-42.json` の status フィールドを返す

#### Scenario: repo_id 省略での後方互換
- **WHEN** `state-read.sh --issue 42 --key status` が repo_id なしで実行される
- **THEN** 従来の `.autopilot/issues/issue-42.json` から読み取る

### Requirement: state-write.sh のリポジトリ対応

state-write.sh は repo_id 引数を受け取り、対応する名前空間ディレクトリに状態ファイルを書き込まなければならない（SHALL）。

#### Scenario: repo_id 指定での書き込み
- **WHEN** `state-write.sh --repo loom --issue 50 --role worker --set status=running` が実行される
- **THEN** `.autopilot/repos/loom/issues/issue-50.json` に書き込まれる

### Requirement: session.json のリポジトリ情報

session.json に repos フィールドと default_repo フィールドを追加しなければならない（SHALL）。

#### Scenario: session.json にリポジトリ情報が記録される
- **WHEN** クロスリポジトリ autopilot セッションが開始される
- **THEN** session.json に `repos` オブジェクト（各 repo_id の owner, name, path）と `default_repo` が記録される

### Requirement: autopilot-init.sh のディレクトリ作成

autopilot-init.sh は repos セクションがある場合、各 repo_id 用のサブディレクトリを作成しなければならない（SHALL）。

#### Scenario: クロスリポジトリ初期化
- **WHEN** plan.yaml に `repos: { lpd: ..., loom: ... }` が含まれる
- **THEN** `.autopilot/repos/lpd/issues/` と `.autopilot/repos/loom/issues/` が作成される
