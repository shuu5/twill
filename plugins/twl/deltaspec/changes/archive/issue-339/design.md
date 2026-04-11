## Context

`change-propose` ステップは `workflow-setup` chain の Step 6 として実行される。chain-runner が `auto_init=true` を state に記録済みの状態でこのステップが呼ばれる。

`change-propose.md` は LLM 向けコマンド仕様であり、Bash スクリプトではない。LLM が手順に従って `twl spec new` と `twl spec instructions` を呼び出し artifact を生成する。

現行の `change-propose.md` の Step 1 は「明確な入力がない場合に質問する」で始まる。`auto_init=true` の場合は Issue 番号から change-id を自動導出できるため、対話は不要。

## Goals / Non-Goals

**Goals:**

- `auto_init=true` かつ Issue 番号あり → 対話なしで change-id `issue-<N>` を自動導出
- `deltaspec/` ディレクトリが未存在の場合でも `twl spec new` が成功するよう `mkdir -p deltaspec/` を先行実行
- Issue body（概要・背景・スコープ・AC）から `proposal.md` を自動生成
- `.deltaspec.yaml` の最小フィールド（name, status: pending, created_at）を生成
- `auto_init=false` の場合は既存フローを完全維持

**Non-Goals:**

- `specs/` や `tasks.md` の自動生成（既存の artifact ループで対応）
- step_init() のロジック変更（#338 のスコープ）
- test-scaffold ステップの変更

## Decisions

### D1: Step 0 として auto_init 分岐を追加

既存の Step 1 の前に「Step 0: auto_init チェック」を挿入する。`auto_init=true` のとき:
1. `state.json` から `auto_init` フィールドを読み取る（chain-runner 経由で設定済み）
2. Issue 番号から `issue-<N>` を change-id として確定
3. `mkdir -p deltaspec/` を先行実行（`twl spec new` が前提とするため）
4. `twl spec new "issue-<N>"` を実行

### D2: `.deltaspec.yaml` は `twl spec new` が生成する scaffold を利用

`twl spec new` コマンドが既に `.deltaspec.yaml` スキャフォールドを生成するため、別途 `.deltaspec.yaml` を手動作成する必要はない。生成後に `status: pending` と `created_at` フィールドの存在を確認する。

### D3: proposal.md の自動生成は既存の artifact ループで実行

Step 0 で `twl spec new` を実行後、既存の Step 3-4（artifact ループ）がそのまま `proposal.md` を生成する。Step 0 は「deltaspec/ の存在前提を解消する」のみに集中する。

## Risks / Trade-offs

| リスク | 緩和策 |
|---|---|
| `twl spec new` が既存 change と衝突する | 実行前に `deltaspec/changes/issue-<N>/` の存在チェックを追加し、既存なら続行確認 |
| Issue 番号が state に存在しない | `auto_init=true` は Issue 番号ありで発火するため、存在チェック不要（step_init() の保証） |
| proposal.md の品質 | ADR-015 に記載の通り、Issue body の構造化度に依存。AC が明文化されていれば十分な品質が得られる |
