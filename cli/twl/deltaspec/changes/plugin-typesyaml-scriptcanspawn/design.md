## Context

twl は Claude Code プラグインの構造定義・検証・可視化を行う CLI ツール。各 plugin は `deps.yaml` でコンポーネント間の依存関係を宣言し、`types.yaml` の型ルール（can_spawn/spawnable_by）に基づいて整合性を検証する。

現在の制約:
- deps.yaml の `calls` は同一 plugin 内のコンポーネントのみ参照可能
- `external` セクションは外部 CLI コマンド（非 plugin）への依存を表現するもので、他 plugin のコンポーネント参照には対応していない
- `script.can_spawn = []` のため、script→script の呼び出しが型ルール違反になる

## Goals / Non-Goals

**Goals:**

- deps.yaml の calls 内で `{plugin}:{component}` 形式による cross-plugin 参照構文を定義する
- `twl validate` が cross-plugin 参照の型整合性を検証する（参照先 plugin の deps.yaml を読み込み）
- `twl check` が cross-plugin 参照先のファイル存在を検証する
- types.yaml の `script.can_spawn` に `script` を追加する

**Non-Goals:**

- 各 plugin 側の deps.yaml を修正すること（各 plugin の Issue で対応）
- cross-plugin の循環参照検出（将来の拡張）
- plugin レジストリや自動探索機構の導入

## Decisions

### D1: Cross-plugin 参照構文は `plugin:component` 形式

calls 内で `{type_key}: "plugin:component"` と記述する。コロン `:` を含む値は cross-plugin 参照として解釈する。

```yaml
calls:
  - atomic: "session:session-state"  # session plugin の session-state コンポーネント
```

**理由**: 既存の calls 構文（`{type}: {name}`）と自然に統合でき、パース変更が最小限で済む。

### D2: 参照先 plugin の解決は `~/.claude/plugins/` からの探索

cross-plugin 参照時、`~/.claude/plugins/{plugin}/deps.yaml` を読み込んで参照先の型情報を取得する。plugin_root の親ディレクトリに `plugins/` がある前提。

**理由**: Claude Code の plugin は `~/.claude/plugins/` 配下に配置される慣例があり、追加設定なしで解決可能。

### D3: 参照先が見つからない場合は warning（error ではない）

cross-plugin 参照先の plugin が見つからない場合、validate/check は warning を出力してスキップする。

**理由**: 開発中や CI 環境で全 plugin が揃わないケースを許容し、段階的な導入を可能にする。

### D4: script.can_spawn に script を追加

types.yaml の `script.can_spawn: []` → `script.can_spawn: [script]` に変更。これにより bash script が他の script を呼び出すパターンが正式にサポートされる。

**理由**: 実態として worktree-create.sh 等が他の script を呼ぶパターンが既に存在しており、型ルールを実態に合わせる。

## Risks / Trade-offs

- **Plugin 探索パスのハードコード**: `~/.claude/plugins/` を前提とするため、非標準配置では動作しない。将来的に設定で上書き可能にする余地は残す
- **参照先 deps.yaml の読み込みコスト**: validate 時に複数の deps.yaml を読み込むためパフォーマンスに影響する可能性がある。ただし plugin 数は通常少ない（10 未満）ため実用上は問題ない
- **cross-plugin 参照の型検証の限界**: 参照先 plugin が更新されても参照元の validate は自動的には走らない。手動での再検証が必要
