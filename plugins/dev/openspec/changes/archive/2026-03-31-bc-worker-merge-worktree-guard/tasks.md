## 1. merge-gate-execute.sh CWD ガード追加

- [x] 1.1 `scripts/merge-gate-execute.sh` のマージ実行モード（`*)`ケース）冒頭に CWD ガードを追加。`pwd` が `*/worktrees/*` に一致する場合は exit 1

## 2. auto-merge.md autopilot 配下判定

- [x] 2.1 `commands/auto-merge.md` に autopilot 配下判定ロジックを追加。`state-read.sh --type issue --issue "$ISSUE_NUM" --field status` で `running` なら merge/worktree 削除をスキップし、`state-write.sh` で merge-ready に遷移のみ

## 3. all-pass-check.md autopilot 配下 merge-ready 宣言

- [x] 3.1 `commands/all-pass-check.md` の PASS 判定後に autopilot 配下判定を追加。`running` なら `state-write.sh` で merge-ready に遷移

## 4. 検証

- [x] 4.1 `loom check` が PASS すること
- [x] 4.2 `loom validate` が PASS すること
