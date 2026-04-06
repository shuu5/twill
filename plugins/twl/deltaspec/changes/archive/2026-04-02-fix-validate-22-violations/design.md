## Context

deps.yaml v3 スキーマでは calls の各エントリに許可されるキーは `script`, `command`, `skill`, `agent` 等の型キーのみ。#78/#79 で独自に `external`/`path`/`optional`/`note` キーを追加したが、これらは v3 で定義されていない。

loom-engine.py は `plugin:component` 形式の cross-plugin 参照をサポートしており（#97 で loom-plugin-session 新設済み）、`session:session-state` で外部依存を表現可能。

## Goals / Non-Goals

**Goals:**

- deps.yaml の 4 コンポーネントから v3 スキーマ違反キーを除去
- session-state.sh 参照を `session:session-state` cross-plugin 参照に置換
- `loom validate` Violations 0 達成
- `loom check` Missing 0 維持

**Non-Goals:**

- scripts 本体（.sh ファイル）の修正
- loom-engine.py の修正
- session plugin 側の変更

## Decisions

1. **cross-plugin 参照形式の採用**: `external` + `path` キーではなく `script: session:session-state` と記述。loom-engine.py の `parse_cross_plugin_ref()` が `plugin:component` 形式を認識し、`~/.claude/plugins/session/deps.yaml` を参照する。

2. **optional/note 情報の扱い**: deps.yaml v3 にはこれらのキーが存在しないため除去。optional 性やフォールバック動作は scripts 本体のロジックで担保されており、メタデータとしての記述は不要。

3. **script→script 参照**: crash-detect→state-read/state-write、health-check→state-read はローカル参照であり、types.yaml で `script.can_spawn=[script]` が定義済みのため violations は発生しない（#54 で修正済み）。

## Risks / Trade-offs

- **session plugin 未インストール時**: `loom validate` が cross-plugin 参照を解決できずに warning を出す可能性がある。ただし session plugin は dev plugin の前提依存のため許容。
- **影響範囲の小ささ**: deps.yaml メタデータのみの修正であり、実行時の動作には一切影響しない。
