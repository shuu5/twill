# phase-review findings schema

`phase-review.json` の `findings[]` エントリのスキーマ定義。

## フィールド定義

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `severity` | string | ✓ | 重要度: `"CRITICAL"` \| `"WARNING"` \| `"INFO"` |
| `category` | string | ✓ | 分類カテゴリ（下記参照） |
| `message` | string | ✓ | 問題の説明（人間が読めるテキスト） |
| `confidence` | number | ✓ | 信頼度 0–100 |

## category 列挙値

| category | severity | 説明 | merge-gate 動作 | 担当スクリプト |
|---|---|---|---|---|
| `ac_missing` | WARNING | AC が未達成のまま PR が作成されている | **REJECT**（exit 1） | `merge-gate-check-phase-review.sh` |
| `coverage_low` | WARNING | テストカバレッジが基準を下回っている | 通過（警告のみ） | — |
| `style` | WARNING | コーディングスタイル違反 | 通過（警告のみ） | — |
| `chain-integrity-drift` | CRITICAL | chain 定義と実装の乖離 | **REJECT**（exit 1） | `merge-gate-check-pr.sh` |
| `optional` | WARNING | 任意の改善提案 | 通過（警告のみ） | — |

> **注**: `merge-gate 動作` 列は merge-gate 全体での最終動作を示す。`merge-gate-check-phase-review.sh` が直接 REJECT するのは `ac_missing` のみ。`chain-integrity-drift` は `merge-gate-check-pr.sh` が担当する。

## merge-gate ブロックルール（Issue #1025）

`merge-gate-check-phase-review.sh` は以下の場合に REJECT（exit 1）を返す:

1. `phase-review.json` が不在（status = MISSING）
2. `findings[]` に `severity == "WARNING"` かつ `category == "ac_missing"` のエントリが 1 件以上存在する

## JSON サンプル

```json
{
  "step": "phase-review",
  "status": "PASS",
  "findings_summary": "0 CRITICAL, 1 WARNING",
  "critical_count": 0,
  "findings": [
    {
      "severity": "WARNING",
      "category": "ac_missing",
      "message": "AC #1 未確認: specialist review が AC カバレッジを検証していない",
      "confidence": 90
    }
  ],
  "timestamp": "2026-04-28T00:00:00Z"
}
```

## 関連

- `plugins/twl/scripts/merge-gate-check-phase-review.sh` — このスキーマを使用するスクリプト
- `plugins/twl/refs/ref-specialist-output-schema.md` — specialist 出力スキーマ
- Issue #1025 — `ac_missing` category 導入の背景
