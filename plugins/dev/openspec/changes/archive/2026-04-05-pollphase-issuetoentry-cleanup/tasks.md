## 1. コード修正

- [x] 1.1 `scripts/autopilot-orchestrator.sh` の `poll_phase()` で `declare -A issue_to_entry` 宣言を削除
- [x] 1.2 `poll_phase()` で `issue_to_entry["$e"]="$e"` の代入を削除
- [x] 1.3 `poll_phase()` で `issue_entry="${issue_to_entry[$e]}"` の代入を削除
- [x] 1.4 `cleanup_worker "$issue_num" "$issue_entry"` を `cleanup_worker "$issue_num" "$entry"` に変更

## 2. 検証

- [x] 2.1 `poll_phase()` 内に `issue_to_entry` / `issue_entry` の残存がないか grep で確認
