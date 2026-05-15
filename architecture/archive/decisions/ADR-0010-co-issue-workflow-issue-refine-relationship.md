# ADR-0010: co-issue と workflow-issue-refine の設計原則

## ステータス

Accepted

## コンテキスト

`co-issue`（controller）と `workflow-issue-refine`（workflow）はどちらも Issue refine（精緻化）に関与するが、`plugins/twl/deps.yaml` 上での設計意図が明文化されていなかった。

具体的な曖昧点:

- どちらが Issue refine の正規実装か（責務の所在）
- `co-issue` は thin wrapper か、それとも独立した refine ロジックを持つか
- `refined` ラベルの付与権限はどちらが保持するか
- Layer D `refined-label-gate` が両 skill を許可している設計根拠

## 決定

### 責務境界

| コンポーネント | 役割 | refine ロジック保持 |
|---|---|---|
| `co-issue` | thin orchestrator | **持たない** |
| `workflow-issue-refine` | refine 実装 workflow | **保持する** |

### co-issue は thin orchestrator

`co-issue` は Issue 作成ワークフローの orchestrator であり、refine フェーズ（Issue 精緻化）は `workflow-issue-refine` に完全委譲する。`co-issue` 自身は refine ロジックを実装しない。

deps.yaml の `delegates_to` フィールドがこの委譲関係を宣言する:

```yaml
co-issue:
  delegates_to:
    - workflow: workflow-issue-refine
      role: refine
```

### workflow-issue-refine は独立 workflow

`workflow-issue-refine` は独立した workflow として設計されており、以下の両方から呼び出し可能:

1. `co-issue`（controller）からの委譲
2. ユーザーの直接起動（`user-invocable: true`）

deps.yaml の `delegated_by` フィールドが被委譲関係を宣言する:

```yaml
workflow-issue-refine:
  delegated_by:
    - controller: co-issue
      role: refine
```

### refined-label 付与権限

`refined` ラベルの付与権限（Layer D `refined-label-gate`）は `workflow-issue-refine` が保持する。`co-issue` はラベルを直接付与しない。Layer D gate が両 skill を許可しているのは、`workflow-issue-refine` が user から直接起動される経路を考慮しているためである。

### deps.yaml の delegates_to / delegated_by フィールド

`delegates_to` と `delegated_by` は deps.yaml の意味的関係を表す注釈フィールドである。`calls` が機能的な呼び出し関係（SVG グラフのエッジ）を表すのに対し、これらは設計意図（委譲パターン）を表す。

`twl --validate` および `twl check` はこれらのフィールドを検証しない（`calls` と重複しない）。将来のツール拡張でグラフ可視化に活用できる。

## 結果

- deps.yaml に `delegates_to` / `delegated_by` エッジが追加され、co-issue と workflow-issue-refine の関係が明文化された
- `twl --validate` は引き続き PASS する
- 将来の Layer D hook 更新時に deps.yaml を参照して設計意図を確認できる
- `workflow-issue-refine` への変更時は co-issue への影響（thin wrapper の委譲先変更）を考慮する

## 関連

- `plugins/twl/deps.yaml` co-issue, workflow-issue-refine
- Epic #806 Phase B Wave 3 co-issue refine Layer D 対応
- Issue #834（本 ADR を起票したタスク）
- Layer D `refined-label-gate` hook
