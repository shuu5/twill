## Why

loom-plugin-dev は旧 dev plugin の後継として新規構築中だが、27 specialists と 11 references が未移植のまま。phase-review / merge-gate が動的に specialist を spawn する設計のため、specialist 群なしでは PR サイクルが機能しない。

## What Changes

- 27 specialists を agents/ に移植（プロンプト内容はほぼそのまま、出力スキーマを共通化）
- 11 references を refs/ に移植（4 件は loom sync-docs 対象、7 件はプラグイン固有）
- deps.yaml v3.0 に全 specialist/reference を登録
- 全 specialist の出力を ADR-004 共通出力スキーマ（status: PASS/WARN/FAIL + findings[]）に統一
- severity を CRITICAL/WARNING/INFO の 3 段階に正規化（旧 High/Medium/Suggestion 等を解消）
- model 宣言を設計判断 #11 に準拠して割り当て（haiku: 構造チェック系、sonnet: 品質判断系）

## Capabilities

### New Capabilities

- phase-review / merge-gate が tech-stack-detect.sh の結果に基づき conditional specialist を動的 spawn 可能になる
- specialist-output-parse.sh が全 specialist の出力を機械的にパース可能になる
- loom sync-docs --check が 4 参照ファイルの同期状態を検証可能になる

### Modified Capabilities

- deps.yaml の agents セクションが空 `{}` から 27 エントリに拡張
- deps.yaml の refs セクションが 4 → 15 エントリに拡張

## Impact

- **agents/**: 27 ファイル新規作成（旧プラグインからの移植 + 出力スキーマ適合）
- **refs/**: 11 ファイル新規作成（4 loom sync 対象 + 7 プラグイン固有）
- **deps.yaml**: agents セクションに 27 件、refs セクションに 11 件追加
- **依存**: B-2（#4 プロジェクト初期構築）完了前提、shuu5/loom#29（model validation）・shuu5/loom#33（specialist output schema）関連
