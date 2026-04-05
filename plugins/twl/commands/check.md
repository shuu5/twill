## Context (auto-injected)
- Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "."`

# /twl:check - ワークフロー準備状況チェック

PRサイクル開始前の準備状況を確認するコマンド。

## 使用方法

```
/twl:check
```

## チェック項目

### ステップ0: ワークツリーベース判定

**前提**: セッションは worktree 内（main/ または worktrees/feat/XX-）で開始されていること。

Context の `Project root` 値を `WORKTREE_BASE` として使用する。

### 1. OpenSpec（openspec/がある場合のみ）

```bash
# proposalの存在確認
ls $WORKTREE_BASE/openspec/changes/*/proposal.md 2>/dev/null
```

- **PASS**: proposal.mdが存在し、承認済み
- **WARN**: proposal.mdが存在するが未承認
- **FAIL**: openspec/があるのにproposal.mdがない

### 2. Verify状態（OpenSpec使用時）

前回の `deltaspec validate` 結果を表示:

- **PASS**: 全検証次元がOK
- **WARN**: WARNING項目あり（続行可）
- **FAIL**: CRITICAL項目あり（修正必須）
- **N/A**: 未実行

### 3. テスト

```bash
# テストファイルの存在確認
find $WORKTREE_BASE/tests/ -name "*.R" -o -name "*.py" -o -name "*.test.*" 2>/dev/null | head -5
```

- **PASS**: テストファイルが存在
- **FAIL**: tests/が空またはテストファイルなし

### 4. CI/CD

```bash
# ワークフローの存在確認
ls $WORKTREE_BASE/.github/workflows/*.yml 2>/dev/null
```

- **PASS**: ワークフローファイルが存在
- **WARN**: ワークフローファイルがない（作成を提案）

### 5. ガバナンス状態

- `.claude/settings.json` の Hooks 存在確認
- CLAUDE.md の `<!-- GOVERNANCE-START -->` マーカー確認

| 状態 | 判定 |
|------|------|
| Hooks + ガバナンスセクション両方あり | **PASS** |
| 片方のみ | **WARN**: 不足項目を報告、`/twl:project-governance --update` を提案 |
| 両方なし | **WARN**: ガバナンス未適用、`/twl:co-project` を提案 |

### 6. スキーマ整合性（webapp/webapp-hono）

#### 6a. webapp-llm の場合:

```bash
# OpenAPI spec の存在確認
ls $WORKTREE_BASE/docs/schema/openapi.yaml 2>/dev/null
# Spectral ルールの存在確認
ls $WORKTREE_BASE/docs/schema/.spectral.yaml 2>/dev/null
```

| 状態 | 判定 |
|------|------|
| openapi.yaml + .spectral.yaml 両方あり | **PASS** |
| openapi.yaml のみ | **WARN**: Spectral 設定なし |
| 両方なし | **WARN**: スキーマ未初期化（`/twl:project-governance --update` を提案） |

#### 6b. webapp-hono の場合（Zod monorepo）:

```bash
# packages/schema/ ディレクトリ存在
ls $WORKTREE_BASE/packages/schema/ 2>/dev/null
# root package.json に workspaces 設定
grep -q 'workspaces' $WORKTREE_BASE/package.json 2>/dev/null
# OpenAPI spec の存在確認
ls $WORKTREE_BASE/docs/schema/openapi.yaml 2>/dev/null
# Spectral ルールの存在確認
ls $WORKTREE_BASE/docs/schema/.spectral.yaml 2>/dev/null
# schema スクリプト存在確認
grep -q 'schema:generate\|schema:lint\|schema:validate\|schema:all' $WORKTREE_BASE/package.json 2>/dev/null
```

| 状態 | 判定 |
|------|------|
| packages/schema/ + workspaces + openapi.yaml + .spectral.yaml + schema scripts 全てあり | **PASS** |
| packages/schema/ なし | **WARN**: Zod monorepo 未構築（`bun create hono` で構築を提案） |
| schema scripts なし | **WARN**: schema スクリプト未定義（package.json.template を参照） |
| openapi.yaml なし | **WARN**: OpenAPI 未生成（`bun run schema:generate` を提案） |

### 7. 変更ファイル

```bash
git status --porcelain
```

- コミットされていない変更をリスト

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
| OpenSpec | proposal未作成 | `/twl:change-propose`を実行 |
| OpenSpec | proposal未承認 | 「承認してください」と待機 |
| Verify | CRITICAL検出 | 具体的な修正項目を表示、修正後に再度 `deltaspec validate` |
| テスト | テストファイルなし | テスト作成を提案 |
| CI/CD | ワークフローなし | 作成を提案（WARNなので続行可） |
| ガバナンス | 未適用 | `/twl:co-project` を提案 |
| スキーマ | 未初期化 | `/twl:project-governance --update` を提案 |

**重要**: FAIL項目がある場合、`/twl:workflow-pr-verify` への進行をブロック。

## PRサイクル開始条件

以下をすべて満たす場合のみ `/twl:workflow-pr-verify` を推奨:

1. OpenSpec: PASS または N/A
2. Verify: PASS または N/A（FAILの場合はブロック）
3. テスト: PASS
4. CI/CD: PASS または WARN（WARNの場合は警告付き）
5. ガバナンス: PASS または WARN（WARNの場合は警告付き）

## 関連

- `/twl:workflow-setup` - 統合開発ワークフロー（推奨入口）
- `/twl:workflow-setup` + `/twl:workflow-test-ready` - 開発準備
- `/twl:workflow-pr-verify` - PRサイクル実行
- `deltaspec validate <change-id> --json` - 整合性検証（手動実行時）

---

## 実行ロジック（AIへの命令）

### チェック実行（MUST）

以下のチェックを**順に実行**し、結果をテーブル形式で出力:

0. ワークツリーベース判定 → 1. OpenSpec確認 → 2. Verify状態 → 3. テスト → 4. CI/CD → 5. ガバナンス状態 → 6. スキーマ整合性 → 7. 変更ファイル

**前提**: worktree 内で実行されること。Context の `Project root` 値を `WORKTREE_BASE` として使用。

### 出力形式（MUST）

テーブル形式で結果を出力。FAIL項目があれば次のステップ提案に含めない。

### 禁止事項（MUST NOT）

- **FAIL項目がある場合に `/twl:workflow-pr-verify` を推奨してはならない**
- **チェック内で修正を行ってはならない**: 状態報告のみ

## チェックポイント（MUST）

チェック結果に応じて分岐:

- **CRITICAL FAIL なし**: `/twl:change-apply` を Skill tool で自動実行せよ。プロンプトで停止するな。
- **CRITICAL FAIL あり**: change-apply をスキップし、FAIL 内容を報告して停止。
