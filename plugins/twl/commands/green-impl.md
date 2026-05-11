---
type: composite
tools: [Bash, Agent, Read]
effort: medium
maxTurns: 20
---
# GREEN 実装（AC-based）

`ac-scaffold-tests` 直後の TDD GREEN フェーズ実装コマンド。`ac-test-mapping.yaml` の `impl_files` を参照し、RED test を PASS させる最小実装を生成する。

## 入力

1. `${SNAPSHOT_DIR:-${CLAUDE_PLUGIN_ROOT}/.dev-session}/01.5-ac-checklist.md` — AC 一覧
2. `ac-test-mapping.yaml` — `test-scaffold` step が生成した RED test → impl_files マッピング
3. RED test ファイル群（`mappings[].test_file` から特定）

## 実行フロー

### Step 1: AC + mapping 読み込み

```bash
SNAPSHOT_DIR="${SNAPSHOT_DIR:-${CLAUDE_PLUGIN_ROOT:-.}/.dev-session/issue-${ISSUE_NUM:-unknown}}"
AC_FILE="${SNAPSHOT_DIR}/01.5-ac-checklist.md"
MAPPING_FILE="${SNAPSHOT_DIR}/ac-test-mapping.yaml"

# AC 一覧
[[ -f "$AC_FILE" ]] && cat "$AC_FILE" || echo "WARN: AC チェックリスト未検出 ($AC_FILE)"

# mapping (impl_files の所在)
if [[ -f "$MAPPING_FILE" ]]; then
  cat "$MAPPING_FILE"
else
  echo "ERROR: ac-test-mapping.yaml が未生成 ($MAPPING_FILE)。test-scaffold step を先に実行する必要がある。"
  exit 1
fi
```

### Step 2: ac-scaffold-tests agent 呼び出し（mode=green）

`agents/ac-scaffold-tests.md` を Read し、**`mode=green`** を明示して agent を Task tool で起動する。

Agent への引き渡し情報（自然言語 prompt 内に含める）:
- "Use the ac-scaffold-tests subagent **with mode=green**"
- AC 一覧（01.5-ac-checklist.md または Issue body から）
- `ac-test-mapping.yaml` の全 `impl_files` パス
- 既存 RED test ファイル群の所在
- 既存実装ファイルのコーディング規約 (関数命名、エラー処理、ログ形式) を踏襲する旨

### Step 3: 出力確認

agent 実行後、後段の `tdd-green-guard.sh` で以下を機械検証する:
- `ac-test-mapping.yaml` の `impl_files` 全件が **編集または新規作成** されている (git diff に含まれる)
- RED test が GREEN になっている (全テスト PASS)

本コマンド (`commands/green-impl.md`) の責務は **agent 起動と impl_files 生成のみ**。検証は呼び出し側 SKILL の Step 1.5 が `tdd-green-guard.sh` を実行することで完了する (責務分離)。

## 禁止事項（MUST NOT）

- `deltaspec/changes/` を参照してはならない
- RED test ファイル自体を編集して PASS にしてはならない（実装ファイル側の編集のみ）
- 全テスト GREEN を偽装するために RED test を skip してはならない
- AC が要求しない機能を実装してはならない（最小実装の原則）
