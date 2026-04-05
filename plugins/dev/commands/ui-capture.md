---
tools: [mcp__playwright__browser_snapshot, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_navigate]
---

# UI キャプチャ

UI のスクリーンショット撮影 + セマンティック解析でコンテキスト化する。

## 前提条件

- Playwright MCP が接続されていること
- ブラウザが起動していること（未起動の場合は URL を確認して `mcp__playwright__browser_navigate` で開く）

## 実行フロー

### 1. 状態確認

```
mcp__playwright__browser_snapshot
```

ブラウザが起動していない場合、ユーザーに URL を確認し `mcp__playwright__browser_navigate` で開く。

### 2. スクリーンショット撮影

```
mcp__playwright__browser_take_screenshot
  type: png
  filename: ui-capture-{timestamp}.png
```

### 3. セマンティック解析

撮影したスクリーンショットを `Read` ツールで読み込み（マルチモーダル）、ユーザーの説明と照らし合わせて分析。

**分析観点**:
- ユーザーが指摘した問題の視覚的確認
- エラーメッセージの有無と内容
- UI 要素の状態（ボタンの有効/無効、入力フィールドの状態等）
- レイアウトの崩れ
- 予期しない表示内容

### 4. 結果報告

```
=== UI Capture Report ===

スクリーンショット: [ファイルパス]
ユーザー報告: [ユーザーの説明]

観察結果:
- [視覚的に確認できた内容]

問題の特定:
[問題の詳細な説明]

推奨アクション:
- [修正提案]
```

## アクセシビリティスナップショットとの使い分け

| 用途 | ツール |
|------|--------|
| DOM 構造・要素の状態確認 | `mcp__playwright__browser_snapshot` |
| 視覚的な問題の確認 | `mcp__playwright__browser_take_screenshot` + `Read` |

**推奨**: 両方を組み合わせて使用。

## 注意事項

- Playwright MCP はコンテナ内でのみ動作
- スクリーンショットファイルはコンテナ内パスに保存
- 機密情報が画面に表示されている場合は注意
