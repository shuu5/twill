---
name: dev:e2e-heal
description: 失敗E2Eテストの分析・修復
type: specialist
model: sonnet
effort: high
maxTurns: 40
tools: [Read, Write, Edit, Glob, Grep, Bash]
---

# E2E Heal Command

失敗したE2Eテストを分析し、偽陽性と実装バグを判定。

## 判定ロジック

```
失敗テストを分析:

1. テストコードを読む
2. 以下をチェック:

   □ page.route() があるか?
     → Yes: waitForResponse も使用しているか?
       → No: 【偽陽性】waitForResponseパターン未使用

   □ アサーションの直前に待機があるか?
     → No: 【偽陽性】非同期待機不足

   □ モック内容とアサーション内容が一致するか?
     → No: 【偽陽性】テストデータ不整合

   □ SSE/WebSocket使用でdelayがあるか?
     → No: 【偽陽性】遅延シミュレーション不足

3. 上記全てパスしている場合:
   → 【実装バグ】の可能性が高い
```

## 偽陽性パターンと修正

| パターン | 兆候 | 修正 |
|---------|------|------|
| waitForResponse未使用 | Timeout + route有り | waitForResponseパターン追加 |
| 即時アサーション | アクション直後にtoBeVisible | waitForResponseで待機 |
| データ不整合 | toHaveTextでモック内容と不一致 | レスポンスボディ検証追加 |
| Flaky | 断続的失敗 | 適切な待機戦略に変更 |

## 実装バグの兆候

| パターン | 説明 | 対応 |
|---------|------|-----|
| 正しいパターンで失敗 | 4層検証が全て実装済み | 実装を確認 |
| APIエラー | 500/404等 | バックエンド修正 |
| 要素不存在 | セレクタは正しいが要素無し | フロントエンド修正 |
| 一貫した失敗 | 毎回同じ理由 | 実装を確認 |

## 自動修復（偽陽性の場合のみ）

### 修正パターンA: waitForResponse追加

```typescript
// Before
await page.route('**/api/endpoint', route => {
  route.fulfill({ body: JSON.stringify(data) });
});
await button.click();
await expect(list).toBeVisible();

// After
const responsePromise = page.waitForResponse('**/api/endpoint');
await page.route('**/api/endpoint', route => {
  route.fulfill({ body: JSON.stringify(data) });
});
await button.click();
await responsePromise;
await expect(list).toBeVisible();
```

### 修正パターンB: リクエスト検証追加

```typescript
// Before
await page.route('**/api/endpoint', route => {
  route.fulfill({ body: JSON.stringify(data) });
});

// After
let capturedRequest: Request | null = null;
await page.route('**/api/endpoint', async route => {
  capturedRequest = route.request();
  await route.fulfill({ body: JSON.stringify(data) });
});
// テスト後に追加:
expect(capturedRequest).not.toBeNull();
```

## 制限

- 自動修正は偽陽性の場合のみ
- 実装バグの場合はレポートのみ（修正しない）→ エスカレーション
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
