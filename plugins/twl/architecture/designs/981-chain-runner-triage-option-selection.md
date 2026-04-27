# Design Note: Issue #981 — chain-runner.sh token_bloat triage

## 問題

`chain-runner.sh` (1398行 / 14698 tok) を 5 atomics が同一 path で参照していたため、
`twl audit` の token_bloat セクションで 5 件の critical が発生していた。

| atomic | path (変更前) |
|--------|--------------|
| arch-ref | scripts/chain-runner.sh |
| chain-status | scripts/chain-runner.sh |
| dispatch-info | scripts/chain-runner.sh |
| llm-complete | scripts/chain-runner.sh |
| llm-delegate | scripts/chain-runner.sh |

## Options 評価

| # | Option | 概要 | 採用可否 |
|---|--------|------|---------|
| A | **script 分割（thin wrapper）** | 各 atomic 用に薄い entry-point スクリプトを作成し、chain-runner.sh に委譲 | **採用** |
| B | 1 atomic 集約 | 5 atomics → 1 atomic に統合 | 非採用（粒度変更で ADR-022 影響が大きい） |
| C | shared_host フラグ | deps.yaml schema 拡張 + audit.py 変更 | 非採用（audit 意味論変更が副作用を伴う） |
| D | audit ロジック修正 | audit.py の dedup ロジック追加 | 非採用（全 plugin に影響する ADR 級変更） |
| E | path null 化 | atomic の path を削除 | 非採用（traceability 喪失） |
| F | 無視 | 現状維持 | 非採用（audit 信頼性低下） |

## 採用 Option: A（thin wrapper script 分割）

### 選定根拠

1. **最小変更**: chain-runner.sh 本体は無変更。各 atomic に独立した entry-point を設けるだけ
2. **ADR-022 準拠**: `CHAIN_STEPS` 不変、step 名不変、deps.yaml chains 構造不変
3. **traceability 維持**: 各 atomic が固有 path を持ち、物理 → 論理のリンクが明確
4. **#985 互換**: workflow skill の orchestrate/step 責務分離に影響なし
5. **audit 解消**: 各 wrapper は ~3 行（≈ 20 tok）→ 2500 tok 閾値を大幅に下回る

### 実装

```
scripts/chain/
├── arch-ref.sh        → exec chain-runner.sh arch-ref "$@"
├── chain-status.sh    → exec chain-runner.sh chain-status "$@"
├── dispatch-info.sh   → exec chain-runner.sh dispatch-info "$@"
├── llm-complete.sh    → exec chain-runner.sh llm-complete "$@"
└── llm-delegate.sh    → exec chain-runner.sh llm-delegate "$@"
```

deps.yaml の 5 atomics の `path:` を `scripts/chain-runner.sh` から各 wrapper に変更。

### ADR-022 整合性確認

- `chain.py CHAIN_STEPS` ⊆ `deps.yaml.chains` flatten: **維持** (step 名は不変)
- deps.yaml SSoT: `check_deps_integrity()` エラーなし
- chain-runner.sh dispatch テーブル: 変更なし（wrapper は exec で委譲するだけ）

### #985 整合性確認

- workflow skill (SKILL.md) は `bash "$CR" <step>` 形式で chain-runner.sh を呼ぶ
- chain-runner.sh は引き続き step dispatch の host として機能
- wrapper scripts は audit 用 entry-point であり、実行時には chain-runner.sh が処理する
- #985 の workflow batch split は SKILL.md の orchestrate 層を扱うため、本変更と直交

## AC-6: deps.yaml 全体の共有 path パターン調査

調査日: 2026-04-27

```bash
# 調査方法: 全 atomic の path を集計し、2件以上の共有を検出
```

**結果: 他の共有パターンなし**

- 本変更前: `scripts/chain-runner.sh` を参照する atomic = 5件
- 本変更後: 全 93 path がユニーク（共有パターン = 0件）
- 調査対象: deps.yaml v3.0 の全 atomic コンポーネント（約 270件中 path 記載 93件）
