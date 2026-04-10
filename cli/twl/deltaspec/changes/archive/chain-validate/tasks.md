## 1. chain_validate 関数の実装

- [x] 1.1 `chain_validate(deps, plugin_root)` 関数のスケルトンを `twl-engine.py` に追加（`deep_validate` の直後、同じシグネチャ `(criticals, warnings, infos)` を返す）
- [x] 1.2 chain 双方向検証の実装: `chains.steps` → `component.chain` の順方向チェック
- [x] 1.3 chain 双方向検証の実装: `component.chain` → `chains.steps` の逆方向チェック
- [x] 1.4 step 双方向検証の実装: `parent.calls[].step` → `child.step_in` の順方向チェック
- [x] 1.5 step 双方向検証の実装: `child.step_in` → `parent.calls[].step` の逆方向チェック
- [x] 1.6 Chain 参加者型制約検証の実装（chain.type フィールドに基づく A/B 判定）
- [x] 1.7 step 番号昇順検証の実装（calls 配列内の step 値を文字列→数値変換して比較）

## 2. prompt-consistency 検証の実装

- [x] 2.1 body テキストから `Step {N} から呼び出される` / `の Step {N} から呼び出される` パターンを検出する正規表現の実装
- [x] 2.2 検出されたパターンと deps.yaml の step_in 情報を照合するロジックの実装

## 3. twl check への統合

- [x] 3.1 `--check` ハンドラ内で `get_deps_version` による v3.0 判定を追加し、`chain_validate` を呼び出す
- [x] 3.2 `--validate` ハンドラにも `chain_validate` 結果を統合
- [x] 3.3 `--deep-validate` ハンドラにも `chain_validate` 結果を統合
- [x] 3.4 CRITICAL がある場合に非ゼロ終了することを確認

## 4. テスト

- [x] 4.1 chain 双方向検証のテスト（正常系・異常系）
- [x] 4.2 step 双方向検証のテスト（正常系・異常系）
- [x] 4.3 Chain 型制約検証のテスト（A/B 各パターン）
- [x] 4.4 step 昇順検証のテスト
- [x] 4.5 prompt-consistency 検証のテスト
- [x] 4.6 twl check 統合テスト（v3.0 / v2.0 分岐確認）
