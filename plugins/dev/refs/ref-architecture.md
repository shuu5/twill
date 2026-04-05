---
name: dev:ref-architecture
description: アーキテクチャパターン評価チェックリスト
type: reference
spawnable_by:
- controller
- atomic
---

<!-- Synced from loom docs/ — do not edit directly -->

# Loom アーキテクチャパターン評価チェックリスト

## 対象パターン（7種）

### パターン1: 並列レビュー（composite + specialist）

**検出方法**:
- deps.yaml に `composite` + `parallel: true` が存在
- 対応する `specialist` が agents/ に存在

**ギャップ検出**:
- atomic コマンド内に独立した分析ステップが3つ以上 → 並列化の候補
- 単一コマンドで複数の独立チェック（構造+原則等）を逐次実行している

**アンチパターン**:
- specialist 間で同一ファイルを変更している（並列安全違反）
- 過剰な specialist 数（同時起動が多すぎる設計）
- 並列化の価値がないタスク（依存関係のあるステップ）を specialist 化
- **controller の calls に composite が管理する specialist を直接含める**（設計依存と構成が不一致、SVG が冗長）

### パターン2: パイプライン

**検出方法**:
- controller の calls に順序依存のコマンドが連鎖している
- 前ステップの出力が次ステップの入力になっている

**ギャップ検出**:
- ステップ間の順序が論理的に不正（前提条件を満たさない実行順）
- 不要な中間ステップが存在する（スキップ可能）

**アンチパターン**:
- 4ステップ以上のパイプラインで Context Snapshot が未導入
- ステップ間のデータ受け渡しが会話コンテキストのみに依存

### パターン3: ファンアウト/ファンイン（composite ベース）

**検出方法**:
- composite がサブタスクを分割 → specialist を並列 spawn → 結果統合の構造を持つ
- specialists リストに2つ以上の specialist が定義されている

**ギャップ検出**:
- 逐次処理されているが、パーティション可能なタスクがある
- 入力データを分割して並列処理できる箇所がある

**アンチパターン**:
- 統合（ファンイン）ロジックが composite に定義されていない
- 分割基準が不明確で specialist 間の作業範囲が重複

### パターン4: Context Snapshot

**検出方法**:
- controller に `/tmp/` ディレクトリの初期化処理がある
- 各ステップで snapshot の Read/Write が定義されている

**ギャップ検出**:
- **4ステップ以上のワークフローで snapshot が未定義** → 導入推奨
- ステップ間のデータ引き継ぎが会話コンテキストのみに依存

**アンチパターン**:
- 3ステップ以下のワークフローへの過剰導入
- snapshot のクリーンアップ処理が未定義
- イテレーション時の上書き戦略が未定義

### パターン5: Subagent Delegation

**検出方法**:
- deps.yaml に `specialist` + `context: isolated` が定義されている
- controller の calls に specialist への委任がある

**ギャップ検出**:
- **WebFetch/WebSearch を使用するコマンドが specialist に委任されていない** → 委任推奨
- 大量データスキャンを controller のコンテキスト内で実行している

**アンチパターン**:
- ユーザー対話が必要なタスクを specialist に委任（対話不可）
- 結果だけでなく過程も必要なタスクを isolated で実行
- 過度な委任でオーバーヘッドが増大（小さなタスクの委任）

### パターン6: Session Isolation

**検出方法**:
- controller に session_id 生成処理（`uuidgen | cut -c1-8`）がある
- snapshot_dir パスに `{session_id}` が含まれている
- session-info.json の Write 処理がある

**ギャップ検出**:
- **per_phase ライフサイクルで snapshot_dir が固定パス** → Session Isolation 導入推奨

**アンチパターン**:
- persistent ライフサイクルへの過剰導入（衝突リスク低）
- 古いセッションの cleanup 処理が未定義

### パターン7: Compaction Recovery

**検出方法**:
- snapshot ディレクトリに specialists の結果出力がある
- controller に復帰判定ロジック（session-info.json + snapshot 読み込み → 分岐）がある

**ギャップ検出**:
- **per_phase + 5ステップ以上で復帰プロトコルが未定義** → Compaction Recovery 導入推奨
- specialist が結果をファイルに永続化していない

**アンチパターン**:
- 3ステップ以下の短いワークフローへの過剰導入
- 冪等性ルールが未定義（同じステップの重複実行リスク）

## 横断チェック

### calls 階層整合性
- controller の calls に specialist が含まれ、**同じ specialist が composite の calls にも含まれている** → 冗長。controller → specialist エッジは Subagent Delegation の場合のみ

### lifecycle 妥当性
- `per_phase` 時に外部コンテキスト手段が定義されているか
- `persistent` 時に specialist 数が適切か（3以下推奨）

### エントリーポイント設計
- 単一 `co-entry` にルーティングテーブル（トリガーフレーズ→コマンド対応表）がないか → 各ワークフローを `co-{purpose}` として分割推奨
- 各 controller の description にトリガーフレーズが含まれているか（スキルマッチング用）
- 各 controller が自身のワークフロー実行ロジックのみ持っているか（ルーティング層が混在していないか）
- controller 本文に「トリガー→アクション対応表」セクションが残存していないか → 削除してワークフロー直接制御に変換

### パターン組合せ安全性
- Context Snapshot + 並列レビュー → snapshot ファイルへの並列書き込みがないか
- 各 specialist は独立した snapshot キーに書き込むべき
- Subagent Delegation + 並列レビュー → specialist 間の作業範囲が重複していないか

## 報告フォーマット

```markdown
## アーキテクチャ検証結果
- **status**: completed | blocked
- **summary**: 1行要約

### パターン適用状態
| パターン | 状態 | 判定 | 詳細 |
|---------|------|------|------|
| 並列レビュー | 適用済/未適用/非該当 | OK/Warning/推奨 | ... |
| パイプライン | 適用済/未適用/非該当 | OK/Warning/推奨 | ... |
| ファンアウト/ファンイン | 適用済/未適用/非該当 | OK/Warning/推奨 | ... |
| Context Snapshot | 適用済/未適用/非該当 | OK/Warning/推奨 | ... |
| Subagent Delegation | 適用済/未適用/非該当 | OK/Warning/推奨 | ... |
| Session Isolation | 適用済/未適用/非該当 | OK/Warning/推奨 | ... |
| Compaction Recovery | 適用済/未適用/非該当 | OK/Warning/推奨 | ... |

### 検出された最適化機会
| 対象 | パターン | 推奨アクション | 重要度 |
|------|---------|---------------|--------|
| {コンポーネント名} | {パターン名} | {具体的なアクション} | Critical/Warning/Info |

### 横断チェック
| チェック項目 | 結果 | 詳細 |
|-------------|------|------|
| lifecycle妥当性 | OK/NG | ... |
| パターン組合せ安全性 | OK/NG | ... |
```
