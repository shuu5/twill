## Why

現行 workflow-pr-cycle は 108 行・8+ ステップの複雑なワークフローで、merge-gate は standard/plugin の 2 パスに分岐している。--auto-merge フラグが全層を透過し（旧 plugin で 35 箇所）、all-pass-check には DEV_AUTOPILOT_SESSION チェックが残る。B-4 で確立した chain-driven パターンを pr-cycle に適用し、機械的ルーティングを deps.yaml chains に移行、merge-gate を動的レビュアー構築による単一パスに統合する。

## What Changes

- deps.yaml に `pr-cycle` chain を定義し、ステップ順序を宣言的に管理する
- merge-gate の standard/plugin 2 パスを廃止し、PR diff から動的にレビュアーを構築する単一パスに統合する
- specialist 出力パーサーを実装し、共通出力スキーマ（ref-specialist-output-schema）に基づく機械的な結果集約を行う
- all-pass-check / auto-merge を autopilot-first 前提で簡素化し、--auto-merge 分岐コードを排除する
- 統一状態ファイル（issue-{N}.json）との連携で結果報告と状態遷移を一元化する
- workflow-pr-cycle SKILL.md を chain で表現できないドメインルール（merge-gate 判定基準、fix-phase エスカレーション条件）のみに縮小する

## Capabilities

### New Capabilities

- **pr-cycle chain 定義**: deps.yaml chains セクションで pr-cycle のステップ順序（verify → parallel-review → test → fix → post-fix-verify → visual → report → all-pass-check → merge）を宣言的に管理
- **動的レビュアー構築**: PR diff のファイルパス・拡張子から適用すべき specialist を自動決定。deps.yaml 変更時は worker-structure + worker-principles を追加、.tsx 変更時は worker-nextjs-reviewer を追加等
- **specialist 出力パーサー**: 共通スキーマ（status/findings[]）の正規表現パース。パース失敗時は出力全体を WARNING (confidence=50) として扱うフォールバック付き
- **merge-gate 単一パス**: standard/plugin の分岐を廃止し、動的レビュアーリストに基づく並列実行 → 結果集約 → PASS/REJECT 判定の統一フロー
- **merge-gate severity フィルタ**: `severity == CRITICAL && confidence >= 80` の機械的ブロック判定

### Modified Capabilities

- **workflow-pr-cycle SKILL.md 縮小**: chain で表現可能なステップ順序・条件分岐を排除し、merge-gate 判定ルール・fix-phase エスカレーション条件等のドメインルールのみに絞る
- **all-pass-check 簡素化**: --auto-merge 分岐と DEV_AUTOPILOT_SESSION チェックを廃止。統一状態ファイルの status フィールドで判定
- **結果報告の統一**: phase-review の結果統合を共通出力スキーマの構造化データに基づく機械的処理に変更（AI による自由形式の変換に依存しない）

## Impact

- **deps.yaml**: pr-cycle chain 追加、新規 atomic/composite コンポーネント登録（merge-gate, all-pass-check, pr-cycle-report 等）、各コンポーネントへの chain/step_in/calls フィールド追加
- **SKILL.md**: workflow-pr-cycle の大幅縮小、merge-gate の新規作成（ドメインルールのみ）
- **統一状態ファイル連携**: issue-{N}.json の status 遷移（running → merge-ready → done/failed）と merge-gate 結果の書き込み
- **specialist 層**: 出力形式の変更なし（ref-specialist-output-schema 準拠を前提）。消費側（パーサー）のみ新規実装
- **loom CLI 依存**: `loom chain validate` で pr-cycle chain の整合性を検証。loom#30 (--check/--all) があれば乖離検出も可能
- **不変条件**: Invariant C（Worker マージ禁止）、E（merge-gate リトライ最大 1 回）、F（rebase 禁止）を実装で遵守
