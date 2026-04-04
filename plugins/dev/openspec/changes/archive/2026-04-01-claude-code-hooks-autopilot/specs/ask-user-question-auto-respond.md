## ADDED Requirements

### Requirement: AskUserQuestion 自動応答 hook

ヘッドレス autopilot Worker が AskUserQuestion tool を呼んだ際、PreToolUse hook が自動的に回答を注入しなければならない（SHALL）。

#### Scenario: 選択肢付き質問への自動応答
- **WHEN** Worker が AskUserQuestion を呼び、`tool_input.questions[].options` に 1 件以上の選択肢がある
- **THEN** hook スクリプトが最初の option の label を `answers` に設定し、`permissionDecision: "allow"` と `updatedInput` を返す

#### Scenario: open-ended 質問への自動応答
- **WHEN** Worker が AskUserQuestion を呼び、`tool_input.questions[].options` が空または未設定
- **THEN** hook スクリプトが `"(autopilot: skipped)"` を `answers` に設定し、`permissionDecision: "allow"` と `updatedInput` を返す

#### Scenario: hooks.json への登録
- **WHEN** hooks/hooks.json を読み込む
- **THEN** PreToolUse セクションに `"matcher": "AskUserQuestion"` エントリが存在しなければならない（MUST）

#### Scenario: 既存 PreToolUse hook との共存
- **WHEN** PreToolUse セクションに既存の `"matcher": "Edit|Write"` エントリがある
- **THEN** AskUserQuestion エントリは別エントリとして追加され、既存エントリを変更しない（SHALL）
