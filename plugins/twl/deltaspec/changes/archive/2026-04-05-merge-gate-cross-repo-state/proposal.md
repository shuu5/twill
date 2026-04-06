## Why

`autopilot-orchestrator.sh` の merge-gate ループ（L858-888）と `run_merge_gate()` 関数（L640）が `state-read.sh` を呼び出す際に `--repo` オプションを渡していない。そのため、クロスリポジトリ Issue では state ファイルを正しく参照できず、merge-gate が常に失敗する。

## What Changes

- `run_merge_gate()` のシグネチャを `issue` → `entry`（`repo_id:issue_num` 形式）に変更
- `run_merge_gate()` 内部の全 `state-read.sh` 呼び出しに `_state_read_repo_args` を適用
- merge-gate ループの `state-read.sh` 呼び出し（L866/871/879/882）に `_state_read_repo_args` を適用
- ループ内の `run_merge_gate` 呼び出しを `run_merge_gate "$_entry"` に変更

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `run_merge_gate()`: クロスリポジトリ Issue の state を正しく参照できる
- merge-gate ループ: クロスリポジトリ Issue の status を正しく読み取れる

## Impact

- **変更ファイル**: `scripts/autopilot-orchestrator.sh`
- **影響範囲**: merge-gate フロー（`run_merge_gate` 関数とループ）
- **依存**: `_state_read_repo_args` パターン（poll_phase で実装済み）
- **後方互換**: `_default` repo_id を持つ通常 Issue には影響なし（`_state_read_repo_args` が空配列になる）
