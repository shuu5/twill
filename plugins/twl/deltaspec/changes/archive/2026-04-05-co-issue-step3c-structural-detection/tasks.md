## 1. SKILL.md Step 3c 出力なし検知ロジック変更

- [x] 1.1 `skills/co-issue/SKILL.md` の Step 3c「[前処理] 出力なし完了の検知（上位ガード）」を開き、現行の `status:` / `findings:` キーワード検索の記述を特定する
- [x] 1.2 status 検出を `^status:\s*(PASS|WARN|FAIL)` に変更する
- [x] 1.3 findings 検出を `^findings:` に変更する
- [x] 1.4 「いずれのパターンにもマッチしない場合を『出力なし』として扱い、WARNING を出力」する旨の記述を更新する

## 2. ref との関係注記追加

- [x] 2.1 Step 3c の出力なし検知セクションに「本ガードは `refs/ref-specialist-output-schema.md` の消費側パースルールの上位ガードとして、行頭縛りを追加適用する（ref 自体は変更しない）」旨の注記を追加する

## 3. 検証

- [x] 3.1 変更後の SKILL.md を読み直し、Step 3c セクションが仕様通りに更新されていることを確認する
