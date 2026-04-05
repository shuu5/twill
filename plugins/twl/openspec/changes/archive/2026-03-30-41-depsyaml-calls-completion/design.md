## Context

deps.yaml v3.0 では `calls` フィールドがコンポーネント間の依存関係を宣言する。
しかし現在 64 件が Isolated（callers なし・outgoing deps なし）、6件が Unused（callers なし）。
`loom orphans` と SVG グラフのエッジ欠落の根本原因は、この `calls` 宣言漏れにある。

5 カテゴリの未宣言パターンが確認されている:
1. **References (15件)**: どの `calls` にも `- reference:` エントリなし
2. **Agents (27件)**: composite から動的 spawn されるが `- agent:` 未宣言
3. **Scripts (25件)**: コマンドが実行するが `- script:` 未宣言（宣言済みは 3件のみ）
4. **Workflows (5件)**: controller から Skill tool で起動されるが `- workflow:` 未宣言
5. **Sub-commands (15件)**: 親コマンドの `calls` に未宣言

## Goals / Non-Goals

**Goals:**

- deps.yaml の `calls` を実際の呼び出し関係と一致させる
- `loom orphans` の Isolated を 64件 → 10件以下に削減
- SVG 依存グラフに全依存関係エッジを描画
- `loom check` / `loom validate` の PASS を維持

**Non-Goals:**

- loom CLI 側の graph/orphan ロジック修正（shuu5/loom#50）
- deep-validate 警告の修正（#42）
- コンポーネントのファイル内容変更（deps.yaml のみ編集）
- 新規コンポーネントの追加

## Decisions

### D1: 分析アプローチ — ファイル内容からの逆引き

各コンポーネントの .md ファイルを読み、実際に参照しているコンポーネントを特定する。
パターン別の検出ルール:

| カテゴリ | 検出パターン | 例 |
|---------|-------------|-----|
| reference | `ref-xxx` テキスト参照、`refs/xxx.md` パス参照 | agents/*.md 内の `ref-specialist-output-schema` |
| agent | `Agent tool` spawn、`subagent_type` 指定 | composite の `can_spawn: [specialist]` |
| script | `$SCRIPT_DIR/xxx.sh`、`scripts/xxx.sh` パス参照 | commands/*.md 内のスクリプト実行指示 |
| workflow | `Skill tool` で `/twl:workflow-xxx` 起動 | controller SKILL.md 内の遷移指示 |
| sub-command | `Skill tool` で `/twl:xxx` 起動、チェックポイント指示 | command .md 末尾のチェックポイント |

### D2: calls エントリ形式

既存の calls 形式に準拠:
```yaml
calls:
  - reference: ref-specialist-output-schema
  - agent: worker-code-reviewer
  - script: worktree-create
  - workflow: workflow-setup
  - atomic: sub-command-name
```

### D3: agent の calls は参照元（composite）に追加

agents は自身が `calls` を持たない（`can_spawn: []`）。
composite コマンドが `can_spawn: [specialist]` で動的に選択する。
→ composite の `calls` に `- agent:` を追加する。

ただし動的選択（tech-stack-detect 結果に基づく）の場合、全候補を列挙する。

### D4: reference の calls は消費元に追加

reference は受動的コンポーネントなので、参照する側の `calls` に追加:
- 全 27 agents → `ref-specialist-output-schema` を参照 → 各 agent に参照元 calls は追加しない（agent は can_spawn:[] で calls 非対応）
- 代わりに、agent を spawn する composite の calls に reference を含める

**注意**: agent 型は `calls` フィールドを持てない（type: specialist, can_spawn: []）。
reference への calls は、実質的にその reference を消費するコマンド/スキル側に追加する。

### D5: ベースライン記録 → 変更後検証

実装前に現在の状態を記録し、変更後と比較:
- `loom orphans` の Isolated / Unused 件数
- SVG の DOT エッジ数（`loom update-readme` 前後）

## Risks / Trade-offs

- **動的 spawn の完全性**: tech-stack-detect による条件付き spawn は実行時まで確定しない。全候補を列挙することで網羅性を確保するが、実際には使われない agent が calls に含まれる可能性がある
- **loom validate の互換性**: `- agent:` や `- reference:` 形式の calls を loom validate が受け付けるか要事前検証。Issue の前提条件チェックボックスに記載済み
- **大量変更のレビュー負荷**: deps.yaml への変更行数が多くなるが、機械的な追加のため誤り混入リスクは低い
