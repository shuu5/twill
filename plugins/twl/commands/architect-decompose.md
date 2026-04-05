# architect-decompose

architecture/ の domain/contexts/ と phases/ から Issue 候補リストを生成し、5項目の整合性チェックを実行する。

## 入力

- `architecture-dir-path`（省略時: `$(git rev-parse --show-toplevel)/architecture`）

## 手順

### 1. Context と Phase の読み取り

- `domain/contexts/*.md` を全件 Read → Context 一覧と依存関係を抽出
- `phases/*.md` を全件 Read → Phase 計画と Issue 候補を抽出

### 2. Issue 候補リスト生成

各 Phase の `## Issues` テーブルから Issue 候補を構造化:

| フィールド | 説明 |
|-----------|------|
| タイトル | Issue のタイトル |
| スコープ | 関連する Context 名（複数可）。`ctx/<name>` ラベルに直接マッピングされる |
| Phase | 所属 Phase 番号 |
| 依存 Issue | 先行して完了が必要な Issue（同一/先行 Phase 内） |

> **ラベル対応**: スコープ列の値は architect-issue-create で `ctx/<name>` ラベルとして付与される（例: スコープ `auth` → ラベル `ctx/auth`）。

### 3. 5項目整合性チェック

以下の5項目を検証し、各項目に PASS/WARNING を付与:

#### 3.1 Coverage
全 Bounded Context が少なくとも1つの Issue 候補のスコープに含まれ、かつ Phase 計画のいずれかの Issue に含まれるか。
- PASS: 全 Context がカバーされている
- WARNING: 未カバー Context を報告（Issue スコープ未参照 or Phase テーブル未記載）

#### 3.2 依存一貫性
Context 間の依存方向と Phase 順序が矛盾しないか。
- Context A が Context B に依存（upstream）→ Context B を含む Issue が同一または先行 Phase にあるか
- WARNING: 逆方向依存（後続 Phase の Issue に依存）を報告

#### 3.3 重複
複数 Issue が同一スコープ（同じ Context のみ）を持たないか。
- WARNING: 重複 Issue を報告し統合を提案

#### 3.4 Phase 適合
各 Issue の依存先が先行 Phase（または同一 Phase 内の先行 Issue）に配置されているか。
- WARNING: 後続 Phase の Issue に依存している Issue を報告

#### 3.5 グループ妥当性
並列実行可能な Issue（相互依存なし）が同一 Phase にまとまっているか。
- INFO: Phase 間にまたがる並列実行可能な Issue を報告（最適化提案）

### 4. 結果出力

```
## Issue 候補リスト

### Phase 1
| # | タイトル | スコープ | 依存 |
|---|---------|---------|------|
| 1 | ... | auth, user | - |
| 2 | ... | payment | #1 |

### Phase 2
...

## 整合性チェック結果

| # | チェック項目 | 結果 | 詳細 |
|---|------------|------|------|
| 1 | Coverage | PASS | 全 5 Context カバー済み |
| 2 | 依存一貫性 | PASS | 矛盾なし |
| 3 | 重複 | WARNING | Issue #3 と #5 が同一スコープ |
| 4 | Phase 適合 | PASS | 依存順序に矛盾なし |
| 5 | グループ妥当性 | INFO | Issue #2, #3 は並列実行可能 |

### WARNING 詳細
- [WARNING] 重複: Issue #3 "認証API" と #5 "認証テスト" が auth のみをスコープとする → 統合検討
```

### 5. ユーザー確認

AskUserQuestion で候補リストの承認を求める:
- 承認 → 候補リスト確定
- 修正指示 → 候補リストを更新し、整合性チェックを再実行

## 禁止事項

- Issue の自動作成は行わない（候補リスト生成と整合性チェックのみ）
- WARNING を自動修正しない（報告のみ）
