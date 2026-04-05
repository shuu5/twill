## 1. issue_list / issue_to_entry のentry形式移行

- [x] 1.1 `poll_phase()` の entry ループを変更: `issue_list` に entry 形式を格納し、`issue_to_entry` のキーも entry 形式にする
- [x] 1.2 ループ変数名を `issue` → `entry` に変更し、各イテレーション冒頭で `repo_id="${entry%%:*}"` / `issue_num="${entry#*:}"` を取り出す

## 2. state-read/state-write の --repo 引数付与

- [x] 2.1 `state-read.sh` 呼び出し箇所（L355, L415）に `--issue "$issue_num"` を使用し、`repo_id != _default` の場合 `--repo "$repo_id"` を追加
- [x] 2.2 `state-write.sh` 呼び出し箇所（L394-L396, L417-L419）に同様の `--repo` 引数付与

## 3. window_name のクロスリポ対応

- [x] 3.1 `window_name` 生成箇所を `[[ "$repo_id" == "_default" ]] && window_name="ap-#${issue_num}" || window_name="ap-${repo_id}-#${issue_num}"` に変更（L368）

## 4. cleaned_up / cleanup_worker のentry形式統一

- [x] 4.1 `cleaned_up[$issue]` → `cleaned_up[$entry]` に変更（L359-L361）
- [x] 4.2 `cleanup_worker` 呼び出し時の引数を entry キーに対応

## 5. タイムアウトループのentry形式対応

- [x] 5.1 タイムアウト処理（L412-L421）の `issue_list` ループを entry 形式で処理するよう更新

## 6. 動作確認

- [x] 6.1 単一リポ（`_default`）の autopilot フローで既存動作が維持されることを確認
- [x] 6.2 クロスリポ plan.yaml で同一番号の Issue が両方保持されることをコードレビューで確認
