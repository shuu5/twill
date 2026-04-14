## 1. baseline-bash.md の新規作成

- [x] 1.1 `plugins/twl/refs/baseline-bash.md` を作成し、frontmatter（name, description, type: reference, disable-model-invocation: true）を設定する
- [x] 1.2 `## 1. Character Class のハイフン配置` セクションを追加し、BAD/GOOD 対比コードブロックを記述する
- [x] 1.3 `## 2. for-loop 変数の local 宣言` セクションを追加し、BAD/GOOD 対比コードブロックを記述する
- [x] 1.4 `## 3. local 宣言の set -u 初期化` セクションを追加し、BAD/GOOD 対比コードブロックを記述する
- [x] 1.5 `baseline-coding-style.md` L156-178 の IFS パースセクションを `baseline-bash.md` の `## 4. 環境変数パースの IFS 問題` として移設する

## 2. baseline-coding-style.md の IFS セクション置換

- [x] 2.1 `plugins/twl/refs/baseline-coding-style.md` の IFS セクション（L156-178）の内容を `→ baseline-bash.md の ## 4 を参照` のリンクノートに置換する

## 3. worker-code-reviewer.md の更新

- [x] 3.1 `plugins/twl/agents/worker-code-reviewer.md` の Baseline 参照（MUST）セクションの番号付きリストに、3 番目のエントリとして `**/refs/baseline-bash.md` への参照を追加する

## 4. deps.yaml の更新

- [x] 4.1 `plugins/twl/deps.yaml` の C-3 セクションに `baseline-bash` エントリ（type: reference, path: refs/baseline-bash.md）を追加する
- [x] 4.2 `plugins/twl/deps.yaml` の `phase-review` calls セクションに `- reference: baseline-bash` を `- reference: baseline-input-validation` の直後に追加する
- [x] 4.3 `plugins/twl/deps.yaml` の `merge-gate` calls セクションに `- reference: baseline-bash` を `- reference: baseline-input-validation` の直後に追加する

## 5. 最終確認

- [x] 5.1 `twl --check` が PASS することを確認する
- [x] 5.2 AC の全チェックポイントが満たされていることを確認する（baseline-bash.md の 4 セクション・frontmatter・BAD/GOOD 対比・IFS キーワード・worker-code-reviewer.md 参照・deps.yaml エントリ）
