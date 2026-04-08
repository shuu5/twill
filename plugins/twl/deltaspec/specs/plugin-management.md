# Plugin Management

workflow-plugin-create と workflow-plugin-diagnose によるプラグイン作成・診断ワークフローを定義するシナリオ。co-project の plugin-create / plugin-diagnose モードから委譲される。

## Scenario: プラグイン作成ワークフロー正常実行

- **WHEN** workflow-plugin-create が実行される
- **THEN** plugin-interview で要件がヒアリングされる（名前・目的・ワークフロー分割・AT 並列タスク要否等）
- **AND** plugin-research で AT 仕様・Claude Code 設定仕様の最新ドキュメントが取得される
- **AND** plugin-design で要件が 6 型にマッピングされ deps.yaml ドラフトが生成される
- **AND** ユーザー確認後に plugin-generate でファイル一式が生成される
- **AND** `twl validate` / `twl audit` の通過が確認される

## Scenario: プラグイン診断ワークフロー正常実行

- **WHEN** workflow-plugin-diagnose が実行される
- **THEN** plugin-migrate-analyze で旧 guide-patterns からの移行が分析される（該当時のみ）
- **AND** plugin-diagnose で構造検証・frontmatter 整合性・5 原則チェック・orphan 検出が実行される
- **AND** plugin-phase-diagnose で worker-structure・worker-principles・worker-architecture が並列診断される
- **AND** plugin-fix で診断結果に基づく修正が適用される
- **AND** plugin-verify で修正後の統合検証（PASS/FAIL 判定）が実行される
- **AND** FAIL 時は plugin-fix に戻る
- **AND** plugin-phase-verify で並列検証が実行され全 worker PASS で完了する

## Scenario: AT 移行分析スキップ

- **WHEN** 既存プラグインが旧 guide-patterns 準拠でない場合
- **THEN** plugin-migrate-analyze はスキップされ Step 2（plugin-diagnose）から開始される

## Scenario: 診断の並列 specialist 実行

- **WHEN** plugin-phase-diagnose が実行される
- **THEN** worker-structure・worker-principles・worker-architecture が並列起動される
- **AND** 構造・品質・アーキテクチャが同時に診断される

## Scenario: 修正→検証のループ

- **WHEN** plugin-verify が FAIL を返す
- **THEN** plugin-fix に戻り問題が再修正される
- **AND** 再度 plugin-verify で検証される

## Scenario: プラグイン生成の成果物

- **WHEN** plugin-generate が完了する
- **THEN** ディレクトリ構造・plugin.json・deps.yaml が生成される
- **AND** 各コンポーネントファイル（controller/workflow/phase/worker/atomic/reference）が生成される
- **AND** Context Snapshot / Subagent Delegation インフラが該当時に生成される
- **AND** README.md + SVG 依存関係図が生成される
