---
name: twl:ref-dci
description: |
  DCI（Dynamic Context Injection）共通パターン。
  サブコマンドの frontmatter 直後に自動注入される変数定義とフォールバック設計。
type: reference
disable-model-invocation: true
---

# DCI (Dynamic Context Injection) パターン

## 概要

サブコマンド（commands/*.md）の frontmatter 直後に `## Context (auto-injected)` セクションを配置し、シェルの `!` バッククォート構文で動的情報を自動注入するパターン。Skill tool 経由の読み込み時に Claude Code が前処理として実行する。

## 標準変数

| 変数 | Context ラベル | シェルコマンド | フォールバック | 用途 |
|------|--------------|--------------|--------------|------|
| BRANCH | Branch | [BANG]`git branch --show-current` | `""` | ブランチ名 |
| ISSUE_NUM | Issue | [BANG]`source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null \|\| true; resolve_issue_num 2>/dev/null \|\| echo ""` | `""` | state file（AUTOPILOT_DIR）または branch から解決した Issue 番号 |
| REPO_MODE | Repo mode | [BANG]`[ -d ".git" ] && echo "standard" \|\| echo "worktree"` | `"standard"` | リポジトリ形式 |
| PR_NUMBER | PR | [BANG]`gh pr view --json number -q '.number' 2>/dev/null \|\| echo "none"` | `"none"` | PR 番号 |
| PROJECT_ROOT | Project root | [BANG]`git rev-parse --show-toplevel 2>/dev/null \|\| echo "."` | `"."` | プロジェクトルートパス |

**注**: `[BANG]` は実際の適用時には `!` に置換する。本ドキュメント内ではコードフェンス内誤実行バグ（claude-code Issue #12781）回避のためプレースホルダーを使用。

## フォールバック設計

全ての DCI 変数は以下のパターンでエラー耐性を確保する:

```
[BANG]`command 2>/dev/null || echo "fallback"`
```

- `2>/dev/null`: stderr を抑制（gh 認証切れ等のエラーメッセージを非表示化）
- `|| echo "fallback"`: コマンド失敗時にデフォルト値を返す
- サブコマンドの実行は DCI 失敗で停止してはならない

## 適用方法

### Context セクションの配置

frontmatter 直後、本文の前に配置する:

```markdown
---
name: twl:example-command
type: atomic
allowed-tools: Bash, Read, Write
---

## Context (auto-injected)
- Branch: [BANG]`git branch --show-current`
- Issue: [BANG]`source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo ""`

# コマンド本文

（以降、Context の値を直接参照）
```

### 必要な変数のみ注入

各コマンドは必要な変数のみを Context セクションに含める。全6変数を一律注入しない。

| コマンド | 注入変数 |
|---------|---------|
| ac-extract | BRANCH, ISSUE_NUM |
| auto-merge | BRANCH, ISSUE_NUM, PR_NUMBER, REPO_MODE |
| all-pass-check | BRANCH, ISSUE_NUM, PR_NUMBER |
| scope-judge | PR_NUMBER |
| check | PROJECT_ROOT |
| init | BRANCH, REPO_MODE |
| pr-cycle-analysis | PR_NUMBER |
| controller-autopilot | REPO_MODE |
| env:rebuild | BRANCH |

### 既存 Bash 取得コードの置換

DCI 注入後、コマンド本文内の対応する Bash 取得コードを削除し、Context セクションの値を参照する記述に置き換える。DCI で注入できない動的値（SNAPSHOT_DIR 等）の Bash 取得は残す。

## コードフェンス内回避策

claude-code Issue #12781 により、コードフェンス内の `!` バッククォート構文も誤って実行される。

- **reference ドキュメント内の例示**: `[BANG]` プレースホルダーを使用
- **実際の Context セクション**: `!` バッククォートをそのまま記述（実行される前提）
- **コードフェンス内でコマンド例を示す場合**: `[BANG]` を使用

バグ修正後は `grep -r '\[BANG\]' claude/plugins/twl/` で一括検索・置換可能。
