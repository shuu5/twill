## Requirements

### Requirement: Phase 2 (CO_ISSUE_V2=1) で依存 DAG を構築する

CO_ISSUE_V2=1 の場合、Phase 2 は draft 本文内の `#<local-ref>` 記法（regex: `(?<![A-Za-z0-9/])#(\d{1,3})(?![0-9])`）を検出して edge を抽出し、Kahn's algorithm で topological sort して level 分割しなければならない（SHALL）。コードブロック内は除外する。循環 edge を検出した場合はエラーメッセージを出力して停止しなければならない（SHALL）。

#### Scenario: 依存のある draft が level 分割される

- **WHEN** draft #2 が本文内に `#1` を含む場合（draft #2 が draft #1 に依存）
- **THEN** L0=[draft #1], L1=[draft #2] として level 分割され、policies.json の parent_refs_resolved に L0 の URL が注入される

#### Scenario: 循環依存があればエラー停止する

- **WHEN** draft #1 が `#2` を含み、draft #2 が `#1` を含む（循環）
- **THEN** "circular dependency" エラーが出力され、Phase 2 は処理を停止する

### Requirement: per-issue input bundle を書き出す

CO_ISSUE_V2=1 の場合、Phase 2 は各 draft に対して per-issue ディレクトリ（`.controller-issue/<sid>/per-issue/<index>/IN/`）を作成し、`draft.md`, `arch-context.md`, `policies.json`, `deps.json` を書き出さなければならない（SHALL）。

#### Scenario: per-issue bundle が作成される

- **WHEN** Phase 2 が 2 件の draft を処理する
- **THEN** `.controller-issue/<sid>/per-issue/1/IN/` と `per-issue/2/IN/` の両ディレクトリが作成され、各ファイルが存在する

### Requirement: policies.json を 3 パターンで生成する

policies.json は quick / scope-direct / 通常 の 3 パターンから適切なものを書き出さなければならない（SHALL）。quick の場合 `max_rounds=1, quick_flag=true`、scope-direct の場合 `max_rounds=1, scope_direct_flag=true`、通常は `max_rounds=3, depth="normal"` とする。

#### Scenario: 通常パターンの policies.json が生成される

- **WHEN** quick / scope-direct フラグが共に false の draft を処理する
- **THEN** `policies.json` に `max_rounds=3`, `specialists=["worker-codex-reviewer","issue-critic","issue-feasibility"]`, `depth="normal"` が書き込まれる

### Requirement: Phase 2 完了後に AskUserQuestion で確認する

CO_ISSUE_V2=1 の場合、Phase 2 は bundle 書き出し後に `[dispatch | adjust | cancel]` の選択肢で AskUserQuestion しなければならない（SHALL）。

#### Scenario: dispatch 選択で Phase 3 に進む

- **WHEN** ユーザーが `dispatch` を選択する
- **THEN** Phase 3 (Level-based Dispatch) が開始される
