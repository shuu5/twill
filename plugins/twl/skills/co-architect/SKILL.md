---
name: twl:co-architect
description: |
  対話的アーキテクチャ構築ワークフロー。
  explore を活用し architecture/ に設計意図を段階的にキャプチャ。
  完全性チェックまで実行し、Issue 化は co-issue に委譲。

  Use when user: says アーキテクチャ設計/architecture/全体設計,
  says 設計を構造化したい/Context分解/Phase計画,
  says --group/グループ深堀り/スケルトン精緻化.
type: controller
effort: high
tools: [Agent(worker-architecture, worker-structure), AskUserQuestion, Read, Skill, Write]
- Agent(worker-architecture, worker-structure)
spawnable_by:
- user
maxTurns: 60
---

# co-architect

対話的アーキテクチャ構築 → 完全性チェック → Issue 候補分解。Non-implementation controller（chain-driven 不要）。

## Step 0: --group 分岐

`--group <context-name>` が含まれる場合:
→ `/twl:architect-group-refine <context-name>` を実行して終了（Step 1〜8 スキップ）。

`--group` なし → Step 1 へ。

## Step 1: コンテキスト収集

TaskCreate 「Architecture: コンテキスト収集」(status: in_progress)

プロジェクト概要を把握:
- README.md, CLAUDE.md, パッケージマネージャ設定を Read
- 既存 `architecture/` があれば Read して現状把握
- なければ `architecture/` ディレクトリを作成

TaskUpdate → completed

## Step 2: 対話的アーキテクチャ探索

TaskCreate 「Architecture: 対話的探索」(status: in_progress)

`/twl:explore` を Skill tool で呼び出す。以下をコンテキストとして注入:

> アーキテクチャ探索モード: DDD の Bounded Context、ユビキタス言語、Context Map を使い設計を構造化。
> 確定した設計事項は architecture/ の対応ファイルに Write:
> - ビジョン → `architecture/vision.md`
> - ドメインモデル → `architecture/domain/model.md`
> - 用語定義 → `architecture/domain/glossary.md`
> - Bounded Context → `architecture/domain/contexts/<name>.md`
> - 設計判断 → `architecture/decisions/<NNNN>-<title>.md`
> - API 境界 → `architecture/contracts/<name>.md`

TaskUpdate → completed

## Step 3: 完全性チェック

TaskCreate 「Architecture: 完全性チェック」(status: in_progress)

`/twl:architect-completeness-check` を実行。

WARNING がある場合 → ユーザーに不足箇所を提示し補完するか確認。
補完する場合 → Step 2 に戻り explore を再開。

TaskUpdate → completed

```
>>> Architecture spec 作成完了

次のステップ:
  - Issue 化: /twl:co-issue で architecture spec ベースに Issue 群を作成
  - autopilot: /twl:co-autopilot で Issue 群を一括実装
```

## 禁止事項（MUST NOT）

- ユーザーの設計判断を代替してはならない（UX ルール。提案は可、決定はユーザー）
- controller 内に実質処理を記述してはならない（設計ルール。atomic に委譲）

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
