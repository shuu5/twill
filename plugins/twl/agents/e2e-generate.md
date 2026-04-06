---
name: twl:e2e-generate
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

ref-specialist-output-schema + ref-specialist-few-shot に従い JSON を出力すること。
findings 配列に severity / confidence / file / line / message / category を含める。
status は PASS / WARN / FAIL。findings 0件時: `{"status": "PASS", "findings": []}`
