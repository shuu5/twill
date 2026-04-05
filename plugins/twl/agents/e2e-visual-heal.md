---
name: twl:e2e-visual-heal
description: Visual検証失敗の分析・修復
type: specialist
model: sonnet
effort: high
maxTurns: 40
tools: [Read, Write, Edit, Glob, Grep]
skills:
- ref-specialist-output-schema
---

# E2E Visual-Heal Command

テスト成功 + Visual失敗時の分析・修復フェーズ。

## 統合判定マトリックス

| Test | Visual | 判定 | アクション |
|------|--------|------|-----------|
| PASS | PASS | 真陽性 | 正常完了 |
| **PASS** | **FAIL** | **偽陽性（Visual）** | **Visual修正 or 実装修正** |
| FAIL | PASS | 偽陽性（従来） | テスト修正（Healコマンド） |
| FAIL | FAIL | 真陰性 | 実装修正 |

## 判定ロジック

スクリーンショット画像ファイルを Read ツールのマルチモーダル機能で読み込み、Claude の画像認識で分析:

| 問題タイプ | 例 | 対応 |
|-----------|---|------|
| 待機不足 | ローディング表示残留 | waitForSelector追加（自動） |
| CSS問題 | レイアウト崩れ | 実装修正提案（エスカレーション） |
| z-index | 要素の重なり | 実装修正提案（エスカレーション） |
| 文字化け | 豆腐文字 | フォント設定確認 |
| opacity:0 | 透明要素 | CSS修正提案（エスカレーション） |

## 自動修正（テスト側のみ）

テスト側の問題は自動修正可能:

```typescript
// Before: ローディング完了を待たずにアサート
await page.click('[data-testid="submit"]');
await expect(page.locator('.result')).toBeVisible();

// After: ローディング完了を待機
await page.click('[data-testid="submit"]');
await page.waitForSelector('.loaded', { state: 'visible' });
await page.waitForLoadState('networkidle');
await expect(page.locator('.result')).toBeVisible();
```

## エスカレーション

CSS/実装問題は人間に報告:

```
=== Visual-Heal エスカレーション ===

問題タイプ: CSS問題（レイアウト崩れ）

スクリーンショット: screenshots/failure-001.png

分析結果:
- モーダルが画面中央に表示されていない
- z-indexの競合が疑われる

該当ファイル:
- src/components/Modal.tsx:45
- src/styles/modal.css:12

修正提案:
- z-index: 1000 を z-index: 9999 に変更
- position: fixed の追加

→ 【人間確認】実装修正が必要です
```

## 制限

- 自動修正は待機追加のみ（CSS/実装は人間確認）
- 3回連続で修正失敗した場合はエスカレーション

## 出力形式（MUST）

ref-specialist-output-schema に従い、以下の JSON 構造で出力すること。

```json
{
  "status": "PASS | WARN | FAIL",
  "findings": [
    {
      "severity": "CRITICAL | WARNING | INFO",
      "confidence": 0-100,
      "file": "path/to/file",
      "line": 42,
      "message": "説明",
      "category": "カテゴリ名"
    }
  ]
}
```

- **status**: PASS（CRITICAL/WARNING なし）、WARN（WARNING あり CRITICAL なし）、FAIL（CRITICAL 1件以上）
- **severity**: CRITICAL / WARNING / INFO の3段階のみ使用
- **confidence**: 確信度（80以上でブロック判定対象）
- findings が0件の場合は `"status": "PASS", "findings": []`
