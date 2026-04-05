## Why

`architecture/` spec が実装と乖離し続けている。2026-03-27 以降 22 件以上の Issue が解決されたが spec は未反映であり、新概念（quick issue 等）が定義なしで運用され #145/#152/#154 のようなバグの根本原因分析を困難にしている。drift 検出は機械的に可能だが、現状そのメカニズムが存在しない。

## What Changes

- `skills/co-issue/SKILL.md`: Phase 1 完了後に Step 1.5（glossary 照合）を追加。`architecture/domain/glossary.md` の MUST terms と explore-summary.md の主要用語を照合し、未定義用語を INFO レベルで通知
- `agents/worker-architecture.md`: PR diff モードに drift 検出評価項目を追加。新状態値・未定義エンティティ・glossary 未登録用語を `severity: WARNING`, `category: architecture-drift` として報告
- `commands/autopilot-retrospective.md`: Step 4 直後に Step 4.5（architecture 差分チェック）を追加。変更ファイルと `architecture/` の対応確認・乖離候補リストを提示（自動 Issue 化なし）
- `deps.yaml`: worker-architecture の参照ファイルに `glossary.md`, `domain/model.md` 等を追加

## Capabilities

### New Capabilities

- **Glossary drift 通知**: co-issue Phase 1 完了時に architecture glossary との照合を実行し、未定義用語を検出する
- **PR diff drift 検出**: merge-gate で architecture-drift カテゴリの WARNING を生成する（マージはブロックしない）
- **Retrospective 乖離候補提示**: autopilot Phase 完了時に architecture 更新が必要な候補リストを提示する

### Modified Capabilities

- **co-issue Phase 1**: Step 1.5 を追加。`architecture/` 非存在時はスキップ
- **worker-architecture drift 評価**: PR diff から新状態値・未定義エンティティ・glossary 未登録用語を検出
- **autopilot-retrospective Step 4.5**: Phase 変更ファイルと architecture/ の対応をチェック

## Impact

| 対象 | 変更種別 |
|------|---------|
| `skills/co-issue/SKILL.md` | Step 1.5 追加 |
| `agents/worker-architecture.md` | drift 検出ロジック追加 |
| `commands/autopilot-retrospective.md` | Step 4.5 追加 |
| `deps.yaml` | 参照ファイル更新 |

architecture/ 非存在時は全ステップがスキップされ、既存プロジェクトへの影響なし。drift 検出は WARNING のみでマージをブロックしない。
