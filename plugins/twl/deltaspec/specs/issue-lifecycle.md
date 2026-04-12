# Issue Lifecycle

co-issue による要望→Issue 変換ワークフロー（4 Phase 構成: 問題探索 → 分解判断 → Per-Issue 精緻化 → 一括作成）を定義するシナリオ。

## Scenario: Phase 1 問題探索（Architecture Context 注入）

- **WHEN** co-issue が実行される
- **AND** `architecture/` ディレクトリが存在する
- **THEN** vision.md・context-map.md・glossary.md を Read して ARCH_CONTEXT として保持する
- **AND** `/twl:explore` に「問題空間の理解に集中」と ARCH_CONTEXT を注入して呼び出す
- **AND** 起動時に SESSION_ID が生成される（例: `1712649600_a3f2`）
- **AND** 探索結果が `.controller-issue/<session-id>/explore-summary.md` に書き出される
- **AND** scope/* が判明した場合、context-map.md のノードラベルから該当コンポーネントの architecture ファイルを ARCH_CONTEXT に追加する

## Scenario: explore-summary 継続判定（セッションID対応）

- **WHEN** co-issue 起動時に glob `.controller-issue/*/explore-summary.md` でセッション検出する
- **AND** 検出件数が 0 件の場合: 新規 Phase 1 開始
- **AND** 検出件数が 1 件の場合: 「継続しますか？」と確認される
- **THEN** [A] 継続 → SESSION_ID を既存セッションに合わせて Phase 2 から再開する
- **AND** [B] 最初から → `.controller-issue/<session-id>/` を削除して Phase 1 から開始する
- **AND** 検出件数が 2 件以上の場合: AskUserQuestion でセッション選択 UI を表示する（ID + 作成日時 + 問題タイトル、[新規開始] オプション付き）

## Scenario: glossary 照合（Step 1.5）

- **WHEN** Phase 1 完了後に glossary 照合が実行される
- **THEN** explore-summary.md の用語と glossary.md の MUST 用語が照合される
- **AND** 不一致は INFO レベルで通知される（非ブロッキング）

## Scenario: Phase 2 分解判断（単一 Issue）

- **WHEN** explore-summary.md の内容が単一の Issue で表現可能と判断される
- **THEN** 分解せず単一 Issue として Phase 3 に進む

## Scenario: Phase 2 分解判断（複数 Issue）

- **WHEN** explore-summary.md の内容が複数の Issue に分解可能と判断される
- **THEN** AskUserQuestion で [A] この分解で進める / [B] 調整 / [C] 単一のまま を確認する

## Scenario: クロスリポ検出（Step 2a）

- **WHEN** explore-summary が複数のリポジトリに言及している
- **THEN** GitHub Project のリンク済みリポから対象リポを動的取得する（ハードコード禁止）
- **AND** 2+ リポ検出時は AskUserQuestion で [A] リポ単位分割 / [B] 単一 Issue を確認する
- **AND** [A] → cross_repo_split=true、target_repos を記録する

## Scenario: quick 判定（Step 2b）

- **WHEN** 変更ファイルが 1-2 個 AND 約 20 行以下 AND patch レベルの変更
- **THEN** `is_quick_candidate: true` が設定される
- **AND** quick 候補も specialist レビュー（Phase 3）はスキップ禁止

## Scenario: Phase 3 specialist レビュー（spawn 粒度）

- **WHEN** N 件の Issue が精緻化される
- **THEN** `/twl:issue-spec-review` が 1 Issue につき 1 回呼び出される（N 回）
- **AND** 各呼び出しが内部で 3 specialist（issue-critic, issue-feasibility, worker-codex-reviewer）を spawn する
- **AND** 合計 3N specialist が起動される
- **AND** N 回の Skill 呼び出しは並列で発行してよい
- **AND** 複数 Issue を 1 回の呼び出しに渡すことは禁止

## Scenario: Phase 3 同期バリア

- **WHEN** Step 3b の全 `/twl:issue-spec-review` 呼び出しが実行される
- **THEN** 全呼び出しが完了を返すまで Step 3c（aggregate）に進んではならない
- **AND** specialist がまだ実行中の状態で aggregate や修正に着手することは禁止

## Scenario: Phase 3 レビュー結果集約（Step 3c）

- **WHEN** 全 specialist レビューが完了する
- **THEN** `/twl:issue-review-aggregate` で結果が集約される
- **AND** CRITICAL findings なし → Step 3.5 へ進む
- **AND** CRITICAL findings あり → ユーザー通知・修正後 Step 3b 再実行可

## Scenario: architecture drift detection（Step 3.5）

- **WHEN** 精緻化済み Issue が architecture spec に影響する可能性がある
- **THEN** `/twl:issue-arch-drift` で architecture 影響が検出される
- **AND** arch-ref タグ・不変条件/Entity 変更言及・ctx/* ラベル 3 以上のいずれかに該当する場合、co-architect を提案する
- **AND** 検出結果は INFO レベルで通知される（非ブロッキング）

## Scenario: Phase 4 Aggregate & Present

- **WHEN** 精緻化が完了し全候補の report.json が出力される
- **THEN** co-issue が全 report.json を集約し summary table を提示する
- **AND** failure/circuit_broken がある場合は retry/manual fix/accept partial を AskUserQuestion で確認する

## Scenario: Phase 4 Project Board 同期

- **WHEN** Issue が作成される
- **THEN** 各 Issue 後に `/twl:project-board-sync N` が実行される
- **AND** Board 同期失敗は警告のみでワークフローを停止しない
- **AND** `chain-runner.sh board-status-update` を直接呼ばない（デフォルトが In Progress のため）

## Scenario: Phase 4 クロスリポ作成

- **WHEN** cross_repo_split=true で Issue 作成する
- **THEN** `/twl:issue-cross-repo-create` で parent + 子 Issue が各リポに作成される

## Scenario: co-issue thin orchestrator 構成

- **WHEN** co-issue が実行される
- **THEN** co-issue SKILL.md は Phase 1-2 を inline で実行し、Phase 3-4 は DAG 依存解決 + Level-based dispatch + aggregate で実行する thin orchestrator として動作する
- **AND** Phase 3 は `issue-lifecycle-orchestrator.sh` 経由で `workflow-issue-lifecycle` Worker を並列 spawn する
- **AND** co-issue の calls から ref-issue-template-bug, ref-issue-template-feature, ref-project-model, ref-issue-quality-criteria, ref-glossary-criteria への直接参照が除去される
- **AND** これらの reference は workflow-issue-lifecycle が内部で参照する

## Scenario: 完了とクリーンアップ

- **WHEN** Phase 4 が完了する（正常完了・中止問わず）
- **THEN** `.controller-issue/<session-id>/`（自セッションのみ）が削除される
- **AND** 他セッションの `.controller-issue/<other-session-id>/` は削除されない
- **AND** Issue URL が表示され `/twl:workflow-setup #N` で開発開始が案内される
