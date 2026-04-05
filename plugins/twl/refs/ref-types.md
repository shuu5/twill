---
name: dev:ref-types
description: 型システム仕様
type: reference
spawnable_by:
- controller
- atomic
---

<!-- Synced from twl docs/ — do not edit directly -->

# Loom 型システム仕様

## 統合型テーブル

| 型 | section | can_spawn | spawnable_by |
|----|---------|-----------|--------------|
| **controller** | skills | workflow, composite, atomic, specialist, reference | user |
| **workflow** | skills | composite, atomic, specialist | controller, user |
| **composite** | commands | specialist | workflow, controller |
| **atomic** | commands | reference | workflow, controller |
| **specialist** | agents | (なし) | workflow, composite, controller |
| **reference** | skills | (なし) | all |

### 特殊 spawnable_by 値

| 値 | 意味 |
|----|------|
| `user` | ユーザー直接呼び出し（controller のエントリーポイント、または user-invocable workflow） |
| `all` | 全型から参照可能（reference 専用） |
| `agents.skills` | エージェント frontmatter `skills:` 経由で reference を参照 |

## 型の責務

### controller (skills/)
- **責務**: セッション管理 + ワークフローチェーン + adaptive context engineering。複数 workflow のセッション分離制御、Task tool で specialist を直接 spawn、workflow で段階制御
- **記載内容**: ワークフロー実行ロジック（ステップチェーン / フロー制御）。発火トリガーは frontmatter description に記載し、スキルマッチングに委任
- **can_spawn**: workflow, composite, atomic, specialist, reference
- **spawnable_by**: user
- **calls に spawn 先を記載**: `calls` に `- agent: {specialist名}` を追加（SVG エッジ生成に必要）

### workflow (skills/)
- **責務**: フロー制御（順序・条件分岐・ループ）。controller から呼ばれるか、個別に user-invocable として直接実行可能。composite/atomic/specialist を制御
- **記載内容**: フェーズ遷移ロジック、中間結果の引き継ぎ
- **can_spawn**: composite, atomic, specialist
- **spawnable_by**: controller, user
- **frontmatter**: `user-invocable: false`（デフォルト推奨。user-invocable にする場合は `true` に変更）

### composite (commands/)
- **責務**: specialist spawn 指示を含む実行ロジック（lead session への spawn 指示書）
- **記載内容**: specialist spawn テンプレート、結果統合ロジック、次のステップ
- **can_spawn**: specialist
- **spawnable_by**: workflow, controller
- **frontmatter**: `allowed-tools: Read, Task, ...`
- **実行パターン**: controller (lead session) がこのコマンドの指示に従って Task tool で specialist を spawn する。composite 自身が独立実行されるのではない

### specialist (agents/)
- **責務**: サブエージェントとして spawn される実行者（Task tool 経由）
- **記載内容**: 完結したタスク指示、ツール制約、出力先
- **can_spawn**: なし（Task tool 禁止）
- **spawnable_by**: workflow, composite, controller
- **frontmatter**: `tools: [Read, Grep, Glob, ...]`

### atomic (commands/)
- **責務**: 単一タスクの実行ロジック（specialist spawn を含まない。リーダー直接実行）
- **can_spawn**: reference
- **spawnable_by**: workflow, controller

### reference (skills/)
- **責務**: 知識提供（チェックポイント定義含む。全コンポーネントから自動参照）
- **can_spawn**: なし
- **spawnable_by**: 全型から参照可能

## calls と can_spawn

`calls` と `can_spawn` は目的が異なる:

- **`can_spawn`**: この型が spawn できる**型名**を列挙。`twl check` でバリデーションに使用
- **`calls`**: 実際に呼び出す**コンポーネント名**を列挙。**SVG 依存グラフのエッジ生成**に使用

specialist を Task tool で spawn する場合、`can_spawn: [specialist]` だけでなく `calls: [{ agent: {名前} }]` も必要。
`calls` がないと SVG グラフで接続されず、orphan 検出の対象になる。

### can_spawn と calls の区別

- **`can_spawn`** = 型レベルの**実行権限**。runtime でどの型を spawn できるかを宣言
- **`calls`** = コンポーネントレベルの**設計依存**。SVG の構成関係エッジを生成

can_spawn に含まれる型でも、calls に書くべきとは限らない:
- controller の can_spawn に `specialist` が含まれるのは、lead session として Task() を実行する権限があるため
- しかし calls には `composite` を含め、`specialist` は含めない（composite が管理するため）
- SVG は設計時の構成関係を表す。controller が composite を介して specialist を管理する事実を正確に反映する

### Reference 配置ルール

reference の calls 宣言は **実際に参照するコンポーネント** に置く:

| パターン | 判定 | 理由 |
|---------|------|------|
| controller calls ref, controller 自身が本文で参照 | OK | 直接利用 |
| controller calls ref, 下流 atomic/specialist が参照 | NG | ref は controller コンテキストのみ、atomic に到達しない |
| atomic calls ref, atomic が本文で参照 | OK | 直接利用 |

**判定基準**: calls に reference を宣言するなら、そのコンポーネントの本文中に ref の内容を参照する記述がなければならない。「将来使うかも」の予約的宣言は禁止。

### allowed-tools / tools 正確性ルール

frontmatter の `allowed-tools`（commands）/ `tools`（agents）は本文の実際のツール使用と一致させる:

| 状態 | 判定 | 対処 |
|------|------|------|
| body で `mcp__xxx__yyy` 使用、frontmatter に未宣言 | NG | frontmatter に追加 |
| frontmatter に宣言、body で未使用 | Warning | 削除を検討 |
| frontmatter と body が一致 | OK | — |

## 階層図

```
user → controller (= lead session)
         ├─ workflow ─┬─→ composite → specialist (Task tool で spawn)
         │            ├─→ specialist (workflow が直接 spawn も可)
         │            └─→ atomic → reference
         ├─ composite ────────→ specialist (Task tool で spawn)
         ├─ specialist (controller が直接 spawn も可)
         ├─ atomic ───────────→ reference
         └─ reference
```

## Frontmatter テンプレート

| 型 | name | 固有フィールド |
|----|------|---------------|
| controller | `{plugin}:co-{purpose}` | - |
| workflow | `{plugin}:workflow-{purpose}` | `user-invocable: false`（デフォルト推奨） |
| composite | (なし) | `allowed-tools: Read, Task, ...` |
| specialist | `{agent-name}` | `tools: [Read, Grep, Glob, ...]` |
| atomic | (なし) | `allowed-tools: Read, Bash` |
| reference | `{plugin}:checkpoint-ref` | - |

## 命名規則

- プラグイン名: `{name}`（例: dev, paper, research）
- co-* prefix: `/{name}:co-` で検索性確保
- controller は複数定義可能（各エントリーの description で役割を明確化）
- **命名**: `co-{purpose}`（purpose はワークフローの目的を示す具体名）
  - 例: `co-create`, `co-improve`, `co-search`
  - **非推奨**: `co-entry`（単一エントリーにルーティングテーブルを持つパターン）
  - 単一ワークフローでも具体名を使用（例: `co-search`、`co-main` は避ける — purpose が汎用すぎるとスキルマッチング精度が低下するため）
