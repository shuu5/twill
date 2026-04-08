# Design: Prompt Compliance Audit ワークフロー統合

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────┐
│  Tier 1: PR Cycle Gate (毎PR、機械的)                        │
│                                                               │
│  git diff --name-only                                        │
│       │                                                       │
│       ▼                                                       │
│  pr-review-manifest.sh                                       │
│       │ .md 変更検出                                          │
│       ▼                                                       │
│  worker-prompt-compliance (specialist)                       │
│       │ twl audit --section 8 --json ベース                   │
│       ▼                                                       │
│  findings: WARNING (stale) / INFO (unreviewed) / OK          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Tier 2: Full Audit Workflow (手動/定期、LLM)                │
│                                                               │
│  co-utility → /twl:workflow-prompt-audit                     │
│       │                                                       │
│       ▼                                                       │
│  Step 1: prompt-audit-scan (atomic)                          │
│       │ twl audit --section 8 --json → stale/unreviewed 特定  │
│       ▼                                                       │
│  Step 2: prompt-audit-review (composite)                     │
│       │ worker-prompt-reviewer を対象ごとに parallel spawn    │
│       ▼                                                       │
│  Step 3: prompt-audit-apply (atomic)                         │
│       │ PASS → refined_by 更新、FAIL → tech-debt Issue 起票   │
│       ▼                                                       │
│  完了                                                         │
└─────────────────────────────────────────────────────────────┘
```

## Tier 1: 詳細設計

### pr-review-manifest.sh への追加

```bash
# prompt ファイル変更検出 → worker-prompt-compliance
has_prompt_md=false
for f in "${FILES[@]}"; do
  case "$f" in
    */commands/*.md|*/agents/*.md|*/skills/*/SKILL.md|*/refs/*.md)
      has_prompt_md=true
      break
      ;;
  esac
done

if $has_prompt_md; then
  SPECIALISTS["worker-prompt-compliance"]=1
fi
```

### worker-prompt-compliance specialist

- **型**: specialist
- **model**: haiku（低コスト）
- **tools**: Bash, Read, Glob
- **実行内容**:
  1. `twl audit --section 8 --json` を実行して JSON 出力を取得
  2. 変更された .md ファイルに対応するコンポーネントの prompt_compliance 項目を抽出
  3. stale → WARNING finding、unreviewed → INFO finding、ok → skip
  4. ref-specialist-output-schema 準拠の JSON で出力

**設計判断**: `twl --audit` の Section 8 出力をそのまま活用。新規ロジックは「変更ファイル → コンポーネント名のマッピング」のみ。

### 変更ファイル → コンポーネント名マッピング

deps.yaml の path フィールドからマッピングを構築:

```python
# twl audit --section 8 --json の出力に component 名が含まれるため
# specialist 側で git diff のファイルリストと照合するだけで十分
```

## Tier 2: 詳細設計

### workflow-prompt-audit (workflow)

| Step | コンポーネント | 型 | 説明 |
|------|--------------|------|------|
| 1 | prompt-audit-scan | atomic | twl audit --section 8 で対象特定 |
| 2 | prompt-audit-review | composite | worker-prompt-reviewer を parallel spawn |
| 3 | prompt-audit-apply | atomic | 結果に基づき refined_by 更新 + Issue 起票 |

### prompt-audit-scan (atomic command)

- `twl audit --section 8 --json` 実行
- stale + unreviewed コンポーネントをリスト化
- 優先度ソート: FAIL(前回) > stale > unreviewed
- 上限 N 件（デフォルト 15）に絞り込み
- 出力: 対象コンポーネントリスト JSON

### prompt-audit-review (composite command)

- prompt-audit-scan の出力を受け取り
- 各対象に対して `worker-prompt-reviewer` を Task spawn（parallel）
- 結果を収集・集約

### prompt-audit-apply (atomic command)

- PASS 判定のコンポーネント: deps.yaml の refined_by を現在のハッシュに更新
  - `twl` CLI に `twl refine --component <name>` サブコマンドを追加（deps.yaml 書き換え）
- WARN/FAIL 判定のコンポーネント: 集約してユーザーに報告
  - ユーザー確認後、tech-debt Issue を起票（1 Issue にまとめる）

### deps.yaml の refined_by 更新方法

`twl refine` CLI サブコマンドを新設:

```bash
# 単一コンポーネント更新
twl refine --component worker-code-reviewer

# バッチ更新（PASS リストから）
twl refine --batch pass-list.json
```

実装: `cli/twl/src/twl/refactor/refine.py`
- deps.yaml を読み込み
- 対象コンポーネントの refined_by を `ref-prompt-guide@<current_hash>` に更新
- refined_at を当日日付に更新
- deps.yaml を書き戻し

## co-utility への統合

co-utility の Step 0 ルーティングにキーワード追加:

```
IF user input ∈ {prompt audit, プロンプト監査, refined_by, prompt compliance}
  → /twl:workflow-prompt-audit を Skill 実行
```

## 新規コンポーネント一覧

| コンポーネント | 型 | パス |
|---|---|---|
| worker-prompt-compliance | specialist | agents/worker-prompt-compliance.md |
| workflow-prompt-audit | workflow | skills/workflow-prompt-audit/SKILL.md |
| prompt-audit-scan | atomic | commands/prompt-audit-scan.md |
| prompt-audit-review | composite | commands/prompt-audit-review.md |
| prompt-audit-apply | atomic | commands/prompt-audit-apply.md |

## 変更対象ファイル一覧

| ファイル | 変更種別 |
|---|---|
| plugins/twl/scripts/pr-review-manifest.sh | MODIFIED |
| plugins/twl/deps.yaml | MODIFIED (新コンポーネント追加) |
| plugins/twl/skills/co-utility/SKILL.md | MODIFIED (ルーティング追加) |
| cli/twl/src/twl/cli.py | MODIFIED (refine サブコマンド追加) |
| cli/twl/src/twl/refactor/refine.py | ADDED |
| plugins/twl/agents/worker-prompt-compliance.md | ADDED |
| plugins/twl/skills/workflow-prompt-audit/SKILL.md | ADDED |
| plugins/twl/commands/prompt-audit-scan.md | ADDED |
| plugins/twl/commands/prompt-audit-review.md | ADDED |
| plugins/twl/commands/prompt-audit-apply.md | ADDED |
