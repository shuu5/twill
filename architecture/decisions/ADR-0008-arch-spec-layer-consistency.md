# ADR-0008: Architecture Spec 三層整合性ルール定義

## Status

Accepted

## Context

Monorepo 層・CLI 層・Plugin 層の 3 つの Architecture Spec が独立して制約（Constraints）とNon-Goals を宣言している。各層が独立して進化すると、下位層が上位層の制約を暗黙に破る矛盾が蓄積するリスクがある。

例として、Plugin 層の vision.md が「TWiLL フレームワーク準拠」と宣言しても、Monorepo 層の制約と実際に整合しているかは人間の目視でしか確認できない状態だった。

## Decision

### 1. 正本ファイルパス（Canonical Paths）

各層の Constraints と Non-Goals の正本ファイル:

| 層 | 正本ファイル | 役割 |
|----|------------|------|
| Monorepo 層（上位） | `architecture/vision.md` | モノリポ全体の最上位制約。全層が従う |
| CLI 層（中位） | `cli/twl/architecture/vision.md` | twl CLI 固有の設計制約 |
| Plugin 層（中位） | `plugins/twl/architecture/vision.md` | ワークフロープラグイン固有の設計制約 |

CLI 層と Plugin 層はともに Monorepo 層を上位に持つ兄弟関係（sibling）であり、CLI ↔ Plugin 間には上下関係を設けない。

### 2. 制約継承方向（Constraint Inheritance）

```
Monorepo 層（architecture/vision.md）
    ├── 制約継承 ──→ CLI 層（cli/twl/architecture/vision.md）
    └── 制約継承 ──→ Plugin 層（plugins/twl/architecture/vision.md）
```

上位層の Constraints は下位層に対して **上限制約**として機能する。下位層は Constraints を絞り込む（より具体化する）ことは許可されるが、緩和・否定してはならない。

### 3. 整合性ルール

#### Constraints の整合性ルール

| 許容 | 禁止 |
|------|------|
| 上位層 Constraints のより具体的な言明（例: 上位「deps.yaml が SSOT」→ 下位「deps.yaml v3.0 が SSOT」） | 上位層 Constraints の否定または緩和 |
| 上位層が未定義の新規 Constraints の追加 | 上位層 Constraints に直接矛盾する Constraints の宣言 |
| 上位層 Constraints の参照（「上位層の○○制約に準拠」等の明示） | 暗黙の矛盾（例: 上位「依存方向の一方向性」を違反する依存方向を前提とした制約の宣言） |

#### Non-Goals の整合性ルール

| 許容 | 禁止 |
|------|------|
| 下位層固有の Non-Goals の追加（拡張） | 上位層 Non-Goals の再掲（重複） |
| 上位層 Non-Goals より具体的なスコープへの絞り込み | 上位層の Non-Goals を全包含する Non-Goals の宣言 |
| 上位層 Non-Goals に言及せずに独自の境界を定義 | 上位層の Constraints に含まれる項目を Non-Goals として宣言 |

### 4. 矛盾の定義

以下のいずれかに該当する場合を「矛盾」とみなす:

1. **直接否定**: 下位層 Constraints が上位層 Constraints を明示的に否定・解除する文言を含む
2. **暗黙の逸脱**: 下位層 Constraints が上位層の制約が想定する構造と相容れない前提に依存している（例: 上位「依存方向の一方向性（plugins → cli のみ）」に対して下位「cli → plugin を前提とした○○」）
3. **Non-Goals の上位包含**: 下位層 Non-Goals が上位層 Non-Goals の全項目を包含する（上位層 Non-Goals が下位層 Non-Goals の真部分集合になる状態）
4. **Constraints の Non-Goals への格下げ**: 上位層 Constraints に定義された項目が下位層 Non-Goals に掲載される

### 5. 整合性検証の手順（人間によるレビュー）

Architecture Spec を変更する際は以下を確認する:

1. 変更する層を特定し、上位層の正本ファイルを Read する
2. 変更後の Constraints が上位層の各 Constraints と矛盾しないか照合する（整合性ルール § 3 を適用）
3. 変更後の Non-Goals が上位層の Non-Goals と重複・矛盾しないか照合する
4. 矛盾が検出された場合は、上位層 Spec の変更（scope 拡張）か下位層記述の修正かを判断する

> 自動検証（`twl audit` 統合）は別 Issue で対応予定。本 ADR は人間によるレビュー基準の定義に留める。

## Consequences

### Positive

- 三層間の整合性判断基準が明文化され、Architecture Spec のレビューでどこを確認すべきかが明確になる
- 下位層が上位層の制約に「暗黙に矛盾」するケースを人間がレビューで検出できる
- 将来の `twl audit` 実装時の要件仕様として機能する

### Negative

- 現時点では機械的な検証がなく、レビュー者がこの ADR を参照しなければ整合性が保証されない
- 「矛盾」の定義（特に暗黙の逸脱）は判断が必要なケースがあり、機械的に判定できない場合がある

### Neutral

- CLI 層と Plugin 層の間には上下関係を設けない（両者はともに Monorepo 層から制約を継承する兄弟関係）
- 本 ADR は Architecture Spec の内容を書き換えるものではなく、整合性ルールのみを定義する
