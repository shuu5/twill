## Context

loom-plugin-dev の `architecture/` ディレクトリは静的文書として存在するが、各ワークフロー（co-issue, merge-gate, specialist）はこれを参照していない。ユーザーフィードバック「LLM に『注意して』は無効、機械的制御で再発防止」に基づき、architecture context を機械的に inject する仕組みを構築する。

PR-Cycle Bounded Context の **動的レビュアー構築ルール**（`architecture/domain/contexts/pr-cycle.md`）に従い、worker-architecture を条件付き自動追加する。

## Goals / Non-Goals

**Goals:**
- co-issue Phase 1 の explore 呼び出しに architecture context を inject する
- issue-structure が arch-ref タグを自動生成し、workflow-setup の arch-ref ステップで context が引き継がれるようにする
- merge-gate が architecture/ 存在時に worker-architecture を動的追加する
- worker-architecture が PR diff モードで ADR・invariant・contract を検証する
- specialist-output-schema に `architecture-violation` カテゴリを追加する

**Non-Goals:**
- `architecture/` ファイル自体の内容更新
- architecture drift 検出メカニズムの構築
- 新しい specialist の作成（worker-architecture の拡張のみ）

## Decisions

### D1: architecture/ 存在チェックはシェル条件分岐で実施

`[ -d "$(git rev-parse --show-toplevel)/architecture" ]` でチェック。存在しないプロジェクトへの影響を排除。マークダウン指示として記述し、LLM が実行時に判定する。

**代替案**: deps.yaml フラグ → 設定の追加が必要で実装コストが高い。却下。

### D2: arch-ref タグは issue-structure が生成する（workflow-setup は読むだけ）

`<!-- arch-ref-start -->...<path>...<!-- arch-ref-end -->` タグを issue-structure が生成することで、arch-ref ステップのロジック（既存実装）を活性化する。arch-ref ステップの変更は最小限。

### D3: worker-architecture の pr_diff モードは既存 plugin_path モードと並立

入力を `pr_diff` か `plugin_path` で分岐する。merge-gate からは `pr_diff` モードで呼び出す。既存の plugin 構造検証フローは変更しない。

### D4: co-issue の architecture context 注入は Read ベース（MCP 不使用）

`vision.md`, `domain/context-map.md`, `domain/glossary.md` を直接 Read して LLM コンテキストに注入。存在しない場合はスキップ（警告なし）。

## Risks / Trade-offs

- **コンテキスト長増加**: architecture context の inject により co-issue の LLM コンテキストが増加する。vision.md + context-map.md + glossary.md の合計が大きい場合は要注意。軽減策: 各ファイルの最初の 100 行のみ読む制限を設ける（実装判断）
- **arch-ref タグの誤生成**: issue-structure が複数の ctx/* ラベルをマッチした場合、主要 context の選定に LLM 判断が入る。明示的ルール（単一マッチ時のみパスを出力）で軽減
- **worker-architecture の誤検出**: ADR・invariant の解釈誤りで false positive が発生する可能性。CRITICAL confidence threshold（>=80）で機械的フィルタリングして影響を限定
