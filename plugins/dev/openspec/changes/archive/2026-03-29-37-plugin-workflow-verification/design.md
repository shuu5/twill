## Context

loom-plugin-dev は全 Issue 実装完了（17 子 + 2 親）。switchover.sh（C-6）で symlink 切替の仕組みも整備済み。loom#44（chain CLI ラッパー）と loom#45（chain generate Template C）もマージ済みで、SKILL.md 再生成の基盤が整っている。

テストプロジェクト loom-plugin-test は bare repo + worktree 構成で既に存在する。`--plugin-dir` は旧 dev と新 dev が同名（"dev"）で衝突するため使用不可。switchover.sh switch による symlink 一時切替で検証する。

## Goals / Non-Goals

**Goals:**

- loom chain generate --write --all で SKILL.md を最新化
- switchover.sh switch で symlink を loom-plugin-dev に切替
- loom-plugin-test で workflow-setup を実行し自律完了を確認
- loom-plugin-test で workflow-pr-cycle を実行し自律完了を確認
- 発見された軽微な問題をその場で修正
- 検証レポートを作成
- switchover.sh rollback で旧プラグインに復元

**Non-Goals:**

- co-autopilot の検証（S3 はオプション、本 change では実施しない）
- 既存プロジェクト（loom-plugin-dev 自身等）での検証
- symlink の永続切替（retire）

## Decisions

1. **検証手法**: switchover.sh switch を使用。--plugin-dir は名前衝突で不可（旧 dev と新 dev が同名）
2. **SKILL.md 再生成**: loom chain generate --write --all を switchover 前に loom-plugin-dev worktree 内で実行。chain 定義から Template C で starter 指示を注入
3. **検証順序**: SKILL.md 再生成 → switchover check → switch → テスト Issue 作成 → workflow-setup → pr-cycle → rollback
4. **修正方針**: 軽微な問題（typo、パス不整合等）はその場で修正しコミット。重大な問題は別 Issue で追跡

## Risks / Trade-offs

- **symlink 切替中のリスク**: 検証中は旧プラグインが無効化される。rollback で即時復元可能だが、検証中に別セッションで旧プラグインを使えない
- **テストプロジェクトの制約**: loom-plugin-test は最小構成のため、実際のプロジェクト（多数の Issue、複雑な deps.yaml）とは検証範囲が異なる
- **chain generate の副作用**: 全 SKILL.md を上書きするため、手動編集があった場合は失われる（chain 定義が SSOT なので問題なし）
