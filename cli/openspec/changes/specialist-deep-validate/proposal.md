## Why

specialist の出力スキーマ（PASS/FAIL, findings, severity, confidence）が prompt body に言及されていないと、merge-gate の機械的フィルタ（`severity in [critical, high] && confidence >= 80`）が機能しない。現在 deep-validate にはこの検証がなく、不適切な specialist が検出されない。

## What Changes

- `deep-validate` に specialist 出力スキーマキーワード検証チェックを追加
- `output_schema: custom` フラグによるスキップ機構を追加
- `audit` Section 5 の Output 列にスキーマ準拠状況を反映

## Capabilities

### New Capabilities

- specialist の prompt body 内で出力スキーマキーワード（PASS/FAIL, findings, severity, confidence）の存在を検証
- `output_schema: custom` を持つ specialist を検証スキップ
- `output_schema` に不正値がある場合の WARNING 報告

### Modified Capabilities

- audit Section 5 の Output 列を拡張し、共通スキーマキーワードの準拠状況を表示

## Impact

- **twl-engine.py**: deep-validate セクション、audit セクションに検証ロジック追加
- **deps.yaml 仕様**: `output_schema` フィールドの認識（既存フィールドへの影響なし）
- **types.yaml**: 変更不要（output_schema は deps.yaml レベルのフィールド）
