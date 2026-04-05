## Why

autopilot worker の chain で、LLM 判断が不要な機械的ステップ（GraphQL 呼び出し、ファイル存在チェック、テスト実行など）にも LLM がコンテキストを消費している。設計哲学「LLM は判断のために使う。機械的にできることは機械に任せる」に反する。

## What Changes

- chain-runner.sh を新設し、11 の機械的ステップを bash で直接実行
- workflow SKILL.md の chain 実行指示を runner 呼び出しに置換
- deps.yaml scripts セクションへ chain-runner.sh を登録
- 既存 command.md は手動実行パスとして維持

## Capabilities

### New Capabilities

- chain-runner.sh: ステップ名を引数に受け取り、対応する処理を bash で実行するスタンドアロンスクリプト
- Worker は機械的ステップの command.md を Read せず、runner 経由で実行可能

### Modified Capabilities

- workflow-setup / workflow-test-ready / workflow-pr-cycle の SKILL.md: 機械的ステップを runner 呼び出しに置換
- 手動実行パス（non-autopilot）は既存 command.md が引き続き動作

## Impact

- 対象ファイル: scripts/chain-runner.sh（新規）、skills/workflow-setup/SKILL.md、skills/workflow-test-ready/SKILL.md、skills/workflow-pr-cycle/SKILL.md、deps.yaml
- 機械的ステップ 11 個: init, board-status-update, ac-extract, ts-preflight, pr-test, all-pass-check, arch-ref, change-id 解決, worktree-create, pr-cycle-report（構造化集約）, 条件チェック
- LLM 判断を含むステップ（crg-auto-build, post-fix-verify, opsx-propose 等）は対象外
