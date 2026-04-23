---
type: composite
tools: [Bash, Agent, Read]
effort: medium
maxTurns: 20
---
# テスト生成（AC-based）

AC チェックリストを入力に、TDD RED フェーズ用テストを生成する。

## 入力

1. `${SNAPSHOT_DIR:-${CLAUDE_PLUGIN_ROOT}/.dev-session}/01.5-ac-checklist.md` — ac-extract が生成した AC 一覧
2. Issue body の `## AC` / `## Acceptance Criteria` 節（01.5-ac-checklist.md 不在時のフォールバック）
3. 実装対象ファイル（Issue body / context から特定）

## 実行フロー

### Step 1: AC 読み込み

```bash
SNAPSHOT_DIR="${SNAPSHOT_DIR:-${CLAUDE_PLUGIN_ROOT}/.dev-session}"
AC_FILE="${SNAPSHOT_DIR}/01.5-ac-checklist.md"
if [[ -f "$AC_FILE" ]]; then
  cat "$AC_FILE"
else
  echo "WARN: AC チェックリスト未検出 ($AC_FILE) — Issue body から AC を直接読む"
fi
```

### Step 2: ac-scaffold-tests agent 呼び出し

`agents/ac-scaffold-tests.md` を Read して、AC リストを入力に agent を実行する。

Agent への引き渡し情報:
- AC 項目リスト（01.5-ac-checklist.md または Issue body から抽出）
- 実装対象ファイルパス
- テストフレームワーク（既存テストから自動推定: pytest/vitest/testthat）

### Step 3: 出力確認

agent 実行後、以下が生成されていることを確認:
- test ファイル（1 AC 項目 = 1 RED test が原則）
- `ac-test-mapping.yaml`（AC 番号 → test file path + test name のマッピング）

`ac-test-mapping.yaml` の形式:
```yaml
mappings:
  - ac_index: 1
    ac_text: "..."
    test_file: "tests/test_foo.py"
    test_name: "test_ac1_..."
  - ac_index: 2
    ac_text: "..."
    test_file: "tests/test_foo.py"
    test_name: "test_ac2_..."
```

## 禁止事項（MUST NOT）

- deltaspec/changes/ を参照してはならない
- テスト生成をスキップしてはならない（対象コードなし以外の独断スキップ禁止）
- 既存テストを削除・弱化してはならない
