# ref-budget-format — Claude Budget Status Line Format Spec

**Epic**: #1271 (AC10)
**Pinned**: 2026-05-08

## 現行フォーマット（Anthropic status line）

```
5h:XX%(YYm)
```

| フィールド | 意味 | 例 |
|-----------|------|-----|
| `5h` | 5時間 budget サイクルのプレフィックス（固定） | `5h` |
| `XX` | 消費済み % (0–100) | `72` |
| `YYm` | サイクルリセットまでの wall-clock 残り時間 | `83m`, `1h21m`, `2h` |

### 例

```
5h:72%(83m)   → 72% 消費、cycle reset まで 83 分
5h:5%(4h21m)  → 5% 消費、cycle reset まで 261 分
5h:95%(3m)    → 95% 消費、cycle reset まで 3 分（BUDGET-LOW 領域）
```

## Regex パターン

```python
# Python — pane テキスト全体から抽出
PCT_RE = re.compile(r'5h:(\d+)%\(([^)]+)\)')

m = PCT_RE.search(pane_text)
if m:
    budget_pct = int(m.group(1))   # 消費 %
    raw_time   = m.group(2)        # 生時間文字列 (e.g. "83m", "1h21m")
```

```bash
# bash grep-oP 版（budget-detect.sh）
BUDGET_PCT=$(echo "$PANE" | grep -oP '5h:\K[0-9]+(?=%)' | tail -1)
BUDGET_RAW=$(echo "$PANE" | grep -oP '5h:[0-9]+%\(\K[^\)]+' | tail -1)
```

## 時間文字列パース規則

`YYm` は以下の 3 パターン:

| パターン | 例 | 分換算 |
|---------|-----|--------|
| `\d+m` | `83m` | 83 |
| `\d+h` | `2h` | 120 |
| `\d+h\d+m` | `1h21m` | 81 |

## budget_min 計算

```
budget_min = 300 * (100 - budget_pct) // 100
```

5h サイクル = 300 分として、残存トークン分数を wall-clock で近似。

## デフォルト閾値

| 閾値 | デフォルト値 | 意味 |
|------|-------------|------|
| `threshold_remaining_minutes` | 40 | budget_min ≤ 40 → low=True |
| `threshold_cycle_minutes` | 5 | cycle_reset_min ≤ 5 → low=True |

設定ファイル (`.supervisor/budget-config.json`) で上書き可能:

```json
{
  "threshold_remaining_minutes": 40,
  "threshold_cycle_minutes": 5
}
```

## Format Mismatch Fallback

`5h:%(Ym)` パターンが pane テキストに見つからない場合:
- `low=True`（安全側 fallback）
- `error="format-mismatch"`

Anthropic が status line フォーマットを変更した際にこの ref を更新すること。

## 変更履歴

| 日付 | 変更内容 |
|------|---------|
| 2026-05-08 | 初版 pin（Issue #1515、epic #1271 AC10） |
