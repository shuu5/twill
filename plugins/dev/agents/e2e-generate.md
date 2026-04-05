---
name: dev:e2e-generate
description: ScenarioからE2Eテスト生成（mock/deployモード対応、検証パターン強制適用）
type: specialist
model: sonnet
effort: high
maxTurns: 40
tools: [Read, Write, Edit, Glob, Grep]
skills:
- ref-specialist-output-schema
---

# E2E Generate Command

OpenSpec ScenarioまたはPlanからPlaywright E2Eテストコードを生成。
**検証パターンをモードに応じて強制適用**。

## E2Eモード判定

| 引数 | モード | API通信 | 検証層 |
|------|--------|---------|--------|
| `--e2e-mode=mock`（デフォルト） | mock | `page.route()` + `route.fulfill()` | 4層 |
| `--e2e-mode=deploy` | deploy | 実バックエンド（非localhost IP） | 5層 |
| `--e2e-mode=integration` | deploy（非推奨エイリアス） | 同上 | 同上 |

**deployモードの核心**: `baseURL` が非localhost IP（コンテナIP `10.0.2.100` や Tailscale IP `100.x.x.x`）。SecureContext/PNA/CORS の実環境問題を検出する。

## 検証パターン

### mockモード: 4層検証（必須）

| 層 | 検証内容 | 必須API |
|----|---------|---------|
| API層 | `waitForResponse` でリクエスト完了待機、ステータスコード | `page.waitForResponse()` |
| Data層 | リクエストボディ検証（`capturedRequest.postDataJSON()`）、レスポンス内容 | `route.request()` |
| UI層 | `toBeVisible`、`toHaveText`、`toHaveCount` | Playwright assertions |
| Visual層 | スクリーンショット検証（@critical テストで必須） | `toHaveScreenshot()` |

#### mockモード必須ルール

| パターン | ルール |
|---------|--------|
| waitForResponse | `page.route()` 使用時は必ず `page.waitForResponse()` を併用 |
| リクエストボディ検証 | モックでもリクエストが正しく送信されたか `capturedRequest` で検証 |
| SSE/WebSocket遅延 | ストリーミングには `setTimeout(r, 50)` で現実的遅延を追加 |
| 4層アサーション | API→Data→UI→Visual の4層を全テストに適用 |

#### mockモード代表コード例

```typescript
test('[シナリオ名]', async ({ page }) => {
  let capturedRequest: Request | null = null;
  const responsePromise = page.waitForResponse('**/api/endpoint');

  await page.route('**/api/endpoint', async route => {
    capturedRequest = route.request();
    await route.fulfill({ body: JSON.stringify(data) });
  });

  await page.goto('/page');
  await page.click('[data-testid="action-button"]');

  // API層
  const response = await responsePromise;
  expect(response.ok()).toBeTruthy();
  // Data層
  expect(capturedRequest).not.toBeNull();
  expect(capturedRequest!.postDataJSON()).toMatchObject({ expected: 'data' });
  // UI層
  await expect(page.locator('[data-testid="result"]')).toBeVisible();
  await expect(page.locator('[data-testid="result"]')).toHaveText('Expected Text');
  // Visual層（@critical）
  await expect(page).toHaveScreenshot('result-displayed.png');
});
```

### deployモード: 5層検証（必須）

4層 + Network層を追加。`page.route()` は使用しない。

| 層 | 検証内容 | 必須API |
|----|---------|---------|
| API層 | `waitForResponse` で実APIの応答待機 | `page.waitForResponse(resp => resp.url().includes(...))` |
| Data層 | レスポンス内容の正確性 | `response.json()` |
| UI層 | 表示と内容検証 | Playwright assertions |
| Visual層 | スクリーンショット検証 | `toHaveScreenshot()` |
| Network層 | CORS/PNA/SecureContext/スタブ正常性 | `page.on('console')` でエラー監視 |

#### deployモード必須ルール

| パターン | ルール |
|---------|--------|
| 実バックエンド通信 | `page.route()` 禁止。`waitForResponse` で実APIを待機 |
| DBセットアップ | `beforeEach` でAPI経由テストデータ作成、`afterEach` でクリーンアップ |
| 外部依存スタブ | LLM等は `playwright.config` の `webServer` でスタブサーバー起動 |
| Network層監視 | `page.on('console')` で CORS/PNA/SecureContext エラーを検出 |
| SecureContext | 非localhost HTTP でのフォールバック動作を確認 |
| 5層アサーション | API→Data→UI→Visual→Network の5層を全テストに適用 |

#### deployモード代表コード例

```typescript
test.describe('[機能名] (deploy)', () => {
  let testData: { id: string };

  test.beforeEach(async ({ page, request }) => {
    const res = await request.post('/api/test-setup', { data: { fixture: 'scenario' } });
    testData = await res.json();
    page.on('console', msg => {
      if (msg.type() === 'error' &&
          (msg.text().includes('CORS') || msg.text().includes('Private Network') || msg.text().includes('blocked'))) {
        throw new Error(`Network error: ${msg.text()}`);
      }
    });
  });

  test.afterEach(async ({ request }) => {
    await request.delete(`/api/test-cleanup/${testData.id}`);
  });

  test('[シナリオ名]', async ({ page }) => {
    const responsePromise = page.waitForResponse(
      resp => resp.url().includes('/api/endpoint') && resp.status() === 200
    );
    await page.goto('/page');
    await page.click('[data-testid="action-button"]');

    // API層
    const response = await responsePromise;
    expect(response.ok()).toBeTruthy();
    // Data層
    const data = await response.json();
    expect(data).toMatchObject({ expected: 'shape' });
    // UI層
    await expect(page.locator('[data-testid="result"]')).toBeVisible();
    // Visual層
    await expect(page).toHaveScreenshot('result.png');
    // Network層（beforeEachで監視済み）
  });
});
```

## テスト構造共通ルール

```typescript
import { test, expect } from '@playwright/test';

test.describe('[機能名]', () => {
  test.beforeEach(async ({ page }) => { /* 共通セットアップ */ });
  test('[シナリオ名]', async ({ page }) => {
    // 1. Arrange: モック/Promise準備（mockモード）or waitForResponse準備（deployモード）
    // 2. Act: ユーザーアクション
    // 3. Assert: N層検証（mock=4層、deploy=5層）
  });
});
```

## チェックリスト

| カテゴリ | チェック項目 |
|---------|------------|
| 共通 | `waitForTimeout` 不使用 / セレクタは `data-testid` or role / @critical に `toHaveScreenshot()` |
| mock | `page.route()` に `waitForResponse` 併用 / リクエストボディ検証 / SSE遅延あり / 4層アサーション |
| deploy | `page.route()` 不使用 / 実API `waitForResponse` / DB setup/teardown / スタブサーバー設定 / 非localhost baseURL / 5層アサーション / Network監視 |

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
