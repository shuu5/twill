## 1. change-propose.md の auto_init 対応

- [ ] 1.1 Step 0 を追加: state から `auto_init` フィールドを読み取る処理を記述
- [ ] 1.2 `auto_init=true` 時の change-id 自動導出ロジックを記述（`issue-<N>` 形式）
- [ ] 1.3 `mkdir -p deltaspec/` の先行実行を Step 0 に組み込む
- [ ] 1.4 `twl spec new "issue-<N>"` 呼び出しを Step 0 に追加
- [ ] 1.5 Step 1 に `auto_init=true` 時スキップ条件を追加

## 2. 検証

- [ ] 2.1 `auto_init=false` の場合に既存フローが維持されることを確認
- [ ] 2.2 `auto_init=true` で `deltaspec/` が存在しない状態から change ディレクトリが作成されることを確認
- [ ] 2.3 AC の全チェックボックスを満たすことを検証
