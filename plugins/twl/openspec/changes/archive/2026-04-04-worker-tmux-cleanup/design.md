## Context

autopilot Worker 完了後のクリーンアップ責務が `merge-gate-execute.sh` のマージ成功パスにのみ実装されており、以下のケースで tmux window とリモートブランチが残存する:

- 手動 merge / Worker 直接 merge → `merge-gate-execute.sh` の default パスを経由しない
- `--reject` / `--reject-final` → `state=failed` は設定するが `tmux kill-window` なし
- poll タイムアウト → orchestrator が `state=failed` を書き込むが cleanup なし
- `poll_single` / `poll_phase` の done/failed 検知後 → `return 0` / `continue` のみ

また `remain-on-exit on` の設定（不変条件 G: クラッシュ検知保証）により、プロセス終了だけでは window が残存するため、明示的な `tmux kill-window` が必須。

## Goals / Non-Goals

**Goals:**
- orchestrator の poll_single / poll_phase で done/failed 検知時に tmux window を kill する
- merge-gate-execute.sh の reject パスに tmux window kill を追加する
- poll タイムアウト時にも tmux window を kill する
- orchestrator で done 検知した場合はリモートブランチも削除する

**Non-Goals:**
- `auto-merge.sh` の変更（スコープ外）
- `co-autopilot SKILL.md` の window 管理記述更新（不要と判断）
- 不変条件 G（remain-on-exit on）の変更

## Decisions

### 1. cleanup ヘルパー関数を orchestrator に追加

`poll_single` / `poll_phase` / タイムアウト処理で共通の cleanup が必要なため、`cleanup_worker()` 関数を orchestrator に追加する。

```bash
cleanup_worker() {
  local issue="$1"
  local window_name="ap-#${issue}"
  # tmux window kill
  tmux kill-window -t "$window_name" 2>/dev/null || true
  # リモートブランチ削除（branch が state に記録されている場合のみ）
  local branch
  branch=$(bash "$SCRIPTS_ROOT/state-read.sh" --type issue --issue "$issue" --field branch 2>/dev/null || echo "")
  if [[ -n "$branch" ]]; then
    git push origin --delete "$branch" 2>/dev/null || true
  fi
}
```

ブランチ名は `state-read.sh --field branch` で取得。`run_merge_gate` と同じアプローチ。

### 2. poll_single の done/failed 時に cleanup_worker を呼ぶ

```bash
done)
  cleanup_worker "$issue"
  return 0 ;;
failed)
  cleanup_worker "$issue"
  return 0 ;;
```

merge-ready の場合は `run_merge_gate` が後続で cleanup するため、cleanup_worker は不要。

### 3. poll_phase の done/failed 時に cleanup_worker を呼ぶ

poll_phase は `continue` のみで次の issue に移っていたが、初回検知時のみ cleanup を実行するよう制御する。

done/failed を初回検知したタイミングで `cleanup_worker` を呼ぶ。再ポーリング時の重複実行は `tmux kill-window` のべき等性（存在しなければ失敗→握りつぶし）で対応。

### 4. タイムアウト時にも cleanup_worker を呼ぶ

poll_phase のタイムアウトループ（L319-329）で `state=failed` を設定した後に `cleanup_worker "$issue"` を追加。

### 5. merge-gate-execute.sh の reject パスに kill-window を追加

`--reject` と `--reject-final` の state-write 後に:
```bash
tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true
```
を追加。

## Risks / Trade-offs

- **二重 kill-window**: done/failed が複数パスで検知される場合（例: orchestrator + merge-gate）、`tmux kill-window` が複数回呼ばれる可能性がある。ただし `|| true` により無害。
- **remote branch delete の副作用**: orchestrator の cleanup_worker がリモートブランチを削除した後、merge-gate が再度削除しようとすることがある。merge-gate の削除失敗は既に `⚠️ 警告+続行` で対応済みのため影響なし。
- **branch 未設定の場合**: state に branch が記録されていない場合は削除をスキップ。手動 merge などで branch が消えている場合も安全。
