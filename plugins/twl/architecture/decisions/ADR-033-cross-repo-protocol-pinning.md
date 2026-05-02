# ADR-033: Cross-Repo Knowledge Transfer via Protocol Pinning

## Status

Accepted

## Context

クロスリポジトリ依存（twill CLI ↔ plugins/twl）において、参照先の変更が Consumer 側に透過的に伝播しない問題がある。
従来の `contracts/` ディレクトリは同一リポジトリ内 Context 間の境界定義に使用されており、クロスリポジトリ依存の追跡には不向きである。

特に以下の問題が顕在化した：
- プラグイン CLI インターフェースの変更が追跡されず、依存側で breaking change を検知できない
- tag/branch 参照では指し示す commit が変わりうる（drift リスク）
- どのリポジトリのどの時点の仕様に依存しているかが不明確

## Decision

### `protocols/` ディレクトリの導入

`architecture/protocols/` ディレクトリを導入し、クロスリポジトリ知識転送プロトコルを定義する。

**contracts/ と protocols/ の棲み分け基準:**

| | contracts/ | protocols/ |
|--|------------|------------|
| 対象スコープ | 同一リポジトリ内 Context 間 | クロスリポジトリ依存 |
| 参照形式 | ファイルパス・型定義 | **40-char commit SHA**（tag/branch 禁止） |
| 変更追跡 | コンパイラ・型チェッカー | `Drift Detection` セクションの運用手順 |
| 主な用途 | API 境界・スキーマ共有 | 外部リポジトリのインターフェース固定点 |

これらは**直交する**概念であり、同一の変更でも両方のファイルを作成する場合がある（例: 型定義は `contracts/`、外部リポジトリとの同期点は `protocols/`）。

### ADR-007 との直交関係

[ADR-007: Cross-repo Project Management](ADR-007-cross-repo-project-management.md) は**プロジェクト管理・Issue 管理**のクロスリポジトリ統合を扱う（GitHub Projects V2 による一元管理、co-issue のクロスリポ Issue 分割）。

ADR-033 は**知識・仕様の転送と固定**を扱う。

- ADR-007: 「どの Issue がどのリポジトリで実装されるか」を管理
- ADR-033: 「どのリポジトリのどのコミット時点の仕様に依存するか」を固定

両者は独立して成立する。ADR-007 がなくても ADR-033 のプロトコルピン機構は機能し、逆も同様。

### Pinned Reference の制約

`protocols/<name>.md` の `Pinned Reference` セクションには必ず **40-char commit SHA** を記録する。

**禁止**: `main`, `HEAD`, `v1.0.0` などの可変参照（tag も時として変更可能であり禁止）。
**理由**: 可変参照は後から指し示す commit が変わる（drift）可能性があり、再現性・一貫性が保証できない。

### Drift Detection 運用例

以下のいずれかの方法でドリフトを定期検出する：

1. **cron（定期バッチ）**: 毎週 `protocols/*.md` の `sha:` フィールドを取得し、Provider リポジトリの最新 main commit と比較する。差分がある場合は Issue を起票する。

2. **GitHub Actions**: PR マージ時に `protocols/*.md` の `sha:` を `^[a-f0-9]{40}$` で検証する CI ステップを追加する。無効な参照（tag/branch）はブロックする。

3. **手動レビュー**: ADR レビューまたは四半期定期レビューの際に、`protocols/*.md` の SHA が依然有効であることを確認する。Provider リポジトリの `git log --oneline <sha>` で参照先が存在することを検証する。

## Alternatives

### A. 既存の contracts/ に拡張

`contracts/*.md` の `Participants` に外部リポジトリを追加する案。
**却下理由**: contracts/ は同一リポジトリ内の型定義と密結合しており、外部 SHA ピンとの混在は責務の曖昧化を招く。

### B. git submodule

外部リポジトリを submodule として固定する案。
**却下理由**: submodule は全ファイルを取り込むため重く、特定のインターフェース定義のみを参照する用途には過剰。

### C. Lock ファイル（package.json 形式）

外部依存を lock ファイルで管理する案。
**却下理由**: このプロジェクトでは「どのインターフェース（セマンティクス）に依存しているか」を人が読める形で文書化する必要があり、lock ファイルのみでは不十分。

## Consequences

### Positive

- クロスリポジトリ依存が明示的に文書化され、drift を検出できる
- `Pinned Reference` の SHA により再現性のある依存が確立される
- `Drift Detection` セクションにより運用手順が標準化される

### Negative

- SHA ピンは手動更新が必要であり、更新漏れのリスクがある（Drift Detection で軽減）
- protocols/ の維持に継続的なコストが発生する

### Mitigations

- `worker-arch-doc-reviewer` が SHA 形式を自動検証し、tag/branch 参照を CRITICAL として検出する
- `architect-completeness-check` は protocols/ の不在を RECOMMENDED（INFO レベル）として扱い、ERROR にはしない
