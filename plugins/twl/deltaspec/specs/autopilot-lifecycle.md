# Autopilot Lifecycle

co-autopilot のライフサイクル全体を定義するシナリオ。Autopilot-first 原則に基づき、単一 Issue も本 controller 経由で実行する。

## Scenario: 単一 Issue の autopilot 実行

- **WHEN** ユーザーが `co-autopilot #42` を実行する
- **THEN** plan.yaml に Phase 1（issues: [42]）が生成される
- **AND** Pilot が worktree `worktrees/feat/42-xxx/` を事前作成する（不変条件 B）
- **AND** Worker が chain ステップを逐次実行する
- **AND** Worker が issue-42.json の status を `merge-ready` に更新する
- **AND** Pilot が merge-gate を実行する
- **AND** merge-gate PASS で squash merge が実行される
- **AND** Pilot が worktree を削除し autopilot-summary を出力する

## Scenario: 複数 Phase の逐次実行

- **WHEN** 依存関係 #10→#11→#12 を持つ 3 Issue で co-autopilot を実行する
- **THEN** plan.yaml に 3 Phase が生成される（Phase 1: [#10], Phase 2: [#11], Phase 3: [#12]）
- **AND** Phase 1 が完了してから Phase 2 が開始される
- **AND** Phase 2 が完了してから Phase 3 が開始される

## Scenario: Phase 内並列実行

- **WHEN** 互いに依存しない #10 と #11 が同一 Phase に含まれる
- **THEN** #10 と #11 の Worker が並列に起動される
- **AND** 両方の Worker が merge-ready になるまで Phase は完了しない

## Scenario: Phase 内 Issue 失敗時の skip 伝播

- **WHEN** Phase 1 の Issue #10 が failed になる
- **AND** Phase 2 の Issue #11 が #10 に依存している
- **THEN** Issue #11 は自動 skip される（不変条件 D）
- **AND** skip は連鎖的に伝播し、#11 に依存する Phase 3 以降の全 Issue も再帰的に skip される
- **AND** issue-11.json の status が `failed` に遷移し failure.message に skip 理由が記録される

## Scenario: session.json 初期化

- **WHEN** co-autopilot セッションが開始される
- **THEN** session.json が作成され session_id, plan_path, current_phase=1 が設定される
- **AND** 既存の session.json がある場合はエラー終了する（同時実行禁止）

## Scenario: Worker crash 検知

- **WHEN** Worker の tmux pane が予期せず終了する
- **THEN** Pilot の poll ループが pane 死亡を検知する（不変条件 G）
- **AND** issue-{N}.json の status が `failed` に遷移する
- **AND** failure に { message, step, timestamp } が記録される

## Scenario: retry 制限

- **WHEN** merge-gate が REJECT を返し retry_count=0 の場合
- **THEN** issue-{N}.json の status が failed → running に遷移する
- **AND** fix_instructions に findings が記録され Worker が fix-phase を実行する
- **WHEN** 再度 merge-gate が REJECT を返し retry_count=1 の場合
- **THEN** issue-{N}.json の status が failed に確定する（不変条件 E）
- **AND** Pilot に手動介入が要求される

## Scenario: Phase 完了時の後処理

- **WHEN** Phase 内の全 Issue が done または failed になる
- **THEN** autopilot-collect で変更ファイルを収集する
- **AND** autopilot-retrospective で Phase 振り返りを実行する
- **AND** autopilot-patterns でパターン検出を実行する
- **AND** 最終 Phase でなければ autopilot-cross-issue で影響分析を実行する

## Scenario: Phase 完了サニティチェック（Pilot 能動評価）

- **WHEN** orchestrator が PHASE_COMPLETE を返す
- **THEN** autopilot-phase-sanity で Issue close 状態を verify する
- **AND** autopilot-pilot-precheck で PR diff stat の削除行比率と AC spot-check を実行する
- **AND** precheck が WARN (high-deletion) を出した場合、autopilot-pilot-rebase で Pilot 介入 rebase を実行する
- **AND** 再 verify が必要な場合、autopilot-multi-source-verdict で multi-source 統合判断を実行する
- **AND** autopilot-phase-postprocess で retrospective / cross-issue / self-improve ECC 照合を実行する
- **AND** `PILOT_ACTIVE_REVIEW_DISABLE=1` の場合、precheck〜verdict はスキップされる

## Scenario: Emergency Bypass

- **WHEN** co-autopilot 自体の SKILL.md にバグがあり起動に失敗する
- **THEN** Emergency Bypass で main/ から直接実装→PR→merge が許可される
- **AND** セッション後に retrospective で理由を記録する義務がある

## Scenario: self-improve 統合

- **WHEN** autopilot-patterns が自リポジトリの Issue で繰り返しパターンを検出する
- **THEN** ECC 照合を自動追加し self-improve Issue を起票する
- **AND** session.json の self_improve_issues に Issue 番号が記録される

## Scenario: 引数解析（MODE 判定）

- **WHEN** ユーザーが `"#19, #18 → #20 → #23"` 形式の依存グラフ文字列を渡す
- **THEN** MODE=explicit として依存グラフが解析される
- **WHEN** ユーザーが `#18 #19 #20` 形式の Issue 番号リストを渡す
- **THEN** MODE=issues として各 Issue が独立に扱われる
- **WHEN** ユーザーが `--board` を指定する
- **THEN** MODE=board として Project Board の非 Done Issue が自動取得される
- **AND** `--auto` 指定時は計画確認をスキップして自動承認する

## Scenario: クロスリポジトリ autopilot

- **WHEN** `"lpd#42 twill#50"` 形式のクロスリポジトリ Issue リストが渡される
- **THEN** `--repos` JSON から各リポジトリの worktree 設定が解析される
- **AND** Worker は各リポジトリの worktree で起動される

## Scenario: セッション再開

- **WHEN** 中断されたセッションで co-autopilot を再実行する
- **THEN** issue-{N}.json の status から自動判定が行われる
- **AND** status=done の Issue はスキップされる
- **AND** status=merge-ready の Issue は即 merge-gate 実行される
- **AND** status=running の Issue は crash-detect.sh でクラッシュ検知される（不変条件 G）
- **AND** status=failed の Issue は依存先 skip が伝播される（不変条件 D）

## Scenario: 循環依存拒否

- **WHEN** plan.yaml 生成時に Issue 間の循環依存が検出される
- **THEN** autopilot-plan.sh がエラー終了する（不変条件 I）
- **AND** ユーザーに循環依存の詳細が報告される

## Scenario: Worktree ライフサイクル安全性

- **WHEN** autopilot セッション中に worktree 操作が発生する
- **THEN** worktree の作成・削除は Pilot のみが実行する（不変条件 B）
- **AND** Worker は Pilot が事前作成した worktree 内で起動される
- **AND** Worker が worktree を削除しようとした場合、worktree-delete.sh が拒否する
- **AND** Worker はマージを実行せず merge-ready を宣言するのみ（不変条件 C）

## Scenario: Worker chain 実行（setup → test-ready 遷移）

- **WHEN** Worker が workflow-setup chain を実行する
- **THEN** init → worktree-create(スキップ) → board-status-update → crg-auto-build → arch-ref → change-propose → ac-extract の順で chain step が実行される
- **AND** IS_AUTOPILOT=true のため、setup 完了後に即座に workflow-test-ready が自動遷移する
- **AND** workflow-test-ready は change-id 解決 → テスト生成 → check → change-apply の順で実行する
- **AND** change-apply 完了後に即座に workflow-pr-verify が自動遷移する

## Scenario: 軽微変更（Quick Issue）の短縮パス

- **WHEN** workflow-setup の init で IS_QUICK=true と判定される
- **AND** IS_AUTOPILOT=true である
- **THEN** workflow-test-ready は呼び出されない
- **AND** 直接実装 → commit → push → PR 作成（`Closes #N` 付き）→ ac-verify → merge-gate が実行される

## Scenario: compaction 復帰

- **WHEN** Worker セッションが context window compaction により状態を失う
- **THEN** ref-compaction-recovery.md に従い、chain-runner.sh の checkpoint から現在のステップを特定する
- **AND** 最後に完了したステップの次から実行を再開する
