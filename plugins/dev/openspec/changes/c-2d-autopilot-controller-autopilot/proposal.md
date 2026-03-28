## Why

co-autopilot controller が参照する 11 個の autopilot コンポーネントが未移植のため、autopilot ワークフローが実行不能。旧プラグインではマーカーファイル (.done/.fail/.merge-ready) と DEV_AUTOPILOT_SESSION 環境変数で状態管理していたが、B-3 で統一状態ファイル (issue-{N}.json / session.json) とスクリプト群 (state-read.sh / state-write.sh) が導入済み。これらを活用する形で全 11 コンポーネントを移植する。

## What Changes

- 11 個のコマンドを `commands/` 配下に COMMAND.md 形式で新規作成
  - セッション管理: autopilot-init, autopilot-launch, autopilot-poll
  - Phase 実行: autopilot-phase-execute, autopilot-phase-postprocess
  - 後処理/分析: autopilot-collect, autopilot-retrospective, autopilot-patterns, autopilot-cross-issue
  - サマリー/監査: autopilot-summary, session-audit
- 全コンポーネントのマーカーファイル参照を state-read.sh / state-write.sh 呼び出しに置換
- DEV_AUTOPILOT_SESSION 環境変数参照を state-read.sh --type session での状態確認に置換
- deps.yaml に 11 コマンドを追加し co-autopilot controller の calls を更新
- co-autopilot SKILL.md を更新し、新コマンドへの呼び出しフローを反映

## Capabilities

### New Capabilities

- autopilot-init: .autopilot/ 初期化 + session.json 作成（autopilot-init.sh / session-create.sh ラッパー）
- autopilot-launch: tmux window 作成 + Worker 起動（state-write で issue status=running 初期化）
- autopilot-poll: state-read による Issue 状態ポーリング + crash-detect.sh 連携
- autopilot-phase-execute: Phase 内 Issue ループ（launch → poll → merge-gate → window 管理）
- autopilot-phase-postprocess: Phase 後処理チェーン（collect → retrospective → patterns → cross-issue）
- autopilot-collect: PR 差分からの変更ファイル収集 → session.json 保存
- autopilot-retrospective: Phase 振り返り分析 → phase_insights 更新
- autopilot-patterns: 繰り返しパターン検出 → self-improve Issue 起票
- autopilot-cross-issue: 変更ファイル競合分析 → session-add-warning.sh 経由で警告追記
- autopilot-summary: 全 Phase 完了サマリー → session-archive.sh でアーカイブ
- session-audit: セッション JSONL 事後分析 → 5 カテゴリ問題検出

### Modified Capabilities

- co-autopilot SKILL.md: calls セクションに 11 コマンドを追加、マーカーファイル/環境変数の参照を全削除

## Impact

- 変更対象: `commands/` (11 新規ディレクトリ), `deps.yaml`, `skills/co-autopilot/SKILL.md`
- 依存先: B-3 スクリプト群 (state-read.sh, state-write.sh, autopilot-init.sh, session-create.sh, session-archive.sh, session-add-warning.sh, crash-detect.sh)
- 依存元: autopilot 経由で実行される全ワークフロー（workflow-setup, workflow-pr-cycle）
- 9 件の不変条件 (#5) との整合性維持が必須
