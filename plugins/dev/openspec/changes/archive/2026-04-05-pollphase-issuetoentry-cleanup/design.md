## Context

`scripts/autopilot-orchestrator.sh` の `poll_phase()` 関数内で、`issue_to_entry` 連想配列は `issue_to_entry["$e"]="$e"` のように自己参照マップとして宣言されている。この配列から取得した `issue_entry` 変数は常に `entry` と同一の値を持つため、どちらも冗長である。

## Goals / Non-Goals

**Goals:**
- `issue_to_entry` 連想配列の宣言・代入・参照を削除
- `issue_entry` 変数を削除
- `cleanup_worker "$issue_num" "$issue_entry"` を `cleanup_worker "$issue_num" "$entry"` に変更

**Non-Goals:**
- `poll_phase()` 以外の関数への変更
- ロジックの変更

## Decisions

- `issue_entry` の参照箇所を `entry` に直接置き換える（値は常に等しいため）
- 連想配列 `declare -A issue_to_entry` の宣言自体を削除する

## Risks / Trade-offs

- リスクなし。純粋なコード簡略化であり、動作は変わらない
