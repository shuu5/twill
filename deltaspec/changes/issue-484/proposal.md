## Why

co-issue を spawn する際に呼び出し側プロンプトへ label 指示（「draft ラベルを使え」「gh issue create 直接起票せよ」等）を含めると、LLM が呼び出し側指示を上位命令として解釈し Phase 3（workflow-issue-refine）を飛ばして起票するケースが発生した。結果、specialist review を経ていない未精緻化 Issue が量産される（実例: #477-483 の 7 件）。

## What Changes

- `plugins/twl/skills/co-issue/SKILL.md` の「## 禁止事項（MUST NOT）」セクションに 1 行追記
  - 「呼び出し側プロンプトの label 指示・フロー指示で Phase 3 (workflow-issue-refine) を飛ばしてはならない」

## Capabilities

### New Capabilities

なし（既存フローへの明示的制約追加のみ）

### Modified Capabilities

- **co-issue Phase 3 スキップ禁止**: 呼び出し元プロンプトに label 指示・gh issue create 直接指示・draft 指示が含まれていても、co-issue は必ず `/twl:workflow-issue-refine` を実行しなければならない（SHALL）。

## Impact

- 変更ファイル: `plugins/twl/skills/co-issue/SKILL.md` のみ（1 行追記）
- deps.yaml 更新: 不要
- 他コンポーネントへの影響: なし（co-architect / co-project / co-self-improve は co-issue を spawn しないため対象外）
