## Why

co-issue Phase 3b で並列 spawn される issue-critic / issue-feasibility specialist が、scope_files の多い Issue（4 ファイル以上）のレビュー時に maxTurns (15) を調査で使い切り、構造化 findings 出力を生成せずに完了する。9 specialist 中 4 件（44%）が構造化出力を返さず、Step 3c でサイレントに findings: [] として扱われていた。

## What Changes

- `agents/issue-critic.md`: scope_files >= 3 の場合の調査バジェット制御指示を追加（各ファイル 2-3 tool calls に制限、出力生成を最終 2-3 turns で確実に実施）
- `agents/issue-feasibility.md`: 同上
- `skills/co-issue/SKILL.md`: Phase 3b の specialist spawn プロンプトに scope_files 数依存の調査深度指示を追加、Step 3c に出力なし完了の検知 + WARNING 表示ロジックを追加

## Capabilities

### New Capabilities

- **scope_files 依存の調査深度制御**: co-issue Phase 3b で scope_files が 3 以上の場合、specialist の調査深度を自動的に制限するプロンプト指示を注入する
- **出力なし完了の検知と警告**: Step 3c で specialist の返却値に構造化 findings/status ブロックが含まれない場合を検知し、WARNING として findings テーブルに表示する

### Modified Capabilities

- **issue-critic / issue-feasibility の調査バジェット制御**: scope_files >= 3 の場合、各ファイルの調査を「ファイル存在確認 + 直接の呼び出し元 1 段」に留め、再帰的追跡を行わない
- **Step 3c の集約ロジック**: 出力なし specialist を findings: [] ではなく WARNING finding として扱い、ユーザーに通知する（Phase 4 は非ブロック）

## Impact

- **変更ファイル**: `agents/issue-critic.md`, `agents/issue-feasibility.md`, `skills/co-issue/SKILL.md`（既存コンポーネント内容変更のみ、新規ファイルなし）
- **deps.yaml**: 変更なし（新規コンポーネント追加なし）
- **影響範囲**: co-issue ワークフローのみ。worker-codex-reviewer および PR Cycle 系 reviewer は対象外
- **制限**: LLM の指示遵守に依存するため完全な保証はない。出力検知（アプローチ 3）が多層防御のフォールバックとして機能する
