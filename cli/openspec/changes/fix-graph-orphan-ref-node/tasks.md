## 1. build_graph() の agent.skills reverse dependency 追加

- [x] 1.1 `build_graph()` の逆依存構築セクション（L446-462 付近）に agent.skills 走査ループを追加
- [x] 1.2 agent.skills の参照先がグラフに存在しない場合のスキップ処理を確認

## 2. classify_layers() の再帰走査

- [x] 2.1 L671-682 の L1→L2 走査を BFS ループに置換（visited set で循環防止）
- [x] 2.2 direct_commands を seed として、新規発見 commands を sub_commands に追加する再帰走査を実装

## 3. Legend の reference 型確認

- [x] 3.1 generate_graphviz() の existing_types 構築で reference が正しく含まれることを確認
- [x] 3.2 必要であれば Legend 表示ロジックを修正

## 4. テスト・検証

- [x] 4.1 `pytest tests/` で既存テスト全 PASS を確認
- [x] 4.2 agent.skills を含む deps.yaml でグラフ生成し、orphan 分類が正しいことを確認
- [x] 4.3 深いチェーン（3 段以上）で sub_commands 分類が正しいことを確認
