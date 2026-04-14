## Context

`co-architect` は `vision.md` で "Non-implementation" カテゴリに属するが、`architecture/` ディレクトリへの直接 Write とコミットを行うため、「コード変更・PR 作成を伴わない」という Non-implementation の定義と矛盾している。
この矛盾を ADR-019 として記録し、新カテゴリ「Spec Implementation」を公式化することで、vision.md と実態を整合させる。
変更スコープは docs-only（ADR + vision.md + glossary.md）であり、実装ロジック（SKILL.md, deps.yaml）は変更しない。

## Goals / Non-Goals

**Goals:**

- ADR-019 (`plugins/twl/architecture/decisions/ADR-019-spec-implementation-category.md`) を作成し、Context/Decision/Consequences/Alternatives を記録する
- `vision.md` の「Controller 操作カテゴリ」テーブルに「Spec Implementation」行を追加し、co-architect を Non-implementation から移動する
- `vision.md` の「Non-implementation controller は co-autopilot を spawn しない」説明文を更新する
- `glossary.md` の MUST 用語テーブルに「Spec Implementation」を追加する

**Non-Goals:**

- co-architect の SKILL.md を変更する（#4 で対応）
- deps.yaml の controller カテゴリを変更する（#4, #5 で対応）
- vision.md 以外の architecture spec ファイルを変更する（Constraints/Non-Goals セクションは触れない）

## Decisions

### D-1: ADR フォーマット準拠

既存 ADR（ADR-018 等）のフォーマットに倣い、`# ADR-019: <title>`・**Status**・**Date**・**Issue**・**Supersedes**・**Related** ヘッダーを使用する。
Status は `Accepted`、Date は `2026-04-13`、Issue は `#557`。

### D-2: vision.md のテーブル更新（方法 A — 行追加）

"Implementation" と "Non-implementation" の間に "Spec Implementation" 行を挿入する。
Non-implementation の「該当 Controller」から `co-architect` を削除する。

変更後テーブル:

| カテゴリ | 定義 | 該当 Controller |
|---|---|---|
| Implementation | コード変更・PR 作成を伴う操作 | co-autopilot のみ |
| Spec Implementation | Architecture spec 変更・PR 作成 | co-architect |
| Non-implementation | Issue 作成・設計・プロジェクト管理 | co-issue, co-project |
| Utility | スタンドアロンユーティリティ操作 | co-utility |
| Observation | ライブセッション観察・問題検出・Issue 起票 | co-self-improve |
| Supervisor | controller の動作を監視・介入するメタレイヤー | su-observer |

テーブル直下の説明文: 「Non-implementation controller は co-autopilot を spawn しない。」→「Non-implementation controller と Spec Implementation controller は co-autopilot を spawn しない。」に更新。
「co-architect が「設計 + 実装」を要求された場合〜」の文は vision.md に残す。

### D-3: glossary.md MUST 用語追加

MUST 用語テーブルの末尾に追加:

| Spec Implementation | Architecture spec の変更・PR 作成を担う controller カテゴリ。co-architect のみ該当。Implementation（コード変更）とは区別される（ADR-019） | 全体 |

### D-4: Alternatives は ADR-019 に記録

Issue body で言及された 2 つの Alternatives（「既存 Implementation に統合」「ADR 例外として対応」）を ADR-019 の Alternatives セクションに記録する。

## Risks / Trade-offs

- vision.md の Constraints セクション（「Controller は6つ」）と CLAUDE.md の記述は今回変更しない。これらは controller の本数を示しており、カテゴリ変更と直交する
- glossary.md の照合ポリシーは完全一致のみのため「Spec Implementation」を正式名称として登録することで、co-issue Step 1.5 での用語照合が機能するようになる
