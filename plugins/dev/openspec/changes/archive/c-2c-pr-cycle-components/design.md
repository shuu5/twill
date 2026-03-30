## Context

C-2a で Issue/Project/Architect/Plugin 管理系 + OpenSpec/汎用系（計 42 コンポーネント）、C-2b で Setup/Workflow-setup 系（11 コンポーネント）を移植済み。残る PR サイクル関連 6 コンポーネントを移植し、全 18 コンポーネントを揃える。

既存 12 コンポーネントは deps.yaml v3.0 に登録済みで COMMAND.md も作成済み。旧プラグイン（claude-plugin-dev）のフラットファイル構造（`commands/xxx.md`）から新プラグインのディレクトリ構造（`commands/xxx.md`）へ変換する。

chain-driven + autopilot-first 設計により、旧プラグインの `--auto-merge` フラグ分岐・環境変数チェック・マーカーファイル管理は除去する。

## Goals / Non-Goals

**Goals:**

- 6 コンポーネントの COMMAND.md 新規作成（ac-deploy-trigger, test-phase, auto-merge, pr-cycle-analysis, schema-update, spec-diagnose）
- 6 コンポーネントの deps.yaml v3.0 エントリ追加
- auto-merge を autopilot-first 前提で簡素化（merge-gate の呼び出し先）
- 旧 --auto-merge 関連コードの除去
- loom validate pass

**Non-Goals:**

- merge-gate 本体の実装（B-5 スコープ）
- 既存 12 コンポーネントの COMMAND.md 内容変更
- chain 定義の変更（既に B-5 で確定済み）
- pr-test, merge-gate の変更（別 Issue スコープ）

## Decisions

### D1: auto-merge の簡素化

旧プラグインの auto-merge は `--auto-merge` フラグ分岐・パイロット制御ガード・マーカーファイル管理を持つ。autopilot-first 設計では:

- merge-gate が PASS 判定後に auto-merge を呼び出す
- 状態管理は issue-{N}.json + state-write.sh に一元化
- パイロット制御ガード・マーカーファイルは不要
- squash merge → archive → cleanup の実行のみに集中

### D2: test-phase の位置づけ

旧 test-phase は composite として pr-test + e2e-quality を統合していた。新設計では:

- pr-cycle chain に `pr-test` が直接ステップとして存在（Step 3）
- test-phase は chain 外のスタンドアロンコマンドとして残す
- workflow-pr-cycle からは chain step の pr-test を直接使用
- test-phase は手動テスト実行やデバッグ用途で独立利用可能

### D3: chain 外コンポーネントの配置

6 コンポーネントのうち chain step に入るものはない（既に chain は確定済み）:

| コンポーネント | 配置 | 呼び出し元 |
|---|---|---|
| ac-deploy-trigger | chain 外 standalone | workflow-pr-cycle から直接 |
| test-phase | chain 外 standalone | 手動 or composite 内 |
| auto-merge | chain 外 standalone | merge-gate から呼び出し |
| pr-cycle-analysis | chain 外 standalone | workflow-pr-cycle Step 7.3 |
| schema-update | chain 外 standalone | 手動実行 |
| spec-diagnose | chain 外 standalone | fix-phase から条件付き呼び出し |

### D4: deps.yaml の calls 関係

- merge-gate → calls: auto-merge（既存 merge-gate に calls 追加）
- workflow-pr-cycle → calls に ac-deploy-trigger, ac-verify, pr-cycle-analysis を追加

## Risks / Trade-offs

- **auto-merge の簡素化リスク**: 旧プラグインのパイロット制御ガードを除去するが、autopilot-first 設計では merge-gate が制御を担うため問題なし
- **test-phase の chain 外配置**: pr-cycle chain では pr-test が直接使われるため test-phase は冗長に見えるが、デバッグ・手動実行用途で残す価値がある
- **schema-update の汎用性**: webapp-hono 専用だが、将来的にコンパニオンプラグインへの移動を検討
