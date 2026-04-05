## Why

loom-plugin-dev の全 17 Issue + 2 Parent が実装完了し、テストスイート（C-5）とスイッチオーバー手順（C-6）も整備済み。しかし、実際のプロジェクトでワークフローを端から端まで通した検証がまだ行われていない。switchover.sh switch でプラグインを一時切替し、テストプロジェクト loom-plugin-test で主要ワークフローを検証することで、本番切替前のリスクを低減する。

## What Changes

- `loom chain generate --write --all` で全 SKILL.md を最新の chain 定義から再生成
- switchover.sh switch で ~/.claude/plugins/dev symlink を loom-plugin-dev に一時切替
- テストプロジェクト loom-plugin-test で workflow-setup → pr-cycle を実行
- 発見された軽微な問題をその場で修正
- 検証完了後 switchover.sh rollback で旧プラグインに復元
- 検証レポートを作成

## Capabilities

### New Capabilities

- テストプロジェクトでのエンドツーエンド ワークフロー検証手順の確立

### Modified Capabilities

- SKILL.md の chain generate Template C による再生成（loom#45 で追加済みの機能を適用）

## Impact

- 影響範囲: ~/.claude/plugins/dev symlink（検証中のみ一時変更、rollback で即時復元可能）
- テストプロジェクト: loom-plugin-test（検証用 Issue 作成、worktree 作成）
- 依存: loom#44（chain CLI ラッパー）、loom#45（chain generate Template C）— いずれもマージ済み
