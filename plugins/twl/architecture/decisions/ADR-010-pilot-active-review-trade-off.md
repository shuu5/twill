# ADR-010: Pilot Active Review Trade-off

## Status

Accepted

## Context

Pseudo-Pilot セッション (Opus 4.6 / 1M context, 21 Issue + Epic 完遂) で 5 つの能動的評価行動が実証された。これらは既存の自動チェック (merge-gate, ac-verify) では捕捉できないインシデントを回避した:

| # | 評価ステップ | 回避インシデント | 失敗時の影響 |
|---|---|---|---|
| 1 | マージ前 `git diff origin/main --stat` で削除確認 | PR #159/#162 で #143 実装 498 行の silent deletion を検知 | 先行 PR の成果が main から消失 |
| 2 | AC 逐一 spot-check + grep + `gh issue view --json comments` | #142 AC「triage 表を Issue にコメント添付」省略を検知 | Issue comment が永遠に空 |
| 3 | rebase + manual conflict resolution | Wave 4 で並列 spawn 中 main が進み Worker 停止 → Pilot が手動 rebase | 並列 spawn が直列化 |
| 4 | AC 矮小化境界の multi-source LLM 判断 | #162 deps.yaml 7 行 diff を multi-source 統合で「正当」と判定 | false REJECT で開発フロー停止 |
| 5 | Worker prompt の事前改善 | 次 Wave の Worker prompt に verify コマンドを明示的に追加 | 同種失敗パターンが繰り返す |

しかし co-autopilot SKILL.md (L54) は Pilot LLM の責務を「計画承認・retrospective・cross-issue 分析」に限定しており、これは context budget 維持を目的とした意図的設計である。Pseudo-Pilot 成功は Opus 4.6 + 1M context 前提であり、Sonnet/Haiku 環境では Pilot context 増加が致命的になる可能性がある。

## Decision

### 選択肢評価

| 選択肢 | 採否 | 理由 |
|---|---|---|
| A. Pilot 責務拡大 (SKILL.md L54 緩和) | **不採用** | context budget 設計意図と直接衝突。Sonnet/Haiku 環境で致命的 |
| **B. Pilot 用 atomic 化** | **採用** | context 増加を atomic 単位で局所化、単独テスト可能、SKILL.md 責務制限維持 |
| C. specialist 化 (merge-gate 経由) | 不採用 | #135 で alignment specialist は実装済。新たに pre-merge specialist を追加するのは scope 重複 |
| D. mergegate.py Python 機械チェック | 不採用 | #166 と重複。本 ADR は Pilot LLM 側に絞る |

**採用案: B 案 (Pilot 用 atomic 化) 単独。** specialist との連携 (autopilot-multi-source-verdict が #135 alignment specialist の出力を引用) は B 案の中の実装詳細として扱う。

### 新規 atomic 群

| atomic | 責務 | 対応する評価ステップ |
|---|---|---|
| autopilot-pilot-precheck | PR diff stat 削除確認 + AC spot-check | 1, 2 |
| autopilot-pilot-rebase | Pilot 介入 rebase (不変条件 F との共存) | 3 |
| autopilot-multi-source-verdict | multi-source 統合 LLM 判断 | 4 |
| PHASE_INSIGHTS 強度勾配 (既存 atomic 拡張) | Worker prompt の事前改善 | 5 |

### opt-out 条件

- 環境変数 `PILOT_ACTIVE_REVIEW_DISABLE=1` で全 atomic を Step 4.5 でスキップ
- **デフォルトは ON** (Pseudo-Pilot 価値を提供)
- 緊急 escape hatch として `1` で完全無効化
- Sonnet/Haiku 環境での段階的無効化は本 ADR スコープ外 (将来の別 Issue)

### 設計原則 P1: Pilot 能動評価の atomic 経由限定

Pilot による PR diff / Issue body 能動評価は autopilot-pilot-* atomic を経由した場合のみ推奨。SKILL.md への直接記述による責務拡大は避ける。

**enforcement**: ADR 参照 + コードレビュー時の人手チェック。`twl --check` の自動検証は本 ADR スコープ外。

不変条件ではなく設計原則として位置づける理由:
- 不変条件は機械的検証 (`twl --check` 等) で enforcement されるべきだが、「atomic 経由か否か」を機械的に判定する mechanism が存在しない
- 設計原則とすることで ADR + コードレビューによる semantic enforcement に委ねる
- 既存不変条件 A-J は機械検証可能 or 運用上明確な制約であり、本原則とは性質が異なる

## Context Budget 増加見積もり

各 atomic 1 回呼び出しあたりの追加 context:

| atomic | 追加トークン (推定) | 理由 |
|---|---|---|
| autopilot-pilot-precheck | 2-5 KB x 最大 3 done Issue = 6-15 KB | PR diff stat + AC + comments |
| autopilot-pilot-rebase | 1-3 KB | git rebase 出力 (abort なら 0) |
| autopilot-multi-source-verdict | 5-10 KB | 5 ソース x 各 1KB 制限 |

Phase あたり合計最悪 28 KB。Opus 1M context の 0.003%、200K context の 0.014%。**許容範囲。**

Phase あたり done Issue 数の想定: 1-3 Issue が標準。4 件以上は precheck で最初の 3 件のみ verify し、残りは sanity_warnings に記録。

### Sonnet/Haiku 環境での扱い

段階的無効化は本 ADR では実装しない。`PILOT_ACTIVE_REVIEW_DISABLE=1` の完全無効化のみサポート。段階的無効化は将来の別 Issue として記録。

## Consequences

### Positive

- Pseudo-Pilot で実証された 5 評価ステップが atomic 化され、再現可能になる
- SKILL.md L54 の責務制限を維持しつつ能動評価を導入できる
- atomic 単位のテスト容易性
- `PILOT_ACTIVE_REVIEW_DISABLE=1` による緊急 escape hatch

### Negative

- Phase あたり最悪 28 KB の context 増加
- 新規 atomic 3 件のメンテナンスコスト
- #166 / #167 マージ後の integration 確認が必要 (defense in depth の検証)

### Neutral

- 既存 autopilot-phase-sanity (#139) との責務分離は明確 (sanity = Issue close 状態のみ / precheck = PR diff stat + AC)
