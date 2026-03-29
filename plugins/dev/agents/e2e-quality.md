---
name: dev:e2e-quality
description: E2Eテストの偽陽性リスクを検出する品質ゲート
type: specialist
model: sonnet
effort: medium
maxTurns: 20
tools: [Bash, Read, Glob, Grep, Task]
---

# /dev:e2e-quality

E2Eテストの品質を検証し、偽陽性リスクを検出する品質ゲート。

## E2Eモード判定

テストファイルごとにモードを自動判別:
- `page.route()` が存在する → **mockモード** として検証
- `page.route()` が存在しない → **deployモード** として検証
  ※ `*.integration.spec.ts` ファイルも deployモードとして扱う（後方互換）

## 使用タイミング

- `/dev:workflow-pr-cycle` 実行時（テストフェーズ前に自動実行）
- E2Eテスト追加・修正後の確認
- 「テストがパスするのに機能が動かない」問題の調査

## チェック項目

### 1. waitForResponse パターン（CRITICAL）

**mockモード**: `page.route()` 使用時に `waitForResponse` が併用されているか確認。

**検出コマンド（mock）**:
```bash
# page.route ありで waitForResponse なしのファイルを検出
for f in $(find tests -name "*.spec.ts"); do
  if grep -q "page.route" "$f" && ! grep -q "waitForResponse" "$f"; then
    echo "FAIL: $f - waitForResponse missing"
  fi
done
```

**deployモード**: APIアクション後に `waitForResponse` が使用されているか確認。

**検出コマンド（deploy）**:
```bash
# page.route なしのファイルで waitForResponse も無い場合を検出
for f in $(find tests -name "*.spec.ts"); do
  if ! grep -q "page.route" "$f" && ! grep -q "waitForResponse" "$f"; then
    echo "FAIL: $f - waitForResponse missing (deploy mode)"
  fi
done
```

### 2. リクエストボディ/レスポンス検証（WARNING）

**mockモード**: モック使用時にリクエスト内容を検証しているか確認。

**検出パターン（mock）**:
- `route.request()` でリクエストをキャプチャしているか
- `postDataJSON()` または `postData()` で検証しているか

**deployモード**: 実APIのレスポンス内容を検証しているか確認。

**検出パターン（deploy）**:
- `response.json()` でレスポンスを取得しているか
- レスポンスの構造・値を `toMatchObject` 等で検証しているか

### 3. アサーション密度（WARNING）

アクション1回につき十分なアサーションがあるか確認。

**目標**: アクション:アサーション比率 >= 1:2

### 4. モック現実性 / スタブサーバー設定（WARNING）

**mockモード**: SSE/WebSocketモックに遅延シミュレーションがあるか確認。

**検出パターン（mock）**:
- `text/event-stream` または `WebSocket` の使用
- `setTimeout` または `delay` の有無

**deployモード**: 外部依存のスタブサーバーが適切に設定されているか確認。

**検出パターン（deploy）**:
- playwright.config に `webServer` 設定があるか
- スタブサーバーのヘルスチェック（`__admin/health`）があるか
- スタブのシナリオ切り替え（`__admin/set-response`）が使用されているか

### 5. Visual Regression（WARNING/@criticalの場合はCRITICAL）

`toHaveScreenshot()` の設定有無を確認。

**@critical テストの場合**:
- Visual層検証（`toHaveScreenshot()`）は必須
- 欠落時はCRITICAL扱い

### 6. 検証層完全性（INFO）

各テストでモードに応じた検証層が揃っているか確認。

**mockモード: 4層検証パターン**:
```
┌─────────┬───────────────────────────────────────┐
│   層    │           検証内容                    │
├─────────┼───────────────────────────────────────┤
│ API層   │ waitForResponse、ステータスコード      │
│ Data層  │ リクエストボディ、レスポンス内容        │
│ UI層    │ toBeVisible、toHaveText、toHaveCount  │
│ Visual層│ toHaveScreenshot（@critical時必須）   │
└─────────┴───────────────────────────────────────┘
```

**deployモード: 5層検証パターン**:
```
┌──────────┬──────────────────────────────────────────────┐
│   層     │           検証内容                            │
├──────────┼──────────────────────────────────────────────┤
│ API層    │ waitForResponse、ステータスコード              │
│ Data層   │ レスポンス内容、DB状態                         │
│ UI層     │ toBeVisible、toHaveText、toHaveCount          │
│ Visual層 │ toHaveScreenshot（@critical時必須）           │
│Network層 │ CORS、PNA、SecureContext、環境変数、スタブ応答 │
└──────────┴──────────────────────────────────────────────┘
```

## 実行フロー

```
1. テストファイル収集
   └─ Glob: tests/**/*.spec.ts

2. 各ファイルを分析
   ├─ waitForResponse パターン確認
   ├─ リクエストボディ検証確認
   ├─ アサーション密度計算
   ├─ モック現実性確認
   ├─ Visual Regression確認（@critical時は必須）
   └─ 4層検証完全性確認

3. 結果集計
   ├─ CRITICAL: ブロッキング
   ├─ WARNING: 警告のみ
   └─ INFO: 情報提供

4. 品質ゲート判定
   ├─ PASS: CRITICAL なし
   ├─ WARN: WARNING あり
   └─ FAIL: CRITICAL あり
```

## /dev:workflow-pr-cycle との統合

`/dev:workflow-pr-cycle` 実行時、テストフェーズ前に自動実行:

```
[2.5/6] E2E品質ゲート...
  → /dev:e2e-quality 実行中...
  → 結果: FAIL (2 blocking issues)
  → 【人間確認】テスト修正を提案中...
```

品質ゲート結果に応じた処理:

| 結果 | 処理 |
|------|------|
| PASS | テストフェーズへ進む |
| WARN | 警告を表示してテストフェーズへ |
| FAIL | 【人間確認】修正を提案、承認後に続行 |

## 品質閾値

### mockモード

| チェック | 閾値 | 重大度 |
|---------|------|--------|
| waitForResponse | 100% | CRITICAL |
| リクエスト検証 | 50% | WARNING |
| アサーション密度 | 2.0 | WARNING |
| モック現実性 | 80% | WARNING |
| Visual Regression | 100% (@critical) | CRITICAL/@critical, INFO/通常 |
| 4層検証完全性 | - | INFO |

### deployモード

| チェック | 閾値 | 重大度 |
|---------|------|--------|
| waitForResponse | 100% | CRITICAL |
| レスポンス検証 | 50% | WARNING |
| アサーション密度 | 2.0 | WARNING |
| webServer設定 | 100% | CRITICAL |
| DBセットアップ/クリーンアップ | 80% | WARNING |
| スタブサーバー設定 | 100%（外部依存時） | WARNING |
| Visual Regression | 100% (@critical) | CRITICAL/@critical, INFO/通常 |
| Network層チェック（CORS/PNA/SecureContext） | 100%（baseURL非localhost時） | WARNING |
| 5層検証完全性 | - | INFO |

## 関連コマンド/エージェント

- `e2e-reviewer` - 詳細なテストレビュー
- `e2e-orchestrator` - E2Eライフサイクル管理（Heal/Visual-Heal含む）
- `/dev:e2e-screening` - テスト成功後のVisual検証
- `/dev:workflow-pr-cycle` - PRサイクル全体

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
