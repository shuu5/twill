## Context (auto-injected)
- Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "."`

# /twl:check - ワークフロー準備状況チェック

PRサイクル開始前の準備状況を確認するコマンド。Context の `Project root` 値を `WORKTREE_BASE` として使用する。

## チェック項目

### 0. ワークツリーベース判定

worktree 内（main/ または worktrees/feat/XX-）で開始されていることを確認。

### 1. テスト

`tests/` 配下のテストファイル存在確認（*.R / *.py / *.test.* 等）。

- **PASS**: テストファイルが存在
- **FAIL**: tests/ が空またはテストファイルなし

### 2. CI/CD

`.github/workflows/*.yml` 存在確認。

- **PASS**: ワークフローファイルが存在
- **WARN**: ワークフローファイルがない（作成を提案）

### 3. ガバナンス状態

`.claude/settings.json` の Hooks + CLAUDE.md の `<!-- GOVERNANCE-START -->` マーカー確認。

| 状態 | 判定 |
|------|------|
| 両方あり | **PASS** |
| 片方のみ | **WARN**: 不足項目を報告、`/twl:project-governance --update` を提案 |
| 両方なし | **WARN**: ガバナンス未適用、`/twl:co-project` を提案 |

### 4. スキーマ整合性（webapp/webapp-hono）

#### 4a. webapp-llm

`docs/schema/openapi.yaml` + `docs/schema/.spectral.yaml` の存在確認。両方あり → PASS、openapi.yaml のみ → WARN、両方なし → WARN。

#### 4b. webapp-hono（Zod monorepo）

`packages/schema/`、`package.json` の workspaces、`openapi.yaml`、`.spectral.yaml`、schema スクリプト（`schema:generate` 等）の確認。いずれか欠けていれば WARN。

### 5. 変更ファイル

`git status --porcelain` でコミットされていない変更をリスト。

## 出力形式

```
## /twl:check 結果

| 項目 | 状態 | 詳細 |
|------|------|------|
| テスト | PASS/FAIL | テストファイル数 |
| CI/CD | PASS/WARN | ワークフロー数 |
| ガバナンス | PASS/WARN | Hooks + CLAUDE.md状況 |
| スキーマ | PASS/WARN/N/A | OpenAPI + Spectral状況 |
| 変更 | INFO | 変更ファイル数 |

### 次のステップ
(状態に応じたアクション提案)
```

## FAIL時の対応

| 項目 | FAIL理由 | 対応 |
|------|---------|------|
| テスト | テストファイルなし | テスト作成を提案 |
| ガバナンス | 未適用 | `/twl:co-project` を提案 |
| スキーマ | 未初期化 | `/twl:project-governance --update` を提案 |

**重要**: FAIL項目がある場合、`/twl:workflow-pr-verify` への進行をブロック。

## PRサイクル開始条件

1. テスト: PASS
2. CI/CD: PASS または WARN
3. ガバナンス: PASS または WARN

## 関連

- `/twl:workflow-setup` - 統合開発ワークフロー（推奨入口）
- `/twl:workflow-pr-verify` - PRサイクル実行
