# ac-test-mapping-N.yaml スキーマ仕様

`ac-test-mapping-N.yaml` は AC（受け入れ基準）とテストファイルの対応関係を記録する SSoT ファイル。
`ac-verify.md` および `ac-impl-coverage-check.sh` がこのファイルを読み込む。

## スキーマ

```yaml
mappings:
  - ac_index: <number or string>  # AC 番号（1, 1b, 2 など）
    ac_text: <string>             # AC テキスト（要約）
    test_file: <string>           # テストファイルパス（リポジトリルートからの相対パス）
    test_name: <string>           # テスト関数/describe 名
    impl_files:                   # 実装ファイルパス一覧（optional, string[]）
      - <string>
```

## フィールド定義

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `ac_index` | number \| string | ✓ | AC 番号。小数点サブ項目 (`1b`, `2c`) も可 |
| `ac_text` | string | ✓ | AC の要約テキスト |
| `test_file` | string | ✓ | 対応テストファイルのパス |
| `test_name` | string | ✓ | テスト関数名または describe ラベル |
| `impl_files` | string[] | — | AC が対応する実装ファイルパス一覧（任意フィールド） |

## `impl_files` フィールドの仕様

### 目的

`impl_files` は `ac-impl-coverage-check.sh` による機械検証の入力として使用される。
PR diff に `impl_files` 内のいずれかのファイルが含まれていれば「実装済み」と判定する。

### 必須化ルール（段階移行）

| 状況 | `impl_files` 要否 | 備考 |
|------|------------------|------|
| 既存 mapping（#1018/#1019/#1027/#1102/#970 等） | 任意（不在許容） | 段階移行のため後方互換 |
| **新規生成 mapping（`ac-scaffold-tests` 経由）** | **必須** | `ac-impl-coverage-check.sh` が WARNING を出力して CI で表面化 |

### `impl_files` 不在時の動作

`ac-impl-coverage-check.sh` は `impl_files` が完全に欠落している mapping エントリを検出した場合:
- mapping 全 AC で不在 → `severity: "WARNING"`, `category: "ac-impl-coverage-skip"` を 1 件出力（exit 2）
- 一部 AC で不在（混在）→ 不在 AC に `severity: "INFO"`, `category: "ac-impl-coverage-skip"` を出力し、LLM fallback

### 値の記述ルール

1. リポジトリルートからの相対パスで記述する
2. 実装の主体となるファイルを列挙する（テストファイルは含めない）
3. 推定できない場合は空配列 `impl_files: []` を書き、コメントで補足する

```yaml
# 推定失敗例
impl_files: []
# impl_files 推定失敗: 手動補完が必要
```

## 運用ルール（ac-scaffold-tests 経由での新規生成）

`ac-scaffold-tests.md` が新規 mapping を生成する際は以下のロジックで `impl_files` を設定する:

1. AC テキストからファイル名・パスのキーワードを抽出（Glob/Grep ベース）
2. 既存ファイルと照合してパスを確定
3. 候補が見つかった場合: `impl_files: [<path>, ...]` を設定
4. 候補が見つからない場合: `impl_files: []` + コメントを設定

## 例

### 基本形（既存 mapping 互換）

```yaml
mappings:
  - ac_index: 1
    ac_text: "PR #1024 と同型の AC 未達成 case を bats fixture で再現"
    test_file: "plugins/twl/tests/bats/issue-1025-specialist-warning-gate.bats"
    test_name: "ac1: category=ac_missing の WARNING が findings に存在するフィクスチャ作成"
```

### impl_files 付き（新規生成推奨形式）

```yaml
mappings:
  - ac_index: 1
    ac_text: "ac-impl-coverage-check.sh を新設する"
    test_file: "plugins/twl/tests/bats/ac-impl-coverage-check.bats"
    test_name: "ac2: ac-impl-coverage-check.sh が scripts/ に存在する"
    impl_files:
      - "plugins/twl/scripts/ac-impl-coverage-check.sh"
  - ac_index: 2
    ac_text: "chain-runner.sh::step_ac_verify に pre-call 統合"
    test_file: "plugins/twl/tests/bats/ac-impl-coverage-check.bats"
    test_name: "ac3: chain-runner.sh の step_ac_verify に ac-impl-coverage-check 呼び出しが含まれる"
    impl_files:
      - "plugins/twl/scripts/chain-runner.sh"
  - ac_index: 3
    ac_text: "impl_files 候補推定不能な AC"
    test_file: "plugins/twl/tests/bats/ac-impl-coverage-check.bats"
    test_name: "ac3b: ..."
    impl_files: []
    # impl_files 推定失敗: 手動補完が必要
```

## 関連

- `plugins/twl/scripts/ac-impl-coverage-check.sh` — このスキーマを入力に機械検証を実行
- `plugins/twl/commands/ac-verify.md` — Step 0.5 で ac-impl-coverage-check.sh を pre-call
- `plugins/twl/agents/ac-scaffold-tests.md` — 新規 mapping 生成時に impl_files を設定
- Issue #1105 — このスキーマ拡張の実装 Issue
