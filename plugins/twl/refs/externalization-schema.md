---
name: externalization-schema
description: 外部化ファイルのスキーマ定義（working-memory.md と wave-{N}-summary.md）
type: reference
---

# 外部化ファイル スキーマリファレンス

su-compact と externalize-state が参照する SSOT。外部化ファイルのフィールド定義を規定する。

## working-memory.md（一時退避）

PreCompact フックで書き出し、PostCompact フックで読み込んで復元する一時ファイル。

**配置パス**: `.autopilot/working-memory.md`

### フロントマター

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `externalized_at` | ISO 8601 datetime | 外部化した日時 |
| `trigger` | enum | 外部化のきっかけ: `auto_precompact` \| `manual` \| `wave_complete` |
| `lifecycle` | enum | 常に `temporary`（PostCompact で消費後に破棄） |

### テンプレート

```markdown
---
externalized_at: "YYYY-MM-DDTHH:MM:SSZ"
trigger: auto_precompact | manual | wave_complete
lifecycle: temporary
---

## 現在のタスク

- [ ] タスクの説明
- [x] 完了済みタスク

## 進捗

現在の作業: ...
次のステップ: ...

## 監視中の Controller

| Controller | Window | Status | 最終確認 |
|---|---|---|---|

## 重要なコンテキスト

（compaction で失われると困る sharp な情報）
```

---

## wave-{N}-summary.md（永続保存候補）

Wave 完了時に書き出し、Long-term Memory（Memory MCP）にも保存する。

**配置パス**: `.autopilot/wave-{N}-summary.md`（N は Wave 番号）

### フロントマター

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `externalized_at` | ISO 8601 datetime | 外部化した日時 |
| `trigger` | enum | 常に `wave_complete` |
| `wave_number` | integer | Wave 番号（1, 2, 3, ...） |
| `lifecycle` | enum | 常に `persistent`（Long-term Memory にも保存） |

### テンプレート

```markdown
---
externalized_at: "YYYY-MM-DDTHH:MM:SSZ"
trigger: wave_complete
wave_number: N
lifecycle: persistent
---

## Wave N サマリ

### 実装結果

| Issue | PR | 結果 | 介入 |
|---|---|---|---|

### 知見

（Long-term Memory に保存すべき教訓）

### 次 Wave への引き継ぎ

（Working Memory に復帰させるべき情報）
```

---

## 利用スキル

| スキル/コマンド | 用途 |
|----------------|------|
| su-compact | 外部化ファイルの書き出し |
| externalize-state | 状態の外部化実行 |
| su-observer | compaction 後の復元参照 |
