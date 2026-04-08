---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 30
---
# Pilot 介入 Rebase (atomic)

並列 Worker rebase 必要時の Pilot 介入手順を atomic 化。
不変条件 F (Worker による merge 失敗時 rebase 禁止) との矛盾を避けるため、限定された trigger 条件でのみ起動可能。

## 入力

| 変数 | 説明 |
|------|------|
| `$ISSUE_NUM` | 対象 Issue 番号 |
| `$BRANCH_NAME` | 対象ブランチ名 |
| `$WORKTREE_DIR` | worktree ディレクトリパス |

## opt-out

```bash
if [ "${PILOT_ACTIVE_REVIEW_DISABLE:-0}" = "1" ]; then
  echo "WARN: PILOT_ACTIVE_REVIEW_DISABLE=1 — autopilot-pilot-rebase をスキップ" >&2
  exit 0
fi
```

## Trigger 条件 (MUST — 以下のいずれかを満たす場合のみ起動可能)

1. autopilot-pilot-precheck が WARN (high-deletion) を出した直後
2. mergegate.py が base drift detected で停止 (#166 連携)
3. autopilot-orchestrator が並列 Worker 同時 spawn 中の base 進行を検出

上記以外の状況では本 atomic を呼び出してはならない。

## 不変条件 F との関係

不変条件 F「merge 失敗時 rebase 禁止」は **Worker** に対する制約。本 atomic は **Pilot** が trigger 条件下で実行するため、不変条件 F とは矛盾しない。ただし `spawnable_by: [controller]` により Worker からの直接呼び出しは不可。

設計原則 P1 (ADR-010): Pilot 能動評価は atomic 経由に限定。

## 処理ロジック (MUST)

### Step 1: fetch

```bash
cd "$WORKTREE_DIR" || { echo "ERROR: worktree ディレクトリが存在しない: $WORKTREE_DIR" >&2; exit 1; }
git fetch origin main
echo "INFO: [pilot-rebase] Issue #${ISSUE_NUM} branch=${BRANCH_NAME} fetch 完了" >&2
```

### Step 2: rebase

```bash
if ! git rebase origin/main 2>/tmp/pilot-rebase-stderr.txt; then
  # conflict 数をカウント
  CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)

  if [ "$CONFLICT_FILES" -ge 4 ]; then
    git rebase --abort
    echo "ERROR: [pilot-rebase] Issue #${ISSUE_NUM}: conflict ${CONFLICT_FILES} ファイル (>= 4) — abort + Pilot ユーザー判断にエスカレーション" >&2
    exit 2
  fi

  # conflict 1-3 ファイル: LLM 判断で resolve
  echo "INFO: [pilot-rebase] Issue #${ISSUE_NUM}: conflict ${CONFLICT_FILES} ファイル — LLM 判断で resolve を試行" >&2
  # LLM がここで conflict marker を読んで resolve する
  # resolve 後: git add <files> && git rebase --continue
fi
```

### Step 3: push

```bash
git push --force-with-lease origin "$BRANCH_NAME"
echo "INFO: [pilot-rebase] Issue #${ISSUE_NUM} branch=${BRANCH_NAME} push 完了 (force-with-lease)" >&2
```

### Step 4: 再 verify

rebase 完了後、呼び出し元が autopilot-pilot-precheck の再実行 or merge-gate 再チェックを判断する。

## 出力

- stderr に rebase 過程を出力 (監査性)
- exit 0: rebase 成功
- exit 2: conflict 4 ファイル以上で abort (Pilot ユーザー報告が必要)

## 禁止事項 (MUST NOT)

- `git push --force` を使用してはならない (`--force-with-lease` 必須)
- conflict 4 ファイル以上を自動 resolve してはならない (abort + Pilot ユーザー判断にエスカレーション)
- Worker から呼び出してはならない (`spawnable_by: [controller]`)
- trigger 条件を満たさない状況で呼び出してはならない
