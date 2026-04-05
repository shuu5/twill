## 1. merge-gate-execute.sh の修正

- [x] 1.1 `scripts/merge-gate-execute.sh` を読み、`*)` デフォルト分岐の先頭位置（`REPO_MODE` 判定の前）を確認する
- [x] 1.2 `*)` 分岐先頭に status=running ブロックを追加する（state-read.sh 呼び出し → running なら exit 1、merge-ready なら情報ログ）
- [x] 1.3 既存 Layer 3 (L79-82) のログ出力が重複しないよう調整する（削除または統合）

## 2. auto-merge.sh の修正

- [x] 2.1 `scripts/auto-merge.sh` を読み、Layer 1（IS_AUTOPILOT 判定）の直後の位置を確認する
- [x] 2.2 Layer 1 直後に IS_AUTOPILOT=false && AUTOPILOT_STATUS=running の矛盾検出ロジックを追加する（merge-ready 宣言 + exit 0）

## 3. テスト追加

- [x] 3.1 `tests/bats/scripts/fix-worker-merge-gate-invariant-c.bats` を新規作成する
- [x] 3.2 テストケース追加: merge-gate-execute.sh が status=running 時に exit 1 を返す
- [x] 3.3 テストケース追加: merge-gate-execute.sh の --reject モードが status=running 時に exit 1 を返さない（非回帰）
- [x] 3.4 テストケース追加: merge-gate-execute.sh が status=merge-ready 時に merge を試みる（exit 1 しない）
- [x] 3.5 テストケース追加: auto-merge.sh が IS_AUTOPILOT=false && status=running 矛盾時に merge-ready 宣言して exit 0 を返す

## 4. 検証

- [x] 4.1 既存の bats テスト（`tests/bats/scripts/` 配下）を全て実行し PASS を確認する
- [x] 4.2 新規テスト `fix-worker-merge-gate-invariant-c.bats` を実行し PASS を確認する
