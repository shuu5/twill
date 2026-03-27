## Context

loom-plugin-dev は旧 dev plugin (claude-plugin-dev) の後継として新規構築するプロジェクト。architecture/ ディレクトリには既に以下が存在する:

- vision.md: 設計哲学、制約、非目標
- domain/: ドメインモデル、コンテキストマップ、用語集、6 Bounded Context 定義
- decisions/: ADR-001〜005（autopilot-first, controller 統合, 統一状態ファイル, 出力標準化, self-improve review）
- contracts/: autopilot-pr-cycle.md
- phases/: Phase 1 (B-1〜B-7), Phase 2 (C-1〜C-6)

Issue #3 の AC に対する既存文書のカバレッジ:
- ✅ 機械/LLM 境界、controller 責務、旧 controller 吸収先、状態遷移図
- ⬜ コンポーネントマッピング表、OpenSpec シナリオ、specialist スキーマ仕様、model 割り当て表、bare repo 検証ルール、worktree 安全ルール、B-3/C-4 スコープ境界

## Goals / Non-Goals

**Goals:**

- architecture/ に不足するドキュメントを追加し、Issue #3 の全 AC を満たす
- 旧 dev plugin の全コンポーネント（controller 9, workflow 7, atomic 30, specialist 27, script 15, reference 5）→ 新 loom-plugin-dev へのマッピング表を作成
- 主要ワークフロー 3 本（autopilot lifecycle, merge-gate, project create）の OpenSpec シナリオを作成
- specialist 共通出力スキーマの詳細仕様を明文化
- model 割り当て表と判定基準を明文化
- bare repo 構造検証ルール・worktree ライフサイクルルールを明文化
- B-3/C-4 スコープ境界を明文化

**Non-Goals:**

- コード実装（設計文書の作成のみ）
- loom CLI 側の機能要件定義（shuu5/loom リポジトリの責務）
- deps.yaml や SKILL.md の作成（後続 Issue B-2 以降）

## Decisions

### D1: ドキュメント配置戦略

新規ドキュメントは既存の architecture/ 構造に統合する:

| ドキュメント | 配置先 | 形式 |
|---|---|---|
| コンポーネントマッピング表 | `architecture/migration/component-mapping.md` | テーブル形式 |
| OpenSpec シナリオ | `openspec/specs/` (deltaspec) | WHEN/THEN 形式 |
| Specialist 共通出力スキーマ | `architecture/contracts/specialist-output-schema.md` | JSON スキーマ + 説明 |
| Model 割り当て表 | `architecture/decisions/ADR-004-output-standardization.md` に追記 | テーブル形式 |
| Bare repo 検証ルール | `architecture/domain/contexts/project-mgmt.md` に追記 | チェックリスト形式 |
| Worktree ライフサイクルルール | `architecture/domain/contexts/autopilot.md` に追記 | ルール表形式 |
| B-3/C-4 スコープ境界 | `architecture/migration/scope-boundary.md` | 分類テーブル |

### D2: コンポーネントマッピングの粒度

旧 plugin の全コンポーネントを以下のカテゴリで分類:
- **吸収**: 新コンポーネントに統合（名称変更含む）
- **削除**: 新アーキテクチャで不要になるもの
- **移植**: ロジック維持でインターフェースのみ適応
- **新規**: 旧にない新コンポーネント

### D3: OpenSpec シナリオの範囲

AC に記載の 3 ワークフローのみ:
1. **Autopilot lifecycle**: co-autopilot → plan.yaml 生成 → Phase ループ → 完了サマリー
2. **merge-gate**: 動的レビュアー構築 → 並列 specialist → 結果集約 → 判定
3. **project create**: co-project → bare repo → worktree → テンプレート → OpenSpec

### D4: 既存ドキュメントへの追記方針

既存の ADR・context 文書は内容を変更せず、不足セクションの追記のみ行う。既存のセクション構造や判断は維持する。

## Risks / Trade-offs

### R1: マッピング表の網羅性

旧 plugin のコンポーネント一覧は claude-plugin-dev リポジトリの deps.yaml に依存。アクセスできない場合は Issue #3 の body に記載された数値（controller 9, workflow 7 等）を基に構成する。

**軽減策**: Issue body に記載された設計判断を SSOT として使用。

### R2: OpenSpec シナリオの抽象度

設計段階のシナリオは実装時に詳細が変わる可能性がある。

**軽減策**: WHEN/THEN を主要な判断分岐に限定し、実装詳細はステップレベルで記述しない。後続 Issue で必要に応じて DeltaSpec で更新する。

### R3: 既存文書との重複

specialist 出力スキーマは ADR-004 に概要が記載済み。別ファイルに詳細仕様を書くと情報が分散する。

**軽減策**: ADR-004 は「判断の根拠」、contracts/specialist-output-schema.md は「実装仕様」として役割を分ける。ADR-004 から specialist-output-schema.md を参照リンクする。
