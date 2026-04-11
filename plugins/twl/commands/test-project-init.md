---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 15
---
# test-target worktree 初期化

co-self-improve framework のテスト対象として、main 履歴と完全分離された orphan branch `test-target/main` を持つ worktree を作成する。

## 引数

| 引数 | 値 | デフォルト | 説明 |
|---|---|---|---|
| `--mode` | `local` \| `real-issues` | `local` | 動作モード |
| `--repo` | `<owner>/<name>` | — | `--mode real-issues` 時必須。専用 GitHub リポ |

## 前提

- `test-fixtures/minimal-plugin/` が存在すること
- 現在の cwd がプロジェクトルート（bare repo の worktree 配下）であること

## 処理フロー（MUST）

### Step 0: 引数パース

```bash
MODE="local"  # default
REPO=""

# 引数解析（--mode と --repo を抽出）
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# --mode real-issues 時の --repo 必須チェック
if [[ "$MODE" == "real-issues" && -z "$REPO" ]]; then
  echo "Error: --mode real-issues requires --repo <owner>/<name>" >&2
  exit 1
fi

# --repo フォーマット検証（コマンドインジェクション防止）
if [[ -n "$REPO" ]]; then
  if ! [[ "$REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: --repo の値が不正です。'<owner>/<name>' 形式で英数字・ハイフン・アンダースコア・ドットのみ使用できます。" >&2
    exit 1
  fi
fi
```

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

### Step 3: リポ検証（--mode real-issues のみ）

`--mode local` の場合はこの Step をスキップして Step 4 へ。

#### Step 3a: リポ存在確認

```bash
gh repo view "$REPO" --json name 2>/dev/null && REPO_EXISTS=true || REPO_EXISTS=false
```

#### Step 3b: 既存リポの場合 — 空リポ検証 + パーミッション確認

`REPO_EXISTS=true` の場合:

```bash
# 空リポ検証（コミット数 == 0 かつブランチ数 <= 1）
COMMIT_COUNT=$(gh api "repos/$REPO/commits" --paginate --jq '. | length' 2>/dev/null || echo "0")
BRANCH_COUNT=$(gh api "repos/$REPO/branches" --jq '. | length' 2>/dev/null || echo "0")

if [[ "$COMMIT_COUNT" -gt 0 ]]; then
  echo "Error: リポ '$REPO' は空ではありません（コミット数: $COMMIT_COUNT）。空リポを指定してください。" >&2
  exit 1
fi

if [[ "$BRANCH_COUNT" -gt 1 ]]; then
  echo "Error: リポ '$REPO' は空ではありません（ブランチ数: $BRANCH_COUNT）。ブランチが 1 以下の空リポを指定してください。" >&2
  exit 1
fi

# push パーミッション確認
PUSH_ACCESS=$(gh api "repos/$REPO" --jq '.permissions.push' 2>/dev/null || echo "false")
if [[ "$PUSH_ACCESS" != "true" ]]; then
  echo "Error: リポ '$REPO' への push パーミッションがありません。権限を確認してください。" >&2
  exit 1
fi
```

#### Step 3c: 存在しないリポの場合 — 自動作成

`REPO_EXISTS=false` の場合:

```bash
OWNER="${REPO%%/*}"

# 1回の実行で stderr をキャプチャしてエラー種別判定
CREATE_ERR=$(gh repo create "$REPO" --private --no-readme 2>&1 1>/dev/null) && CREATE_OK=true || CREATE_OK=false

if [[ "$CREATE_OK" != "true" ]]; then
  # エラー種別判定（生メッセージは表示しない）
  if echo "$CREATE_ERR" | grep -qi "already exists\|name already"; then
    echo "Error: リポ '$REPO' は既に存在します（名前衝突）。別の名前を指定してください。" >&2
  elif echo "$CREATE_ERR" | grep -qi "rate limit\|too many requests"; then
    echo "Error: GitHub API rate limit に達しました。しばらく待ってから再試行してください。" >&2
  elif echo "$CREATE_ERR" | grep -qi "permission\|forbidden\|unauthorized"; then
    echo "Error: リポ '$REPO' を作成する権限がありません（owner: $OWNER）。" >&2
  else
    echo "Error: リポ '$REPO' の作成に失敗しました。詳細はシステムログを確認してください。" >&2
  fi
  exit 1
fi
echo "✓ リポ '$REPO' を作成しました（private / empty）"
```

### Step 4: orphan branch 作成 + worktree 追加

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

### Step 5: README 自動配置

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

### Step 6: 初回 commit + tag

```bash
cd "$BARE_ROOT/worktrees/test-target"
git add -A
git commit -m "test-target: initial scaffold from minimal-plugin"
git tag test-target/initial
```

### Step 7: .test-target/config.json 生成

```bash
INIT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
WORKTREE_PATH="$BARE_ROOT/worktrees/test-target"

if [[ "$MODE" == "real-issues" ]]; then
  # jq --arg でパラメータ化してJSONインジェクションを防止
  jq -n \
    --arg mode "real-issues" \
    --arg repo "$REPO" \
    --arg initialized_at "$INIT_TIME" \
    --arg worktree_path "$WORKTREE_PATH" \
    --arg branch "test-target/main" \
    '{"mode": $mode, "repo": $repo, "initialized_at": $initialized_at, "worktree_path": $worktree_path, "branch": $branch}' \
    > "$WORKTREE_PATH/.test-target/config.json"
else
  jq -n \
    --arg mode "local" \
    --arg initialized_at "$INIT_TIME" \
    --arg worktree_path "$WORKTREE_PATH" \
    --arg branch "test-target/main" \
    '{"mode": $mode, "repo": null, "initialized_at": $initialized_at, "worktree_path": $worktree_path, "branch": $branch}' \
    > "$WORKTREE_PATH/.test-target/config.json"
fi

cd "$WORKTREE_PATH"
git add .test-target/config.json
git commit -m "test-target: add .test-target/config.json (mode=$MODE)"
```

### Step 8: リモート紐付け（--mode real-issues のみ）

`--mode local` の場合はこの Step をスキップして Step 9 へ。

```bash
cd "$BARE_ROOT/worktrees/test-target"
git remote add origin "https://github.com/$REPO.git"
git push -u origin test-target/main
echo "✓ test-target worktree を '$REPO' に紐付けました"
```

### Step 9: JSON 出力

```json
{
  "status": "created",
  "mode": "<MODE>",
  "path": "<worktree path>",
  "branch": "test-target/main",
  "commit": "<commit hash>",
  "tag": "test-target/initial",
  "repo": "<REPO or null>",
  "issue_count": 0
}
```

## 禁止事項（MUST NOT）

- main branch に test-target 関連の commit を作成してはならない
- `--mode local` では `git push` してはならない（init はローカル操作のみ）
- `--mode real-issues` と `--mode local` は相互排他。両方同時に指定してはならない
