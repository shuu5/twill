---
name: twl:ref-issue-quality-criteria
description: |
  Issue 品質レビュー specialist（issue-critic, issue-feasibility）が使用する品質基準。
  severity 判定基準、category 定義、過剰 CRITICAL 防止ルールを定義。
type: reference
---

# ref-issue-quality-criteria

Issue 品質レビュー specialist（issue-critic, issue-feasibility）が使用する品質基準。

## severity 判定基準

### CRITICAL（Phase 4 ブロック）

以下の場合のみ CRITICAL を使用する。confidence >= 80 で Phase 4 進行不可となるため、慎重に判定すること。

| 条件 | 例 |
|------|-----|
| スコープが不明確で実装不可能 | 「含む」セクションにファイルパスも機能範囲も記載なし |
| 対象ファイルが存在しない | スコープに記載されたファイルパスが実在しない |
| 粒度が過大で 1 PR に収まらない | 推定変更ファイル数 > 10、複数の独立した関心事を含む |
| 矛盾する要件 | AC の項目間で論理的矛盾がある |

### WARNING（ユーザー提示、修正任意）

| 条件 | 例 |
|------|-----|
| 受け入れ基準が定量的でない | 「適切に動作する」「パフォーマンスが良い」 |
| 暗黙の仮定がある | 特定の API/スキーマの存在を前提としているが明記なし |
| スコープの暗黙除外 | 「含まない」が明示されていない隣接機能 |
| 影響範囲の見落とし可能性 | 変更対象の呼び出し元が Issue body に言及なし |
| deps.yaml 更新への言及なし | 新規コンポーネント追加時 |
| 依存関係が未特定 | 先行 Issue や外部サービスへの依存が暗黙的 |

### INFO（ログのみ、action 不要）

| 条件 | 例 |
|------|-----|
| 改善提案 | より良い分割案、代替実装アプローチ |
| 補足情報 | 関連する既存コンポーネントの情報 |
| 軽微な記述改善 | 文言の明確化提案 |

## 過剰 CRITICAL 防止ルール（MUST）

- 軽微な曖昧さ（「適切に」程度の表現）は WARNING とする。CRITICAL にしてはならない
- CRITICAL は Phase 4 進行をブロックするため、真に実装不可能な問題にのみ使用する
- 迷った場合は WARNING を選択する
- confidence が 80 未満の CRITICAL は実質的にブロックしないが、severity 選択は問題の深刻度で判断する

## category 定義

| category | specialist | 用途 |
|----------|-----------|------|
| `assumption` | issue-critic | 未検証の仮定、暗黙の前提条件 |
| `ambiguity` | issue-critic | 曖昧な記述、定量化されていない基準 |
| `scope` | issue-critic | 粒度過大、split 提案、スコープ境界不明確 |
| `feasibility` | issue-feasibility | 実装可能性、影響範囲、コードベースとの乖離 |

## split 提案ガイドライン

- split 提案は `category: scope` の finding として出力
- 具体的な分割案を message に含める（「A と B を分割」のような漠然とした提案は不可）
- split 後の各 Issue が独立して実装可能であることを確認
- 最大 1 ラウンドの split のみ適用（再帰防止）
