---
name: dev:ref-deps-format
description: AT対応deps.yaml形式仕様
type: reference
spawnable_by:
- controller
- atomic
---

<!-- Synced from twl docs/ — do not edit directly -->

# deps.yaml 形式仕様

## 基本構造

```yaml
version: "2.0"
plugin: {name}

entry_points:
  - skills/co-{purpose}/SKILL.md            # 各ワークフローに独立エントリーポイント

skills: { ... }
commands: { ... }
agents: { ... }
hooks: { ... }              # 任意
```

## calls と can_spawn の関係

`calls` と `can_spawn` は異なる目的のフィールド。混同注意。

| フィールド | 目的 | 影響範囲 |
|-----------|------|---------|
| **`can_spawn`** | この型が spawn できる**型名**のバリデーション | `twl check` の型ルール検証のみ |
| **`calls`** | このコンポーネントが実際に呼び出す**コンポーネント名** | **SVG 依存グラフのエッジ生成** + orphan 検出 |

### 重要なルール

1. **`can_spawn` には型名**を指定（例: `specialist`, `atomic`）
   - 誤: `can_spawn: [researcher]`（コンポーネント名）→ バリデーションエラー
   - 正: `can_spawn: [specialist]`（型名）

2. **`calls` にはコンポーネント名**を `{section}: {name}` 形式で指定
   - `calls` に含まれないコンポーネントは **SVG グラフでエッジが描画されない**
   - Task tool で spawn するエージェントも `calls` に含める必要がある

3. **サブエージェント/specialist を spawn する controller は、`calls` に `- agent: {name}` を追加**すること
   - `can_spawn: [specialist]` だけでは SVG に反映されない

4. **calls 階層原則**: controller の calls には `composite` を含め、composite が管理する `specialist` は含めない
   - specialist の依存は `composite → specialist` の calls で表現する
   - 理由: SVG は設計時の構成関係を表す。controller→composite→specialist の階層が実際のワークフローと一致する
   - 誤: controller の calls に `- agent: worker-a`（composite が管理する specialist を直接含める）
   - 正: controller の calls に `- command: phase-review`、composite の calls に `- agent: worker-a`

## セクション別属性

### skills セクション

#### controller
```yaml
co-search:                                  # co-{purpose} 形式
  type: controller
  path: skills/co-search/SKILL.md
  spawnable_by: [user]
  can_spawn: [specialist]                   # 型名を指定
  calls:
    - agent: researcher                     # spawn する specialist
    - agent: critic                         # spawn する specialist
    - reference: ref-search-strategy
```

#### workflow
```yaml
# デフォルト: controller から呼び出し
workflow-review:
  type: workflow
  path: skills/workflow-review/SKILL.md
  spawnable_by: [controller]
  can_spawn: [composite, specialist]
  user-invocable: false                  # デフォルト推奨
  calls:
    - command: phase-review
    - agent: docs-researcher
```

```yaml
# user-invocable: ユーザーが直接実行可能
workflow-test-ready:
  type: workflow
  path: skills/workflow-test-ready/SKILL.md
  spawnable_by: [user]
  can_spawn: [composite, specialist]
  user-invocable: true                   # スキルマッチング対象
  calls:
    - command: test-scaffold
    - command: check
```

#### reference
```yaml
checkpoint-task:
  type: reference
  path: skills/checkpoint-task/SKILL.md
  spawnable_by: [all]
```

### commands セクション

#### composite
```yaml
phase-review:
  type: composite
  path: commands/phase-review.md
  spawnable_by: [workflow, controller]
  parallel: true              # specialist 並列起動
  calls:
    - agent: worker-a
    - agent: worker-b
```

#### atomic
```yaml
init:
  type: atomic
  path: commands/init.md
  spawnable_by: [workflow, controller]
```

### agents セクション

#### specialist
```yaml
worker-a:
  type: specialist
  path: agents/worker-a.md
  model: sonnet               # モデル指定
  checkpoint: true            # チェックポイント有無
  checkpoint_ref: checkpoint-task  # CP reference名
  spawnable_by: [composite, controller]
  tools: [Read, Grep, Glob]   # 利用可能ツール
  skills: [checkpoint-task]    # 参照するreference
```

## hooks（任意）

```yaml
hooks:
  TaskCompleted:
    action: validate           # validate | notify | ignore
    validation: [lint_check, test_pass]
```

## エントリーポイント設計

### 原則: 各ワークフローが独立エントリーポイント

ルーティングテーブル（トリガーフレーズ→コマンド対応表）を持つ単一 `co-entry` は**非推奨**。
理由: コントローラー全体がコンテキストに読み込まれるため、AIは文脈から適切なワークフローを判断できる。ルーティング層は冗長でトークンの無駄。

代わりに、各ワークフローを `co-{purpose}` として独立定義する:

```yaml
entry_points:
  - skills/co-create/SKILL.md
  - skills/co-improve/SKILL.md
  - skills/co-migrate/SKILL.md
```

### 各コントローラーの設計

- frontmatter の `description` にトリガーフレーズを含める（Claude Code のスキルマッチングで処理）
- 本体はワークフロー実行ロジックのみ（ルーティングテーブル不要）
- 単一ワークフローでも具体名を使用（例: `co-search`）

各エントリーの description でユーザーが選択できるよう役割を明記すること。

## 最小例（完全動作）

```yaml
version: "1.0"
plugin: example
entry_points: [skills/co-analyze/SKILL.md]

skills:
  co-analyze:                               # co-{purpose} 形式
    type: controller
    path: skills/co-analyze/SKILL.md
    spawnable_by: [user]
    can_spawn: [composite, specialist]
    calls: [{ command: phase-work }, { command: init }]
  checkpoint-task:
    type: reference
    path: skills/checkpoint-task/SKILL.md
    spawnable_by: [all]

commands:
  phase-work:
    type: composite
    path: commands/phase-work.md
    spawnable_by: [controller]
    parallel: true
    calls: [{ agent: worker-a }]
  init:
    type: atomic
    path: commands/init.md
    spawnable_by: [controller]

agents:
  worker-a:
    type: specialist
    path: agents/worker-a.md
    model: sonnet
    checkpoint: true
    checkpoint_ref: checkpoint-task
    spawnable_by: [composite, controller]
    tools: [Read, Grep, Glob]
    skills: [checkpoint-task]
```
