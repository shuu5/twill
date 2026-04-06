## 1. path フィールド更新

- [x] 1.1 `rename_component()` のプレビューフェーズに path 置換ロジックを追加（old_name → new_name のパスコンポーネント境界マッチ）
- [x] 1.2 `rename_component()` の適用フェーズに path 更新の deps.yaml 書き戻しを追加
- [x] 1.3 dry-run で path 変更をプレビュー表示に追加

## 2. entry_points 更新

- [x] 2.1 `rename_component()` のプレビューフェーズに entry_points リスト内パス置換ロジックを追加
- [x] 2.2 `rename_component()` の適用フェーズに entry_points 更新の deps.yaml 書き戻しを追加
- [x] 2.3 dry-run で entry_points 変更をプレビュー表示に追加

## 3. ディレクトリ rename

- [x] 3.1 移動先ディレクトリの存在チェック（既存時はエラー中断）を追加
- [x] 3.2 path の親ディレクトリに old_name が含まれる場合の `Path.rename()` を追加（promote_component() を参考）
- [x] 3.3 ディレクトリ rename 後の空ディレクトリ削除を追加
- [x] 3.4 deps.yaml 書き戻し失敗時のディレクトリ rename ロールバックを追加
- [x] 3.5 dry-run でディレクトリ移動をプレビュー表示に追加

## 4. テスト

- [x] 4.1 path 更新のテスト（標準ケース + 部分一致防止）
- [x] 4.2 entry_points 更新のテスト（存在/未定義ケース）
- [x] 4.3 ディレクトリ rename のテスト（成功/移動先存在/ディレクトリなし/ロールバック）
