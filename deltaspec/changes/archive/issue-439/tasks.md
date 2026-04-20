## 1. mergegate.py 実装

- [x] 1.1 `_check_phase_review_guard()` 関数を追加（checkpoint 不在チェック + scope/direct/quick ラベル例外）
- [x] 1.2 `_check_phase_review_findings()` ロジックを追加（CRITICAL findings (confidence >= 80) の統合）
- [x] 1.3 `execute()` メソッドの checkpoint 検査フローに phase-review ガードを組み込む
- [x] 1.4 `--force` 使用時に phase-review 不在を WARNING ログに記録する処理を追加

## 2. merge-gate.md 更新

- [x] 2.1 `checkpoint 統合（MUST）` セクションに phase-review checkpoint の読み込み処理を追記
- [x] 2.2 `severity フィルタ判定` セクションに phase-review MISSING 条件の REJECT ルールを追記
- [x] 2.3 `scope/direct` / `quick` ラベル例外の処理フローを記述

## 3. テスト

- [x] 3.1 phase-review.json 不在時に REJECT を返すユニットテストを追加
- [x] 3.2 scope/direct ラベル付き Issue では phase-review チェックがスキップされるテストを追加
- [x] 3.3 quick ラベル付き Issue では phase-review チェックがスキップされるテストを追加
- [x] 3.4 phase-review に CRITICAL findings がある場合の REJECT テストを追加
- [x] 3.5 --force 使用時に WARNING が記録されるテストを追加
