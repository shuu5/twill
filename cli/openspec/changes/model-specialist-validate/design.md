## Context

loom-engine.py の deep_validate は (A) controller-bloat, (B) ref-placement, (C) tools-mismatch の3カテゴリを検証している。audit_report は 5セクション構成。specialist の model フィールドは現在いずれでも未検証。

Issue #29 で specialist 型の model 宣言チェックを追加する。許可値は loom-engine.py 内定数として定義し、types.yaml には含めない。

## Goals / Non-Goals

**Goals:**

- deep-validate に model-required ルールを追加（specialist 限定）
- audit に Section 6: Model Declaration を追加
- ALLOWED_MODELS 定数を loom-engine.py に定義

**Non-Goals:**

- specialist 以外の型への model チェック拡張
- types.yaml への model 許可値の外部化
- model フィールドのデフォルト値推定

## Decisions

1. **検証対象**: specialist のみ。agents セクション内で `type` が `specialist` に解決されるコンポーネント
2. **ALLOWED_MODELS の位置**: loom-engine.py モジュールレベル定数。`{"haiku", "sonnet", "opus"}`
3. **検証ロジックの配置**: deep_validate 関数内に新セクション `(D) Model Declaration` として追加
4. **severity レベル**:
   - model 未宣言 → WARNING
   - model が ALLOWED_MODELS にない → INFO（タイポ検出、将来モデル名を妨げない）
   - model = "opus" → WARNING（設計判断: specialist に opus は使わない）
5. **audit Section 6**: specialist 全件を一覧表示。model 値と severity を表示
6. **型解決**: `resolve_type()` を使用して specialist かどうかを判定（既存パターンに準拠）

## Risks / Trade-offs

- ALLOWED_MODELS がハードコードのため、新モデル追加時に loom-engine.py の更新が必要。ただし未知モデルは INFO（非ブロック）なので実運用への影響は軽微
- opus WARNING は設計判断に依存。将来 specialist に opus が必要になった場合、定数更新だけでなく WARNING 除外ロジックも必要になる可能性がある
