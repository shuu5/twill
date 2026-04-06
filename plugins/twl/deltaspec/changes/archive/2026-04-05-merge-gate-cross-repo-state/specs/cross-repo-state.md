## MODIFIED Requirements

### Requirement: run_merge_gate クロスリポジトリ対応

`run_merge_gate()` は `entry`（`repo_id:issue_num` 形式）を受け取り、`_state_read_repo_args` を用いて全 `state-read.sh` 呼び出しに `--repo` を渡さなければならない（SHALL）。

#### Scenario: クロスリポジトリ Issue の merge-gate 実行

- **WHEN** `entry` が `my-repo:123` の形式で `run_merge_gate` が呼ばれる
- **THEN** `state-read.sh` の呼び出しに `--repo my-repo` が付与され、正しい state ファイルを参照する

#### Scenario: デフォルトリポジトリ Issue の merge-gate 実行（後方互換）

- **WHEN** `entry` が `_default:123` の形式で `run_merge_gate` が呼ばれる
- **THEN** `_state_read_repo_args` は空配列となり、既存動作と同じ state ファイルを参照する

### Requirement: merge-gate ループのクロスリポジトリ state 読み取り

merge-gate ループ（L865-888）の `state-read.sh` 呼び出しは `_state_read_repo_args` を使用しなければならない（SHALL）。

#### Scenario: クロスリポジトリ Issue の status 読み取り

- **WHEN** `_batch_issue_to_entry[$issue]` が `my-repo:123` を返す
- **THEN** status/retry_count/failure.reason の読み取りに `--repo my-repo` が渡される

#### Scenario: run_merge_gate へ entry を渡す

- **WHEN** merge-gate ループが `run_merge_gate` を呼ぶ
- **THEN** `"$_entry"`（`repo_id:issue_num` 形式）を引数として渡す
