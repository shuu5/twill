# Contract: Architecture Spec <-> co-issue / co-architect (DCI)

Architecture Spec が co-issue と co-architect に DCI（Dynamic Context Injection）で注入されるインターフェース定義。

## 注入元ファイル

| ファイル | 注入先 | 用途 |
|---------|--------|------|
| `architecture/vision.md` | co-issue Phase 1 | 設計意図・制約の理解 |
| `architecture/domain/context-map.md` | co-issue Phase 1 | Context 間関係の理解 |
| `architecture/domain/glossary.md` | co-issue Phase 1, Step 1.5 | 用語の一貫性確保 |
| `architecture/domain/contexts/*.md` | co-architect explore | 各 Context の詳細理解 |

## co-issue への注入ルール

### Phase 1: architecture context 注入

```
IF [ -d "$(git rev-parse --show-toplevel)/architecture" ]
THEN
  Read: architecture/vision.md
  Read: architecture/domain/context-map.md
  Read: architecture/domain/glossary.md
  → ARCH_CONTEXT として explore に注入
```

- ファイル不存在時: スキップ（エラーにしない）
- ARCH_CONTEXT 空時: 従来通り explore を実行

### Step 1.5: glossary 照合

- `glossary.md` の `### MUST 用語` セクションから用語名を抽出
- explore-summary.md の主要用語と完全一致を照合
- 不一致: **INFO レベル**で通知（非ブロッキング）

## co-architect への注入ルール

- `architecture/` 全体を Read して現状把握（Step 1）
- `architecture/domain/contexts/*.md` を explore で参照（Step 2）
- `architect-completeness-check` で必須ファイルの存在を検証（Step 3）

## 更新トリガー

以下の変更が発生した場合、architecture spec の更新を検討する:

| トリガー | 影響を受ける spec ファイル |
|---------|-------------------------|
| 新しい概念・用語の導入 | glossary.md |
| Context 境界の変更 | context-map.md, contexts/*.md |
| 新しい設計判断 | decisions/ADR-NNN.md |
| Controller/Workflow 構成の変更 | model.md, contexts/*.md |
| 新しい Contract の追加 | contracts/*.md |
| Project Board / クロスリポ関連の変更 | contexts/project-mgmt.md |

## co-issue からのフィードバック（Step 3.5: Architecture Drift Detection）

co-issue は Issue 精緻化後に architecture drift を検出し、ユーザーに co-architect の実行を **INFO レベル**で提案する。co-issue 自体が architecture を更新することはない（Non-implementation controller）。

### 検出シグナル（3層）

| レベル | シグナル | 検出方法 |
|--------|---------|---------|
| 明示的 | `<!-- arch-ref-start -->` タグ | Issue body のパース |
| 構造的 | 不変条件・Entity Schema・Workflow 変更言及 | glossary.md の MUST 用語 + architecture/ ファイル名との照合 |
| ヒューリスティック | スコープが 3 Context 以上に跨る | ctx/* ラベルの数 + 影響範囲の Context 分析 |

### 出力

```
INFO: 以下の Issue が architecture spec に影響する可能性があります:
  #N: explicit reference (architecture/domain/contexts/autopilot.md)
  #M: invariant change (不変条件B)
architecture spec の事前更新を検討してください: /twl:co-architect
```

**非ブロッキング**: glossary 照合（Step 1.5）と同レベル。co-issue フローを止めない。

## 品質保証

- architecture spec の陳腐化は co-issue の Issue 品質を直接低下させる
- glossary.md の MUST 用語が不完全だと、Step 1.5 の照合が不十分になる
- vision.md の Constraints が現実と乖離すると、explore が誤った方向に誘導される
- **Step 3.5 drift detection が機能することで、陳腐化の早期検知が可能になる**
