## 1. types.yaml の script.can_spawn 修正

- [x] 1.1 types.yaml の `script.can_spawn: []` を `script.can_spawn: [script]` に変更
- [x] 1.2 既存テスト（`pytest tests/`）が PASS することを確認

## 2. Cross-plugin 参照のパース

- [x] 2.1 calls 値のパースで `:` を含む値を `(plugin, component)` タプルに分割する関数を追加
- [x] 2.2 `build_graph()` で cross-plugin 参照ノードを生成（`xref:{plugin}:{component}` 形式）
- [x] 2.3 cross-plugin 参照のパースに関するユニットテストを追加

## 3. Cross-plugin 参照先の解決

- [x] 3.1 参照先 plugin の deps.yaml を `~/.claude/plugins/{plugin}/` から読み込む `resolve_cross_plugin()` 関数を追加
- [x] 3.2 参照先 plugin が見つからない場合の warning ハンドリングを実装
- [x] 3.3 解決ロジックのユニットテストを追加

## 4. validate の cross-plugin 対応

- [x] 4.1 `validate_types()` に cross-plugin 参照エッジの型整合性チェックを追加
- [x] 4.2 参照先 plugin 不在時の warning 出力を実装
- [x] 4.3 cross-plugin validate のシナリオテストを追加

## 5. check の cross-plugin 対応

- [x] 5.1 check コマンドで cross-plugin 参照先の path 解決とファイル存在チェックを追加
- [x] 5.2 参照先 plugin 不在時の warning 出力を実装
- [x] 5.3 cross-plugin check のシナリオテストを追加

## 6. 統合テストとドキュメント

- [x] 6.1 cross-plugin 参照を含むシナリオテストの追加（正常系・異常系）
- [x] 6.2 全既存テストの PASS を確認
