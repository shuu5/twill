## Context

`plugins/twl/tests/scenarios/skillmd-pilot-fixes.test.sh` は 342 行のシェルスクリプトで、以下のものが混在している:
- 共通テストユーティリティ（ヘルパー関数・カウンター・サマリー出力）: 約 60 行
- 実際のテストロジック: 約 270 行（4 要件、19 テスト）

ベースライン閾値（300 行）を超えているため、警告が出続ける状態。

既存の `tests/helpers/` ディレクトリは存在せず、新規作成が必要。現在のすべてのテストスクリプトはヘルパーをインラインで定義している（重複コード）。

## Goals / Non-Goals

**Goals:**
- `tests/helpers/test-common.sh` を作成し、共通ヘルパーを抽出する
- `skillmd-pilot-fixes.test.sh` を 300 行以下に削減する
- 既存のテストロジックと通過/失敗ロジックを変更しない

**Non-Goals:**
- 他のテストスクリプトのリファクタリング（本 Issue のスコープ外）
- テストロジック自体の変更
- テストシナリオの分割（ヘルパー抽出で閾値を達成できる）

## Decisions

**ヘルパー抽出アプローチを採用**（シナリオ分割より）:
- 4 要件・19 テストは概念的に 1 ファイルに収まる粒度
- ヘルパー関数（assert_file_exists, assert_file_contains, assert_file_not_contains, run_test, run_test_skip）は約 40 行で再利用性が高い
- カウンター初期化（PASS/FAIL/SKIP/ERRORS 宣言）とサマリー出力も helpers に移動
- `source` による読み込みでスクリプト構造を変えず安全にリファクタリング可能

**test-common.sh の設計**:
- `PROJECT_ROOT` は呼び出し元スクリプトで設定済みと仮定（変数参照）
- `PASS`, `FAIL`, `SKIP`, `ERRORS` カウンター初期化を含む
- `print_summary()` 関数でサマリー出力を統一

## Risks / Trade-offs

- `source` パスが相対パスになる場合、実行ディレクトリに依存するリスク → `BASH_SOURCE[0]` を使った絶対パス解決で対処
- 他テストスクリプトとの互換性: 今回は `skillmd-pilot-fixes.test.sh` のみ変更するため影響なし
