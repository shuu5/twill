## Context

`scripts/autopilot-plan-board.sh` の `_build_cross_repo_json()` は stdout で `issue_list` を返しつつ、グローバル変数（`CROSS_REPO`, `REPO_OWNERS`, `REPO_NAMES`, `REPO_PATHS`, `REPOS_JSON`）を副作用として更新する。`fetch_board_issues()` (L183) がこの関数をコマンド置換 `$()` で呼ぶため、副作用がサブシェルで消失する。

## Goals / Non-Goals

**Goals:**

- `_build_cross_repo_json()` の副作用を親シェルに正しく伝搬させる
- 既存の単一リポジトリ Board テストの PASS 維持
- クロスリポジトリ Board シナリオのテスト追加

**Non-Goals:**

- `_build_cross_repo_json()` の内部ロジック変更（パース・バリデーション等）
- `--board` 以外のモード（`--issues`, `--explicit`）への変更

## Decisions

1. **stdout 出力をグローバル変数 `BUILD_RESULT` に置き換え**: `_build_cross_repo_json()` の末尾 `echo "${issue_list# }"` を `BUILD_RESULT="${issue_list# }"` に変更。呼び出し側はコマンド置換を廃止し直接呼び出し後に `$BUILD_RESULT` を参照する。
   - **理由**: Issue body で提案されたアプローチそのもの。最小限の変更で問題を解決できる。一時ファイルや `declare -n` (nameref) よりシンプル。

2. **テストは `autopilot-plan-board-fetch.bats` に追加**: 既存のヘルパー `_stub_gh_single_project` をベースに、クロスリポジトリ用のスタブ `_stub_gh_cross_repo_project` を `autopilot-plan-board-helpers.bash` に追加。

## Risks / Trade-offs

- `BUILD_RESULT` はグローバル変数のため名前衝突のリスクがあるが、ファイルスコープ内でのみ使用されるため実用上問題なし
- `_build_cross_repo_json()` を他の場所からコマンド置換で呼んでいる箇所があれば影響するが、`fetch_board_issues()` のみが呼び出し元であることを確認済み
