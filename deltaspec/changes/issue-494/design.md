## Context

`chain-runner.sh` の `step_all_pass_check()` は L1024-1035 で `status=merge-ready` を書き込むが、`workflow_done=pr-merge` を書いていない。`autopilot-orchestrator.sh` は `workflow_done` が存在しない場合に `non_terminal_chain_end` を検知し、不正な再実行を引き起こす可能性がある。

現在の状態書き込みコマンド（L1028）:
```bash
python3 -m twl.autopilot.state write ... --set "status=merge-ready" --set "pr=$_cr_pr" --set "branch=$_cr_branch"
```

修正後:
```bash
python3 -m twl.autopilot.state write ... --set "status=merge-ready" --set "workflow_done=pr-merge" --set "pr=$_cr_pr" --set "branch=$_cr_branch"
```

## Goals / Non-Goals

**Goals:**
- `step_all_pass_check()` が merge-ready 書き込み時に必ず `workflow_done=pr-merge` も書くよう修正する
- smoke テストで正常終了後の state に `workflow_done=pr-merge` が書かれることを確認する
- SKILL.md 側の LLM 指示（`workflow-pr-merge/SKILL.md` L118 付近）と値の整合を維持する

**Non-Goals:**
- `worker-terminal-guard.sh` の変更
- `workflow_done` のステージ値の新規追加
- SKILL.md 側の LLM 指示の削除（後方互換として残す）

## Decisions

1. **変更箇所は L1028 の state write コマンドのみ**: `--set "workflow_done=pr-merge"` を既存の `--set "status=merge-ready"` と同一コマンド内に追加する。アトミックに書き込むことで、partial write を回避できる。

2. **失敗時 (L1038) は変更なし**: `status=failed` 書き込み時は `workflow_done` を書かない。issue の AC 定義と一致。

3. **smoke テストの追加**: `test-fixtures/` 配下に `all-pass-check` smoke テストを追加し、`workflow_done=pr-merge` が書かれることを自動確認する。

4. **SSOT 確立**: script 側が `workflow_done` の書き込み決定権を持つ。SKILL.md 側の書き込みと値が一致するため二重書き込みでも不一致は発生しない。

## Risks / Trade-offs

- **リスクなし**: 既存コマンドへの `--set` 引数追加のみで、他の state フィールドへの副作用はない
- **後方互換**: `workflow_done` フィールドを新たに書くだけで、読み取り側 (`autopilot-orchestrator.sh`) は既存の `non_terminal_chain_end` チェックで正常動作するようになる
