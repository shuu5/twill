## Context (auto-injected)
- Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "."`

# /twl:check - ワークフロー準備状況チェック

PRサイクル開始前の準備状況を確認するコマンド。Context の `Project root` 値を `WORKTREE_BASE` として使用する。

## チェック項目

### 0. ワークツリーベース判定

worktree 内（main/ または worktrees/feat/XX-）で開始されていることを確認。

### 1. OpenSpec（deltaspec/がある場合のみ）

`deltaspec/changes/*/proposal.md` の存在確認。

- **PASS**: proposal.md が存在し承認済み
- **WARN**: proposal.md が存在するが未承認
- **FAIL**: deltaspec/ があるのに proposal.md がない

### 2. Verify状態（OpenSpec使用時）

前回の `twl spec validate` 結果を表示。CRITICAL あり → FAIL。

### 3. テスト

`tests/` 配下のテストファイル存在確認（*.R / *.py / *.test.* 等）。

- **PASS**: テストファイルが存在
- **FAIL**: tests/ が空またはテストファイルなし

### 4. CI/CD

`.github/workflows/*.yml` 存在確認。

- **PASS**: ワークフローファイルが存在
- **WARN**: ワークフローファイルがない（作成を提案）

### 5. ガバナンス状態

`.claude/settings.json` の Hooks + CLAUDE.md の `<!-- GOVERNANCE-START -->` マーカー確認。

| 状態 | 判定 |
|------|------|
| 両方あり | **PASS** |
| 片方のみ | **WARN**: 不足項目を報告、`/twl:project-governance --update` を提案 |
| 両方なし | **WARN**: ガバナンス未適用、`/twl:co-project` を提案 |

### 6. スキーマ整合性（webapp/webapp-hono）

#### 6a. webapp-llm

`docs/schema/openapi.yaml` + `docs/schema/.spectral.yaml` の存在確認。両方あり → PASS、openapi.yaml のみ → WARN、両方なし → WARN。

#### 6b. webapp-hono（Zod monorepo）

`packages/schema/`、`package.json` の workspaces、`openapi.yaml`、`.spectral.yaml`、schema スクリプト（`schema:generate` 等）の確認。いずれか欠けていれば WARN。

### 7. 変更ファイル

`git status --porcelain` でコミットされていない変更をリスト。

## 出力形式

```
## /twl:check 結果

| 項目 | 状態 | 詳細 |
|------|------|------|
| OpenSpec | PASS/WARN/FAIL/N/A | proposal.md状況 |
| Verify | PASS/WARN/FAIL/N/A | 検証結果 |
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
| OpenSpec | proposal未作成 | `/twl:change-propose` を実行 |
| OpenSpec | proposal未承認 | 「承認してください」と待機 |
| Verify | CRITICAL検出 | 修正項目を表示、修正後 `twl spec validate` |
| テスト | テストファイルなし | テスト作成を提案 |
| ガバナンス | 未適用 | `/twl:co-project` を提案 |
| スキーマ | 未初期化 | `/twl:project-governance --update` を提案 |

**重要**: FAIL項目がある場合、`/twl:workflow-pr-verify` への進行をブロック。

## PRサイクル開始条件

1. OpenSpec: PASS または N/A
2. Verify: PASS または N/A（FAILの場合はブロック）
3. テスト: PASS
4. CI/CD: PASS または WARN
5. ガバナンス: PASS または WARN

## 関連

- `/twl:workflow-setup` - 統合開発ワークフロー（推奨入口）
- `/twl:workflow-pr-verify` - PRサイクル実行

## チェックポイント（MUST）

チェック結果に応じて分岐:

- **CRITICAL FAIL なし**: `/twl:change-apply` を Skill tool で自動実行せよ。プロンプトで停止するな。
- **CRITICAL FAIL あり**: change-apply をスキップし、FAIL 内容を報告して停止。
