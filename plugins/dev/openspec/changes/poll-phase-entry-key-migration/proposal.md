## Why

`scripts/autopilot-orchestrator.sh` の `poll_phase()` 関数で使用する `issue_to_entry` 連想配列が issue 番号のみをキーとしているため、クロスリポ環境で異なるリポジトリに同一 issue 番号が存在する場合、後勝ちで上書きされる衝突が発生する。

## What Changes

- `issue_to_entry` 連想配列のキーを `repo_id:issue_num`（entry 形式）に変更（L342, L346）
- `issue_list` を entry 形式で保持するよう変更
- poll ループ内の `issue_to_entry` アクセスを entry キーに更新（L353, L413）
- `state-read/state-write` 呼び出し時に `--repo "$repo_id"` 引数を追加（`_default` 以外）
- `window_name`（tmux window 名）生成に `repo_id` を含める（`_default` 時は従来通り `ap-#N`、クロスリポ時は `ap-{repo_id}-#N`）
- `cleaned_up` 連想配列のキーも entry 形式に統一
- `cleanup_worker` / `check_and_nudge` への引数形式の更新

## Capabilities

### New Capabilities

- クロスリポ環境における同一番号・異リポ Issue が同一 Phase に含まれる場合の衝突防止

### Modified Capabilities

- `poll_phase()` 関数: entry キー形式（`repo_id:issue_num`）でのポーリング管理
- `window_name` 生成: クロスリポ時に `repo_id` を含む一意な tmux ウィンドウ名

## Impact

- 影響ファイル: `scripts/autopilot-orchestrator.sh`（poll_phase 関連 L340-L430 付近）
- 単一リポ（`_default`）の動作は変更なし
- `state-read.sh` / `state-write.sh` の `--repo` 引数対応が前提（既存サポート済み）
