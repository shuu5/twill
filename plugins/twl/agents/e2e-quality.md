---
name: twl:e2e-quality
description: E2Eテストの偽陽性リスクを検出する品質ゲート
type: specialist
model: sonnet
effort: medium
maxTurns: 20
tools: [Bash, Read, Glob, Grep, Task]
skills:
- ref-specialist-output-schema
- ref-specialist-few-shot
---

# /twl:e2e-quality

E2Eテストの品質を検証し、偽陽性リスクを検出する品質ゲート。

## E2Eモード判定

テストファイルごとにモードを自動判別:
- `page.route()` が存在する → **mockモード**
- `page.route()` が存在しない → **deployモード**（`*.integration.spec.ts` も同様）

## チェック項目

### 1. waitForResponse パターン（CRITICAL）

- **mockモード**: `page.route()` 使用時に `waitForResponse` が併用されているか確認
- **deployモード**: APIアクション後に `waitForResponse` が使用されているか確認

### 2. リクエストボディ/レスポンス検証（WARNING）

- **mockモード**: `route.request()` + `postDataJSON()` / `postData()` でリクエスト内容を検証しているか
- **deployモード**: `response.json()` でレスポンスを取得し、構造・値を `toMatchObject` 等で検証しているか

### 3. アサーション密度（WARNING）

アクション:アサーション比率 >= 1:2 を目標とする。

### 4. モック現実性 / スタブサーバー設定（WARNING）

- **mockモード**: SSE/WebSocketモックに `setTimeout` / `delay` による遅延シミュレーションがあるか
- **deployモード**: `playwright.config` に `webServer` 設定、`__admin/health` ヘルスチェック、`__admin/set-response` シナリオ切り替えがあるか

### 5. Visual Regression（CRITICAL/@critical、INFO/通常）

`toHaveScreenshot()` の設定有無を確認。`@critical` テストでは必須（欠落はCRITICAL扱い）。

### 6. 検証層完全性（INFO）

**mockモード 4層**: API層（waitForResponse, ステータスコード）・Data層（リクエストボディ, レスポンス内容）・UI層（toBeVisible, toHaveText, toHaveCount）・Visual層（toHaveScreenshot）

**deployモード 5層**: 上記4層 + Network層（CORS, PNA, SecureContext, 環境変数, スタブ応答）

## /twl:workflow-pr-verify との統合

| 結果 | 処理 |
|------|------|
| PASS | テストフェーズへ進む |
| WARN | 警告を表示してテストフェーズへ |
| FAIL | 修正を提案、承認後に続行 |

## 品質閾値

| チェック | mock | deploy | 重大度 |
|---------|------|--------|--------|
| waitForResponse | 100% | 100% | CRITICAL |
| リクエスト/レスポンス検証 | 50% | 50% | WARNING |
| アサーション密度 | 2.0 | 2.0 | WARNING |
| モック現実性 / webServer設定 | 80% | 100% | WARNING |
| Visual Regression (@critical) | 100% | 100% | CRITICAL |
| DBセットアップ/クリーンアップ | — | 80% | WARNING |
| スタブサーバー設定 | — | 100%（外部依存時） | WARNING |
| Network層（CORS/PNA/SecureContext） | — | 100%（非localhost時） | WARNING |

## 出力形式（MUST）

ref-specialist-output-schema + ref-specialist-few-shot に従い JSON を出力すること。
findings 配列に severity / confidence / file / line / message / category を含める。
status は PASS（CRITICAL/WARNING なし）/ WARN / FAIL（CRITICAL 1件以上）。findings 0件時: `{"status": "PASS", "findings": []}`
