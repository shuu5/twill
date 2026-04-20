## Context

bare repo 構造（`.bare/` + `main/` worktree + `worktrees/feat/*`）では、`git worktree add` が `remote.origin.fetch` refspec を継承しないケースがある。refspec が `+refs/heads/*:refs/remotes/origin/*` でない場合、`git fetch origin` は HEAD のみ更新し `refs/remotes/origin/main` が stale になる。現在は手動修復済みだが、再発時の detection コストが高い（Wave 4 で 1 時間を要した）。

既存スクリプト:
- `plugins/twl/scripts/chain-runner.sh` — worktree-create ステップが `twl.autopilot.worktree` に委譲
- `plugins/twl/commands/autopilot-pilot-precheck.md` — PR merge 直前の軽量検証 atomic
- `plugins/twl/CLAUDE.md` — bare repo 構造検証（現行 3 条件）
- `plugins/twl/scripts/health-check.sh` — ロジック異常検知（chain 停止・input wait）、refspec 検査は未実装

## Goals / Non-Goals

**Goals:**
- `.bare/config`・main worktree・全 feat worktree の `remote.origin.fetch` を一括検査するスタンドアローンスクリプトを追加
- refspec 欠落時に警告 + 自動修復（`git config --add`）を提供
- autopilot セッション起動時（pilot-precheck）に refspec チェックを組み込む
- worktree 作成直後に refspec を自動設定する
- bats テストで「refspec 欠落 worktree の検出」を機械的に保証
- `plugins/twl/CLAUDE.md` に refspec を第 4 条件として明文化

**Non-Goals:**
- `remote.origin.fetch` 以外の git 設定全般の健全性検証
- GitHub Actions / CI への組み込み
- 既存の `health-check.sh`（ロジック異常検知）との統合（責務が異なる）

## Decisions

### D-1: 新規スクリプト `worktree-health-check.sh`

`health-check.sh` とは**責務分離**（chain/process 監視 vs git refspec 監視）。命名を `worktree-health-check.sh` とし独立させる。引数: `[--fix]`（自動修復モード）、`[--bare-root <path>]`（bare repo パス指定）。

検査順:
1. bare repo root の `.bare/config` を確認
2. `main/` worktree を確認
3. `git worktree list --porcelain` で全 worktree を列挙して確認
4. `git show-ref refs/remotes/origin/main` と `git ls-remote origin main` の tip 比較

出口コード: `0` = 全 OK、`1` = 問題あり（`--fix` なし）、`0` = 問題あり + 修復済み（`--fix` あり）

### D-2: autopilot-pilot-precheck への統合

precheck の既存 Step（PR diff stat / AC spot-check）の**前**に Step 0 として refspec チェックを追加。`--fix` フラグなしで呼び出し、欠落を検出したら `PRECHECK_WARNINGS` に追加して処理を継続（abort しない）。

### D-3: worktree-create での refspec 自動設定

`chain-runner.sh` の `step_worktree_create()` で `python3 -m twl.autopilot.worktree create` 完了後に以下を実行:
```bash
git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' || true
```
既存 refspec が正しい場合は上書きせず（`--get-all` で確認してから `--add`）。

### D-4: bats テスト

`test-fixtures/` 配下に bats テストを追加（既存パターンに倣う）。
- `setup()`: 一時 bare repo + worktree を作成し、refspec を意図的に削除
- `@test`: `worktree-health-check.sh` が exit 1 + WARN メッセージを出力することを検証
- `@test --fix`: `worktree-health-check.sh --fix` 後に refspec が正しく設定されていることを検証

## Risks / Trade-offs

- **`git ls-remote origin main` はネットワーク接続を要する**: precheck での tip 比較は optional とし、ネットワーク不可環境では skip する（タイムアウト 5 秒）
- **全 worktree の列挙コスト**: `git worktree list --porcelain` は軽量だが、worktree 数が多い環境では若干遅い。許容範囲と判断
- **`--add` と `--replace-all` の選択**: `git config --add` は重複エントリを生む可能性がある。`git config --replace-all` を使い、既存 refspec を置き換える方が安全
