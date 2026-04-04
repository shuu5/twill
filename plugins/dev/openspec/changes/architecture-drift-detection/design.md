## Context

architecture/ spec は 2026-03-27 以降更新されていないが、実装は 22 件以上の Issue で進化している。drift 検出を 3 つのコンポーネントに分散して挿入することで、既存フローを中断せず段階的に検出できる。

前提 Issue: #159（worker-architecture PR diff モード追加）が完了済みであること。

## Goals / Non-Goals

**Goals:**
- co-issue Phase 1 完了後に glossary 未定義用語を INFO 通知する
- merge-gate で architecture drift を WARNING として報告する（ブロックしない）
- autopilot Phase 完了時に architecture 更新候補を提示する（自動 Issue 化しない）
- architecture/ 非存在プロジェクトで影響ゼロを保証する

**Non-Goals:**
- architecture/ ファイルの自動書き換え
- CRITICAL/blocking エラーとしての drift 検出
- loom リポ側の変更
- 前提 Issue #159 の実装（worker-architecture PR diff モード追加）

## Decisions

### D-1: 存在チェックを各コンポーネント内に配置

各コンポーネント（co-issue, worker-architecture, autopilot-retrospective）が独立して `architecture/` の存在チェックを行う。共通ミドルウェア化しない。

**理由**: コンポーネントの独立性を維持。他プロジェクトへの影響ゼロを保証。

### D-2: drift 検出は WARNING のみ

`severity: WARNING`, `category: architecture-drift` として報告し、マージをブロックしない。

**理由**: architecture spec の陳腐化は漸進的に起こる。厳格な CRITICAL 判定は開発速度を低下させる。

### D-3: glossary 照合は MUST 用語のみ

`architecture/domain/glossary.md` の `### MUST 用語` セクションの用語のみを照合対象とする。SHOULD 用語は対象外。

**理由**: MUST 用語は設計の核心。SHOULD 用語まで含めると誤検知が増える。

### D-4: autopilot-retrospective は提示のみ

Phase で変更されたファイルと architecture/ の対応を確認し、乖離候補リストを出力するが、自動 Issue 化しない。

**理由**: 更新内容の判断は LLM が必要。自動 Issue 化は誤検知リスクがある。

### D-5: worker-architecture drift 検出は PR diff から

PR diff から新状態値（IssueState/SessionState 外）・domain/model.md 未定義エンティティ・glossary 未登録用語を検出する。

**理由**: PR diff は変更の最小単位。ファイル全体スキャンより誤検知が少ない。

## Risks / Trade-offs

| リスク | 影響 | 緩和策 |
|--------|------|--------|
| glossary.md の用語リストが増大すると照合コストが増加 | パフォーマンス低下 | MUST 用語のみに限定（D-3） |
| architecture/ の部分的な更新により drift 検出が不正確 | 誤通知 | WARNING のみ・ブロックなし（D-2）で許容 |
| co-issue Step 1.5 で大量の INFO 通知が出ると開発体験が悪化 | ノイズ増大 | 1 件以上で 1 回だけ通知（まとめ形式） |
