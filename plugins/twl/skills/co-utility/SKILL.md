---
name: twl:co-utility
description: |
  standalone ユーティリティコマンドのエントリポイント。
  プロンプトなしで対話的ツール紹介、プロンプト付きで該当コマンド実行。

  Use when user: says ユーティリティ/utility/ツール一覧,
  says worktree一覧/worktree削除/検証/validate,
  says サービス起動/services/スクショ/UI capture,
  says schema更新/spec診断/e2e計画,
  says self-improve/セルフレビュー,
  says DeltaSpec propose/apply/archive.
type: controller
effort: low
tools: []
spawnable_by:
- user
---

# co-utility

standalone ユーティリティコマンドの統合エントリポイント。

## Step 0: モード判定

ユーザー入力（引数 or プロンプト）からカテゴリとコマンドを判定する。

### カテゴリマッピング

| カテゴリ | キーワード | コマンド |
|---------|-----------|---------|
| **Worktree** | worktree, 一覧, 削除, list, delete | worktree-list, worktree-delete |
| **検証** | validate, 検証, チェック | twl-validate |
| **開発** | services, サービス, ui, capture, スクショ, schema | services, ui-capture, schema-update |

### 判定ロジック

1. **プロンプトあり**: キーワードマッチでカテゴリ → コマンドを特定
   - 1 コマンドに絞れる → Step 2 へ
   - カテゴリは分かるがコマンドが曖昧 → カテゴリ内の候補をテーブル表示し AskUserQuestion
   - 該当なし → Step 1 へ
2. **プロンプトなし**: Step 1 へ

## Step 1: 対話的ツール紹介

全カテゴリのコマンドをテーブルで紹介する。

```
利用可能なユーティリティコマンド:

🌳 Worktree
  /twl:worktree-list   — worktree 一覧表示
  /twl:worktree-delete — worktree + ブランチ削除

🔍 検証
  /twl:twl-validate  — 構造・型ルール検証（twl + plugin validate）

🛠 開発ユーティリティ
  /twl:services      — 開発サービス起動管理
  /twl:ui-capture    — UI スクショ撮影 + セマンティック解析
  /twl:schema-update — Zod スキーマ更新 + OpenAPI 再生成
```

AskUserQuestion: 「どのコマンドを実行しますか？番号またはコマンド名で指定してください」

## Step 2: コマンド実行

特定されたコマンドの Skill を呼び出す。

```
Skill(twl:<command-name>)
```

ユーザーの元のプロンプトに追加のコンテキスト（パス、オプション等）が含まれている場合は、そのままコマンドに引数として渡す。
