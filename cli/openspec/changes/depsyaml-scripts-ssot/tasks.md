## 1. 型定義とパーサー基盤

- [x] 1.1 types.yaml に `script` 型を追加（section: scripts, can_spawn: [], spawnable_by: [atomic, composite]）
- [x] 1.2 loom-engine.py の _FALLBACK_TYPE_RULES に script エントリ追加
- [x] 1.3 build_graph に scripts セクション処理ループ追加（`script:{name}` ノード生成）
- [x] 1.4 parse_calls の key_map に `'script': 'script'` 追加
- [x] 1.5 find_node の prefix リストに `'script'` 追加

## 2. バリデーション

- [x] 2.1 validate_types の section_map に `'scripts': 'script'` 追加、走査ループに scripts セクション追加
- [x] 2.2 validate_types の call_key_to_section に `'script': 'scripts'` 追加
- [x] 2.3 validate_v3_schema の v3_type_keys に `'script'` 追加
- [x] 2.4 validate_v3_schema に旧形式 scripts フィールド WARNING 追加（[v3-legacy-scripts]）
- [x] 2.5 validate_body_refs で scripts セクションをスキップ
- [x] 2.6 deep_validate で scripts セクションの tools チェックをスキップ

## 3. 可視化

- [x] 3.1 classify_layers に scripts レイヤー追加
- [x] 3.2 generate_graphviz に script ノード描画追加（オレンジ #FF9800、hexagon）
- [x] 3.3 generate_graphviz のエッジ生成で script ノードへの接続対応
- [x] 3.4 generate_subgraph_graphviz に script ノード描画追加
- [x] 3.5 generate_mermaid に script ノード描画追加（六角形、オレンジスタイル）
- [x] 3.6 main の --list に SCRIPTS セクション追加
- [x] 3.7 main の --tokens に Scripts セクション追加

## 4. 保守コマンド

- [x] 4.1 find_orphans で script ノードの no_deps 判定を調整（script は can_spawn:[] なので agent と同様にスキップ）
- [x] 4.2 check_dead_components: script ノードは既存ロジックで処理されるため変更不要を確認
- [x] 4.3 rename_component の検索セクションに `'scripts'` 追加
- [x] 4.4 rename_component の calls 更新で `script` キーに対応
- [x] 4.5 audit_report の all_components 収集に scripts セクション追加、script 型は各チェックセクションでスキップ
- [x] 4.6 complexity_report の calc_type_balance で script を含める

## 5. テスト

- [x] 5.1 types.yaml 読み込みテスト（script 型が TYPE_RULES に含まれること）
- [x] 5.2 build_graph テスト（scripts セクションからノード生成）
- [x] 5.3 validate_types テスト（script の正当/不正呼び出しエッジ）
- [x] 5.4 validate_v3_schema テスト（script キー許可、旧形式 WARNING）
- [x] 5.5 graphviz 出力テスト（script ノード存在、スタイル確認）
- [x] 5.6 orphans/dead component テスト（script 検出）
- [x] 5.7 rename テスト（scripts セクション + calls 更新）
- [x] 5.8 既存テスト全通過確認
