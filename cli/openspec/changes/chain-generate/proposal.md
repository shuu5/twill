## Why

deps.yaml v3.0 の chains/step/step_in 情報がプロンプトファイル内に手書きで分散しており、deps.yaml の SSOT と乖離するリスクがある。deps.yaml からテンプレートを自動生成することで、SSOT からの一方向生成を実現し、AI 修正時の整合性を保証する。

## What Changes

- `twl chain generate <chain-name>` サブコマンドを twl-engine.py に追加
- Template A: Chain A 参加者のチェックポイント出力テンプレート生成（next コンポーネント自動解決）
- Template B: Chain B の called-by 宣言行生成（step_in から parent/step 取得）
- Template C: chain ライフサイクル図テーブル生成（controller 用）
- `--write` フラグによるプロンプトファイルへの直接書き込み機能
- テンプレートは自律実行デフォルト前提で設計（--auto 分岐なし）

## Capabilities

### New Capabilities

- **chain-generate-stdout**: `twl chain generate <chain-name>` で Template A/B/C を stdout に出力
- **chain-generate-write**: `--write` フラグでプロンプトファイル内の既存セクションをパターンマッチで検出・置換
- **template-a-checkpoint**: chains.steps から position+1 を解決し、チェックポイント出力テンプレートを生成
- **template-b-called-by**: step_in から parent と step を取得し、called-by 宣言行を生成
- **template-c-lifecycle**: chains.steps と各 component の description からライフサイクル図テーブルを生成

### Modified Capabilities

- なし（既存機能への変更なし）

## Impact

- **変更対象**: `twl-engine.py`（CLI 引数追加、テンプレート生成関数追加）
- **依存関係**: deps.yaml v3.0 の `chains`/`step`/`step_in` フィールドが前提（#11 で導入済み）
- **テスト**: 既存の chain_validate テストとの整合性を維持
- **API/互換性**: 新規サブコマンド追加のみ。既存コマンドへの影響なし
