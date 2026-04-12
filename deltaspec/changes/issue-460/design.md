## Context

`chain-runner.sh` と `autopilot-orchestrator.sh` の両方が `resolve_deltaspec_root()` と同一の walk-down find ロジックを持っている。前者は関数として定義しており、後者は `_archive_deltaspec_changes_for_issue()` 内でインラインに同一ロジックを持つ。

- `chain-runner.sh:61-79` — `resolve_deltaspec_root()` 正規実装
- `autopilot-orchestrator.sh:1140-1147` — 同一 find ロジックのインライン重複

両スクリプトはそれぞれ `SCRIPT_DIR`/`SCRIPTS_ROOT` を `BASH_SOURCE[0]` ベースで解決し、`lib/` 以下を source する確立されたパターンを持つ（`lib/python-env.sh` が既に共有されている）。

## Goals / Non-Goals

**Goals:**

- `resolve_deltaspec_root()` を `plugins/twl/scripts/lib/deltaspec-helpers.sh` に移動する
- `chain-runner.sh` と `autopilot-orchestrator.sh` の両方から `deltaspec-helpers.sh` を source する
- `autopilot-orchestrator.sh` の `_archive_deltaspec_changes_for_issue()` 内のインライン find ロジックを `resolve_deltaspec_root()` 呼び出しに置換する
- shellcheck を両スクリプトで通す
- bats 回帰テストを追加する

**Non-Goals:**

- multi-root 走査・orphan 掃除（別 Issue に委譲）
- `resolve_deltaspec_root()` の挙動変更
- 他スクリプトへの影響（scope 外）

## Decisions

**案 A（ヘルパーファイル切り出し）を採用**

`lib/python-env.sh` の既存パターンに倣い、`lib/deltaspec-helpers.sh` を新設する。

- パス解決: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` ベースで session-independent に解決
- `chain-runner.sh` の source 行: `source "${SCRIPT_DIR}/lib/deltaspec-helpers.sh"`
- `autopilot-orchestrator.sh` の source 行: `source "${SCRIPTS_ROOT}/lib/deltaspec-helpers.sh"`
- `_archive_deltaspec_changes_for_issue()` 内の `local ds_root="$root"` + インライン find を `local ds_root; ds_root="$(resolve_deltaspec_root "$root")"` の 1 行に置換する

案 B（chain-runner サブコマンド）は orchestrator から subprocess 呼び出しを要するため オーバヘッドが生じる。ライブラリ共有の方がシンプルかつ高速。

## Risks / Trade-offs

- `_archive_deltaspec_changes_for_issue()` の `resolve_deltaspec_root()` 呼び出し後、元の実装では `found_cfg` が見つからない場合でも `ds_root` が `$root` のまま（正常）だったが、`resolve_deltaspec_root()` も見つからない場合は `$root` を echo して `return 1` する。呼び出し側が `|| true` または `return code` を適切に扱う必要がある。ただし `_archive_deltaspec_changes_for_issue()` の後続処理は `$ds_root` の存在チェック（`[[ ! -d "$changes_dir" ]]`）で保護されているため問題なし
- shellcheck: `resolve_deltaspec_root` が別ファイルで定義されるため、`# shellcheck source=./lib/deltaspec-helpers.sh` ディレクティブを追加する必要がある
