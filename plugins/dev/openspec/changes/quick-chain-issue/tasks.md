## 1. GitHub ラベル作成

- [x] 1.1 `quick` ラベルを loom-plugin-dev, loom, ubuntu-note-system の 3 リポジトリに作成（`gh label create quick --description "小規模Issue: 軽量chain対象" --color "0E8A16"`）

## 2. deps.yaml 軽量 chain 定義

- [x] 2.1 ~~deps.yaml の chains セクションに `quick-setup` chain を追加~~ → chain-bidir 制約（単一 chain 値のみ）により deps.yaml 独立 chain 定義は不可。workflow-setup SKILL.md のドメインルールとして setup chain のステップ部分実行（opsx-propose/ac-extract スキップ）で対応

## 3. workflow-setup init quick 検出

- [x] 3.1 chain-runner.sh の `step_init` に Issue ラベル取得ロジック追加（`gh issue view --json labels`）
- [x] 3.2 `is_quick` フィールドを init JSON 出力に追加
- [x] 3.3 workflow-setup SKILL.md に quick 分岐ロジック追加（`is_quick=true` → setup chain のステップ部分実行、opsx-propose/ac-extract スキップ、「直接実装可能」案内）

## 4. co-issue Phase 2 quick 判定

- [x] 4.1 co-issue SKILL.md Phase 2 に quick 判定基準を追加（変更ファイル 1-2 個 AND ~20行以下、patch レベル記述、Markdown/config のみ）
- [x] 4.2 quick 候補推定時に Phase 3b への `quick-classification` 検証指示を追加

## 5. co-issue Phase 3b specialist 検証

- [x] 5.1 issue-critic agent への指示に `quick-classification` カテゴリの検証ルールを追加
- [x] 5.2 issue-feasibility agent への指示に実コードベースでの変更量検証ルールを追加
- [x] 5.3 逆方向の推奨: 通常 Issue に対する `quick-classification: recommended` finding の出力ルール追加

## 6. co-issue Phase 4 ラベル付与

- [x] 6.1 Phase 4 の Issue 作成ステップに quick ラベル付与ロジック追加（Phase 3b で `inappropriate` finding なし AND Phase 2 で quick 候補）
- [x] 6.2 ユーザー確認画面に quick ラベル状態を表示
- [x] 6.3 `--quick` フラグ使用時は quick ラベル非付与の制約を明記

## 7. 軽量 chain 後の PR フロー

- [x] 7.1 workflow-setup SKILL.md に quick chain 完了後のフロー記述追加（直接実装 → commit → push → PR → merge-gate）
- [x] 7.2 autopilot 判定での quick chain 対応（IS_AUTOPILOT=true 時の軽量 chain 継続フロー）
