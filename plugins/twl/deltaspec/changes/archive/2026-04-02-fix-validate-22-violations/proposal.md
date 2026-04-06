## Why

`loom validate` が 16 violations（v3-calls-key）を検出する。#78/#79 で導入した `external`/`path`/`optional`/`note` キーは deps.yaml v3 スキーマに存在しない独自キーであり、#97 で loom-plugin-session が新設された今、cross-plugin 参照（`session:component`）形式に移行可能。

## What Changes

- 4 コンポーネント（autopilot-poll, autopilot-phase-execute, crash-detect, health-check）の calls から `external`/`path`/`optional`/`note` キーを除去
- session-state.sh への参照を `session:session-state` cross-plugin 参照に置換
- script→script 参照の整合性維持（crash-detect→state-read/state-write, health-check→state-read）

## Capabilities

### New Capabilities

なし（既存機能の参照形式修正のみ）

### Modified Capabilities

- deps.yaml の外部依存宣言が v3 準拠の cross-plugin 参照に統一される
- `loom validate` が Violations 0 で PASS する

## Impact

- **deps.yaml**: 4 コンポーネントの calls セクション修正
- **依存**: loom-plugin-session（`session:session-state`）への cross-plugin 参照が追加される
- **scripts**: 実行時の session-state.sh 呼び出しロジックは変更なし（deps.yaml メタデータのみ）
- **リスク**: 低（メタデータ修正のみ、実行パスに変更なし）
