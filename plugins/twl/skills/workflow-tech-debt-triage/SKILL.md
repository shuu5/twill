---
name: dev:workflow-tech-debt-triage
description: |
  tech-debt Issue の全件棚卸しワークフロー。

  Use when user: says tech-debt/技術的負債/棚卸し/triage,
  or when maintenance is needed.
type: workflow
effort: medium
spawnable_by:
- user
---

# tech-debt 棚���し Workflow

**tech-debt Issue の全件棚卸しワークフロー。**

## 使用方法

```
/twl:workflow-tech-debt-triage
```

---

## フロー制御（MUST）

以下の順序で**必ず**実行する:

### Step 1: tech-debt Issue 全件取得

```bash
gh issue list --label tech-debt/warning --state open --json number,title,body,labels --limit 50
gh issue list --label tech-debt/deferred-high --state open --json number,title,body,labels --limit 50
```

2つのコマンドで取得し、number で重複除去して統合リストを作成する。

**0件の場合**: 「tech-debt Issue はありません」と通知して終了。
**50件超の場合**: 取得件数の上限（各ラベル50件）に達した旨をユーザーに通知し、取得分のみで棚卸しを続行する。

### Step 2: 解決済み検出

各 tech-debt Issue のタイトルから主要キーワード（名詞・固有名詞）を抽出し、`openspec/specs/*/spec.md` 内の Requirement 名・Scenario 名と照合する。

```bash
# キーワードごとに検索
grep -rli -F -- "$KEYWORD" openspec/specs/*/spec.md 2>/dev/null
```

- 部分文字列一致（大文字小文字区別なし）で対応 spec が見つかった Issue → 「解決済み」
- 最大3件まで表示。4件以上は「他 N 件」と件数のみ

### Step 3: 統合候補検出

解決済みに該当しなかった Issue について、タイトル・本文の主要キーワードを相互比較し、同一モジュール・機能に関する複数 Issue をグルーピングする。

判定基準:
- タイトルの主要キーワード（名詞・固有名詞・ファイルパス・コンポーネント名）が2つ以上一致する Issue 群 → 統合候補グループ
- 1グループ最低2件で成立
- モジュール判定: `modules.yaml` の paths 定義またはファイルパスのディレクトリ名で判定

### Step 4: 不適切検出

統合候補にも該当しなかった Issue について、参照する機能・コンポーネントがプロジェクトに存在するか確認する。

- 言及されているファイルパス・モジュール名がプロジェクト内に存在しない → 「不適切」
- クローズ理由を生成

### Step 5: 要継続分類

上記いずれにも該当しなかった Issue → 「要継続」（アクション不要）。

### Step 6: 一括処理（triage-execute に委譲）

分類結果（4カテゴリのリスト）を `/twl:triage-execute` に渡して実行を委譲する。
triage-execute が結果表示・ユーザー確認・一括処理・完了サマリーを担当する。

---

## ラベル判定

| 要望の種類 | ラベル |
|-----------|--------|
| tech-debt（Warning由来） | `tech-debt/warning` |
| tech-debt（High/Critical由来） | `tech-debt/deferred-high` |

---

## 禁止事項（MUST NOT）

- **ユーザー確認なしでIssueをクローズ・統合してはならない**
- **Issue番号を推測してはならない**: gh出力から正確に取得
