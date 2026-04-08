---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 15
---
# test-target worktree 初期化

co-self-improve framework のテスト対象として、main 履歴と完全分離された orphan branch `test-target/main` を持つ worktree を作成する。

## 前提

- `test-fixtures/minimal-plugin/` が存在すること
- 現在の cwd がプロジェクトルート（bare repo の worktree 配下）であること

## 処理フロー（MUST）

### Step 1: プロジェクトルート解決

```bash
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
BARE_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
```

worktrees/ 配下の worktree なら `$PROJECT_DIR/..` が bare root。bare repo 直下なら `$PROJECT_DIR` 自体。

### Step 2: 既存チェック

```bash
git -C "$BARE_ROOT" worktree list | grep -q "test-target"
```

- 既存ありの場合: AskUserQuestion で「既に test-target が存在します。reset しますか?」と確認。
  - Yes → 「`/twl:test-project-reset` を実行してください」と案内して終了
  - No → no-op で終了
- 既存なしの場合: Step 3 へ

### Step 3: orphan branch 作成 + worktree 追加

```bash
# 1. 空ツリーから orphan commit を作成（main 履歴と完全分離）
EMPTY_TREE=$(git -C "$BARE_ROOT" hash-object -t tree --stdin </dev/null)
INITIAL_COMMIT=$(git -C "$BARE_ROOT" commit-tree "$EMPTY_TREE" -m "test-target: initial empty commit")
git -C "$BARE_ROOT" update-ref refs/heads/test-target/main "$INITIAL_COMMIT"

# 2. worktree 追加
git -C "$BARE_ROOT" worktree add "$BARE_ROOT/worktrees/test-target" test-target/main

# 3. 初期コンテンツ展開
cp -r "$BARE_ROOT/test-fixtures/minimal-plugin/"* "$BARE_ROOT/worktrees/test-target/"

# 4. .test-target/ ディレクトリ作成（Issue ローカル管理用）
mkdir -p "$BARE_ROOT/worktrees/test-target/.test-target/issues"
```

### Step 4: README 自動配置

`$BARE_ROOT/worktrees/test-target/.test-target/README.md` を作成（以下の内容）:

```
# test-target

co-self-improve framework のテスト対象プロジェクト。

## Branch

- `test-target/main` (orphan branch — main とは共通 commit なし)

## WARNING

**このディレクトリの変更は絶対に main branch にコミットしないでください。**

## Reset

初期状態に戻すには: `/twl:test-project-reset`

## Scenario Load

テストシナリオの読み込み: `/twl:test-project-scenario-load --scenario <name>`
```

### Step 5: 初回 commit + tag

```bash
cd "$BARE_ROOT/worktrees/test-target"
git add -A
git commit -m "test-target: initial scaffold from minimal-plugin"
git tag test-target/initial
```

### Step 6: JSON 出力

```json
{
  "status": "created",
  "path": "<worktree path>",
  "branch": "test-target/main",
  "commit": "<commit hash>",
  "tag": "test-target/initial",
  "issue_count": 0
}
```

## 禁止事項（MUST NOT）

- main branch に test-target 関連の commit を作成してはならない
- `git push` してはならない（init はローカル操作のみ）
