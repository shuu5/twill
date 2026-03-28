## Context

loom-plugin-dev の 4 co-* controllers は B-1〜B-7 で作成された stub 状態。旧 claude-plugin-dev の 9 controllers から機能を移植し、chain-driven + autopilot-first アーキテクチャに適合させる。

前提:
- deps.yaml v3.0 が SSOT（B-2 確定済み）
- 統一状態ファイル issue-{N}.json / session.json（B-3 確定済み）
- chain-driven workflow-setup / workflow-pr-cycle（B-4, B-5 確定済み）
- specialist 共通出力スキーマ（B-6 確定済み）
- self-improve-review hook（B-7 確定済み）
- architecture/ の 6 Bounded Context 定義が設計の SSOT

## Goals / Non-Goals

**Goals:**

- 4 controllers の SKILL.md を完全実装（stub → 本実装）
- 旧 5 controllers の機能を吸収先に正しく組み込む
- Non-implementation controller（co-issue, co-project, co-architect）は SKILL.md 内で Step 順序を自然言語定義（chain-driven 不要）
- Implementation controller（co-autopilot）は chain-driven workflow 経由
- co-issue 用 Issue テンプレート（bug.md, feature.md）を移植
- deps.yaml の can_spawn 等を実装に合わせて更新

**Non-Goals:**

- atomic/composite コマンドの新規実装（既に B-3〜B-5 で完了済み、または C-2 以降で対応）
- specialist エージェントの実装（C-3 で対応）
- scripts の新規実装（B-3 で完了済み）
- 旧 plugin リポジトリのファイル削除

## Decisions

### D1: SKILL.md の構造

各 SKILL.md は以下の構造で統一する:

```
---
frontmatter (name, description, type, spawnable_by)
---
# タイトル
## Step 0: 引数解析 / モード分岐（該当 controller のみ）
## Step N: 各処理ステップ
## エラーハンドリング
## 禁止事項（MUST NOT）
```

### D2: co-autopilot の self-improve 統合方式

旧 controller-self-improve のフローを co-autopilot に直接組み込まず、以下の方式で統合:
- autopilot-patterns（既存 atomic）が self-improve Issue を検出した際に ECC 照合を自動追加
- session.json の `self_improve_issues` フィールドに記録
- 旧 controller-self-improve の独立フロー（collect → propose → apply → close）は co-autopilot の Phase ループ内に吸収

### D3: co-project の 3モードルーティング

Step 0 で引数からモードを判定し、各モードの Step セットに分岐:
- `create`: project-create → governance → Board 作成
- `migrate`: project-migrate → governance 再適用
- `snapshot`: snapshot-analyze → classify → generate

### D4: co-issue の explore-summary 統合

B-7 で追加された stub を実装。起動時に `.controller-issue/explore-summary.md` を確認し、存在すれば Phase 1 スキップを提案。

### D5: TaskCreate/TaskList による進捗管理

長時間ワークフロー（co-autopilot の Phase ループ、co-issue の 4 Phase、co-architect の 9 Step）で TaskCreate を使用し、ユーザーが CLI 上でリアルタイム進捗確認可能にする。

### D6: Issue テンプレート配置

co-issue が参照する Issue テンプレートを `refs/` に配置:
- `refs/ref-issue-template-bug.md`
- `refs/ref-issue-template-feature.md`

## Risks / Trade-offs

### R1: SKILL.md 肥大化リスク

co-autopilot と co-project は責務が広い。ADR-002 の bloat 基準（200行以下）に収めるため、詳細ロジックは既存の atomic/composite コマンドに委譲し、SKILL.md はオーケストレーションフローのみ記述する。

### R2: 旧 plugin との機能差分

移植時に旧 plugin の全機能を 1:1 で再現するのではなく、chain-driven アーキテクチャに適合する形に再設計する。一部の旧機能（例: controller-plugin の interview → research → design → generate フロー）は co-project のテンプレート方式に置き換えられ、挙動が変わる。

### R3: 未実装 atomic コマンドへの依存

一部の atomic コマンド（issue-create, issue-structure, issue-dig 等）は C-2 以降で実装予定。SKILL.md では呼び出しを定義するが、実際の動作は C-2 完了後となる。
