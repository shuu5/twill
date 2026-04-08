---
type: atomic
tools: [Bash, AskUserQuestion, Read, SendMessage, WebFetch, WebSearch]
effort: low
maxTurns: 10
---
# evaluate-architecture: アーキテクチャパターン評価

## 目的
プラグイン設計（deps.yaml ドラフトまたは既存）のアーキテクチャパターン適用状態を評価し、最適化を提案する。create/migrate のdesign後に実行するatomicコマンド。

## 入力
- 会話コンテキスト内の deps.yaml ドラフト、または `plugin_path` 引数

## 手順

### 1. deps.yaml 取得
会話コンテキストから deps.yaml ドラフトを取得。
`plugin_path` 引数がある場合は `{plugin_path}/deps.yaml` を Read。

### 2. 構造抽出
以下を抽出:
- `team_config`（lifecycle, max_size, external_context）
- entry_points
- 全コンポーネントの型分布
- controller の calls 順序（パイプライン長）

### 3. 7パターン評価
ref-architecture のチェックリストに照合:

**AT並列レビュー**:
- team-phase + parallel: true の存在確認
- atomic コマンド内に独立分析ステップが3つ以上ないか

**パイプライン**:
- calls の順序と依存関係
- 4ステップ以上で Context Snapshot が未導入ではないか

**ファンアウト/ファンイン**:
- team-phase の workers 構成
- 統合ロジックの有無

**Context Snapshot**:
- 4ステップ以上のワークフローでの定義有無
- 初期化・クリーンアップの定義

**Subagent Delegation**:
- WebFetch/WebSearch を使用するコマンドの specialist 委任状態
- specialist の context: isolated 設定

**Session Isolation**:
- per_phase ライフサイクルで snapshot_dir/team_name にsession_id が付加されているか
- session-info.json の生成・管理が定義されているか

**Compaction Recovery**:
- per_phase + 5ステップ以上で team-state.json 管理が定義されているか
- worker に Dual-Output（Write + SendMessage）が指示されているか
- controller に復帰判定ロジックがあるか

### 4. 横断チェック
- lifecycle 妥当性
- max_size 整合性
- パターン組合せ安全性
- **エントリーポイント設計**: 単一 `controller-entry` にルーティングテーブルがないか → `controller-{purpose}` への分割を推奨

### 5. 結果出力
ref-architecture の報告フォーマットで評価結果を出力。

### 6. ユーザー確認
AskUserQuestion で推奨アクションの適用を確認:
- **YES**: design 修正指示を出力（具体的な deps.yaml / SKILL.md の変更案）
- **NO**: 現状の設計で続行

## 出力
アーキテクチャ評価レポート + 推奨アクション（ユーザー承認時は修正指示）
