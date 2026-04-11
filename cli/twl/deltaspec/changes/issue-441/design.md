## Context

su-observer（ADR-014）は「全 controller を session:spawn して観察する常駐 observer パターン」として設計されているが、architecture spec 4 ファイル（supervision.md / observation.md / context-map.md / model.md）がこのパターンを不正確または不完全に記述している。

対象ファイルはすべて `plugins/twl/architecture/domain/` 配下の純粋なドキュメントであり、実装コードへの影響はない。

## Goals / Non-Goals

**Goals:**

- supervision.md の常駐ループ mermaid 図に全 controller への spawn パスを追加する
- supervision.md L226 の「委譲」を「session:spawn 経由」と明記する
- supervision.md に co-autopilot のみ能動 observe、他は spawn 後即指示待ちであることを追記する
- observation.md の Observe ループ mermaid の起点を「su-observer が session:spawn で co-self-improve を起動」に修正する
- context-map.md の Supervision → Live Observation エッジラベルを「session:spawn → observe」に変更し、テーブルも更新する
- model.md の Supervisor クラスの `type: observer` を `type: supervisor` に修正する

**Non-Goals:**

- su-observer SKILL.md の変更（別 Issue）
- co-self-improve SKILL.md の変更（別 Issue）
- deps.yaml の変更（別 Issue）
- su-observer-skill-design.md の変更（正典のため変更しない）
- ADR-014 の変更

## Decisions

### D1: supervision.md mermaid 図に spawn パスを追加

**現状**: 常駐ループ図には `co-autopilot spawn` / `co-issue spawn` / `co-architect spawn` のみ記載。

**変更**: co-self-improve / co-utility / co-project への spawn パスも追加する。ノード名は既存の命名規則（`spawn`サフィックス）に合わせる。

**理由**: Issue スコープに明記されており、全 controller を spawn できることが su-observer の核心機能。

### D2: L226 委譲文の修正

**現状**: 「su-observer はテストシナリオ実行を co-self-improve に委譲する（ADR-011 継続）。」

**変更**: 「su-observer は session:spawn 経由で co-self-improve を起動し、テストシナリオ実行を委譲する（ADR-011 継続）。」

**理由**: spawn メカニズムが不明確だったため。

### D3: co-autopilot の能動 observe 記述を追加

**現状**: 全 controller が「spawn + observe」と書かれているが、co-autopilot のみ能動 observe で他は spawn 後即指示待ちという差異が未記載。

**変更**: 「co-self-improve との境界」セクションまたは「Supervisor 常駐ループ」に差異を追記する。

### D4: observation.md の起点修正

**現状**: `A[co-self-improve 起動]` がフローの最初のノード（su-observer との関係が未記載）。

**変更**: `A[su-observer: session:spawn で co-self-improve を起動]` に変更し、spawn 関係を明示。

### D5: context-map.md の SOBS→OBS エッジ変更

**現状**: `SOBS -->|"Customer-Supplier<br/>co-self-improve テスト委譲"| OBS`

**変更**: `SOBS -->|"Customer-Supplier<br/>session:spawn → observe"| OBS`

関係テーブルも「co-self-improve へのテスト委譲（Upstream、ADR-014）」 → 「session:spawn で co-self-improve を起動し observe（ADR-014）」に更新。

### D6: model.md の type 修正

**現状**: `type: observer`（タイポ）

**変更**: `type: supervisor`（正しい型定義）

## Risks / Trade-offs

- **リスク**: mermaid 図の変更は既存ドキュメント参照に影響しない（IDではなくビジュアルなので）。変更後は必ず mermaid 記法が正しいことを確認する。
- **トレードオフ**: 最小限の変更（文書修正のみ）のため影響範囲は極小。実装コードは変更しない。
