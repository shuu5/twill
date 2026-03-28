# 自動マージ実行（autopilot-first）

merge-gate から呼び出され、squash マージ → archive → cleanup を実行する。
autopilot-first 前提で設計。状態管理は issue-{N}.json + state-write.sh に一元化。

## 実行ロジック（MUST）

### Step 1: squash マージ

```bash
gh pr merge --squash --delete-branch
```

マージ失敗時（コンフリクト等）:
- 停止のみ。自動 rebase は試みない（MUST NOT）
- issue-{N}.json の status を failed に遷移

### Step 2: archive（OpenSpec change 存在時）

```bash
git checkout main && git pull origin main
```

OpenSpec change が存在する場合:
```bash
CHANGE_ID=$(ls openspec/changes/ 2>/dev/null | grep -v archive | head -1)
if [ -n "${CHANGE_ID}" ]; then
  deltaspec archive "${CHANGE_ID}" --yes --skip-specs
fi
```

archive 失敗時: 警告をログに記録するが処理は続行（マージは完了済みのため）。
OpenSpec 未使用時: archive ステップをスキップ。

### Step 3: cleanup

REPO_MODE による分岐:

```bash
if [ "${REPO_MODE}" = "standard" ]; then
  git branch -d "${BRANCH}"
else
  WORKTREE_PATH=$(git rev-parse --show-toplevel)
  MAIN_WORKTREE=$(git worktree list | grep '\[main\]' | awk '{print $1}')
  cd "${MAIN_WORKTREE}"
  git worktree remove "${WORKTREE_PATH}" 2>/dev/null || true
  git branch -d "${BRANCH}" 2>/dev/null || true
fi
```

cleanup 失敗時: 警告を出力するが処理は続行。

### Step 4: 完了

issue-{N}.json の status を done に遷移。

## 禁止事項（MUST NOT）

- マージ失敗時に自動 rebase を試みてはならない
- cleanup 失敗で処理全体を停止してはならない
