---
type: atomic
tools: [Bash]
effort: low
maxTurns: 10
---
# test-target リセット

test-target worktree を初期状態（`test-target/initial` tag）に戻す。

## 処理フロー（MUST）

### Step 1: プロジェクトルート解決

```bash
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
BARE_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
TEST_TARGET="$BARE_ROOT/worktrees/test-target"
```

### Step 2: 存在チェック

```bash
[[ -d "$TEST_TARGET" ]] || { echo '{"error": "test-target worktree が存在しません。先に /twl:test-project-init を実行してください"}'; exit 1; }
```

### Step 3: cwd 安全確認（MUST）

```bash
CURRENT_DIR="$(pwd)"
if [[ "$CURRENT_DIR" == "$TEST_TARGET"* ]]; then
  echo '{"error": "test-target worktree 内から reset は実行できません。worktree 外に移動してから再実行してください"}'
  exit 1
fi
```

### Step 4: ユーザー確認（MUST）

AskUserQuestion: 「test-target を初期状態に reset します。未 push の変更は失われます。続行しますか?」

- No → no-op で終了
- Yes → Step 5 へ

### Step 5: reset 実行

```bash
cd "$TEST_TARGET"
git reset --hard test-target/initial
git clean -fdx
```

### Step 6: JSON 出力

```json
{
  "status": "reset",
  "path": "<worktree path>",
  "commit": "<test-target/initial の commit hash>",
  "file_count": <reset 後のファイル数>
}
```

## 禁止事項（MUST NOT）

- cwd が test-target 内の場合に reset を実行してはならない
- ユーザー確認なしに reset を実行してはならない
