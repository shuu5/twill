## Context

autopilot Worker が pr-cycle チェーンを完走した際、auto-merge.md が autopilot 配下かどうかを判定せず直接 `gh pr merge --squash` を実行する。また worktree モード時に Worker 自身が worktree を削除する。これにより issue-{N}.json の status が running のまま残り、Pilot のポーリングが完了を検知できない。

merge-gate-execute.sh にも CWD ガードがなく、worktrees/ 配下から実行された場合に不変条件B/C に違反する操作が可能。

## Goals / Non-Goals

**Goals:**

- auto-merge.md で autopilot 配下（issue-{N}.json status=running）を検出し、merge/worktree 削除をスキップして merge-ready 宣言のみ行う
- merge-gate-execute.sh に CWD ガードを追加し、worktrees/ 配下からの実行を拒否する
- all-pass-check.md で autopilot 配下の merge-ready 遷移を正しく行う

**Non-Goals:**

- `--auto`/`--auto-merge` フラグの廃止（#47 のスコープ）
- state-write.sh の構文修正・DCI 欠落対応（#54 のスコープ）
- 不変条件のテスト追加（別 Issue）

## Decisions

### D1: autopilot 配下判定パターン

`state-read.sh --type issue --issue "$ISSUE_NUM" --field status` で status を取得し、`running` なら autopilot 配下と判定する。ファイル不在や読み取りエラー時は空文字（= 非 autopilot）として扱う。

### D2: auto-merge.md の分岐

autopilot 配下の場合:
1. `state-write.sh --set "status=merge-ready"` で遷移宣言
2. merge、archive、worktree 削除を全てスキップ
3. 正常終了（Pilot が merge-gate を実行する）

非 autopilot の場合: 既存動作を維持（直接 merge → archive → cleanup）。

### D3: merge-gate-execute.sh の CWD ガード

worktree-delete.sh:33-35 と同一パターンを採用:
```bash
cwd=$(pwd)
if [[ "$cwd" == */worktrees/* ]]; then
  echo "ERROR: ..." >&2; exit 1
fi
```

スクリプト冒頭（環境変数バリデーション後、MODE 判定前）に配置。

### D4: all-pass-check.md の state-write 構文

現在の all-pass-check.md は旧形式（位置引数）で state-write.sh を呼んでいる。正しい named-argument 形式に修正:
```bash
bash scripts/state-write.sh --type issue --issue "$ISSUE_NUM" --role worker --set "status=merge-ready"
```

## Risks / Trade-offs

- **#54 との依存**: state-write.sh の構文が正しく動作することを前提とする。#54 が未修正の場合、state-write 呼び出しが失敗する可能性がある。ただし #58 側は正しい構文を使用するため、#54 修正後に自動的に動作する
- **autopilot 非配下での影響なし**: 判定は issue-{N}.json の存在と status=running に依存するため、手動実行時は既存動作に影響しない
