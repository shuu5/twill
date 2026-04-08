---
type: atomic
tools: [Bash, Skill, Read]
effort: low
maxTurns: 10
---
# テスト実行

プロジェクトのテストスイートを実行し、結果を返す。

## 入力

- テストファイル（tests/ ディレクトリ）
- パッケージマネージャ（init で検出済み）

## 出力

- テスト結果（PASS / FAIL + 失敗テストリスト）

## 冪等性

何度実行しても同じ結果を返す（テスト対象が変わらない限り）。

## 実行ロジック（MUST）

### Step 1: テストランナー検出

| 検出条件 | テストコマンド |
|---------|--------------|
| `tests/run-all.sh` 存在 | `bash tests/run-all.sh` |
| `package.json` に test スクリプト | `npm test` / `pnpm test` |
| `pytest.ini` or `pyproject.toml` | `pytest` |
| `tests/scenarios/*.test.sh` 存在 | 各 .test.sh を順次実行 |

### Step 2: テスト実行

検出されたテストランナーで全テストを実行。タイムアウト: 5 分。

### Step 3: 結果判定

```
IF 全テスト PASS → PASS
IF 1 件以上 FAIL → FAIL + 失敗テスト名と出力を記録
IF テストなし → WARN（テストファイルなし）
```

## チェックポイント（MUST）

`/twl:fix-phase` を Skill tool で自動実行。

