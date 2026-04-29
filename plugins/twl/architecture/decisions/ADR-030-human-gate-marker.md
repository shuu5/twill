# ADR-030: ★HUMAN GATE マーカー規約

## Status

Accepted

## Context

twl の autonomous development は **observer (su-observer)** が核であり、su-observer が controller (co-autopilot/co-issue/co-architect) を spawn + 監督し、ユーザーへの hand-off ポイントを判断する。

既存規約に統一マーカーがなく、observer が「ユーザーへ escalate すべきポイント」を pitfalls-catalog/intervention-catalog から都度参照する必要があり、grep 不可・認知統一が困難であった。

`intervention-catalog.md` の 3 層プロトコル（Layer 0 Auto / Layer 1 Confirm / Layer 2 Escalate）において Layer 1/2 がユーザー hand-off に相当するが、各 SKILL.md や refs ドキュメントにその境界を視覚的に明示する統一マーカーが存在しなかった。

参考: feature-dev plugin が Phase 3 `CRITICAL: DO NOT SKIP` / Phase 5 `DO NOT START WITHOUT USER APPROVAL` の大文字強調マーカーを採用している先行事例がある。

## Decision

ユーザーの判断・承認が**必ず**必要なポイントを示す統一マーカーとして `★HUMAN GATE` を規約化する。

- **記号**: `★HUMAN GATE`（U+2605 BLACK STAR + 半角スペース + 大文字 ASCII）
- **UTF-8 バイト列**: `\xe2\x98\x85HUMAN GATE`（3 bytes + ASCII 10 bytes）

### 主目的

observer の Layer 1 (Confirm) / Layer 2 (Escalate) 介入境界の明示。`intervention-catalog.md` の 3 層プロトコルと整合し、Layer 0 (Auto) との境界を visual に分かるようにする。observer が grep 一発で hand-off ポイントを集約できる。

### 副目的

autopilot/co-issue/co-architect 系の人介入ポイント（AskUserQuestion 直前 / merge-gate REJECT エスカレーション等）の統一マーキング。observer の proxy 対話で介入される境界でもあるため、補助的に統一する。

### 適用条件

ユーザーの判断・承認が**必ず**必要なポイント（Layer 1 Confirm 以上の介入）:
- observer が AskUserQuestion を呼び出す直前
- merge-gate REJECT によりエスカレーションが必要な場合
- Layer 2 Escalate で処理が停止し、ユーザー手動介入を求める場合
- controller の計画承認・設計確認など、自動化できない判断ポイント

### 適用しない条件

以下には付与しない:
- AUTO モードで bypass される自動承認（Layer 0 Auto）
- 進捗報告・ログ出力（ユーザー action 不要）
- 警告の単純表示（INFO/WARN レベルで処理継続可能）

### 段階導入方針

本 ADR（Issue #1084）では試験導入として以下 6 箇所のみ実施:
- observer 主体 3 箇所: `intervention-catalog.md` / `pitfalls-catalog.md` / `su-observer/SKILL.md`
- autopilot 補助 3 箇所: `workflow-pr-merge/SKILL.md` / `co-autopilot/SKILL.md` / `co-architect/SKILL.md`

横展開（全 SKILL.md / agent.md / commands/ 等）は運用知見を積んだ後、別 Issue で判断する。

## Consequences

**ポジティブ**:
- `grep -rn '★HUMAN GATE' plugins/` で hand-off ポイントを一括集約可能
- observer が intervention-catalog を都度参照せずとも視覚的に境界を認識できる
- ドキュメント全体でユーザー介入ポイントの認知が統一される

**リスク / ネガティブ**:
- 規約だけ作って実装で守られない場合ノイズになる → ADR で明文化 + 段階導入で対処
- UTF-8 U+2605 が破損すると grep で検出不能 → CI に grep バイト列チェックを追加することで対処可能（本 Issue は grep 手動確認のみ）

## Alternatives

**A. 既存マーカー（`MUST`, `CRITICAL`, `DO NOT SKIP`）で代替**:
採用しない理由: grep でユーザー hand-off ポイントのみを集約できない。`MUST` は実装制約全般に使用されており、layer 1/2 介入境界と区別不可。

**B. コメントタグ形式（`<!-- HUMAN GATE -->`）**:
採用しない理由: Markdown 表示で不可視となり、読者への視覚的強調効果がない。

**C. 専用 CI lint による機械的検出**:
採用しない理由: 本 Issue のスコープ外。運用知見を積んだ後、別 Issue で検討する。
