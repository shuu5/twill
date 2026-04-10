type: Feature
title: "[Feature] su-observer モード分離廃止 — セッションマネージャー型再設計 + spawn 統一"
scope: scope/plugins-twl, ctx/supervision, ctx/observation
is_quick_candidate: false
is_scope_direct_candidate: false

## 概要

su-observer SKILL.md と設計ドキュメント（su-observer-skill-design.md）からモード分離パターンを完全廃止し、LLM が文脈から自然に判断する常駐セッションマネージャーとして再設計する。全 controller の session:spawn 統一、session plugin スクリプト活用も同時に実装する。

## 背景・動機

su-observer は「ユーザーと controller の間に入るセッションマネージャー」であるべきだが、現行 SKILL.md と設計ドキュメントが「モード分離」パターンを採用しており、LLM の判断力を制限している。

**現行 SKILL.md の問題:**
1. Step 0「モード判定」テーブルで supervise / delegate-test / retrospect の 3 モードに強制ルーティング
2. 引数なし or 曖昧な場合は AskUserQuestion で 3 モードから選択させる（LLM が判断すべき）
3. Steps 1-3 がモード専用の処理で分離
4. Step 2 (delegate-test) が `Skill(twl:co-self-improve)` 直接呼出し（spawn ではない）
5. 常駐ループ構造が不完全

**設計ドキュメント（su-observer-skill-design.md）の問題:**
1. Step 1 に 6 モードのルーティングテーブル（autopilot, issue, architect, observe, compact, delegate）
2. 各モードが Steps 2-7 に対応する分離構造
3. SKILL.md がこれを「正典」として参照するため、正典自体がモード前提だと SKILL.md も修正不能

**あるべき姿（セッションマネージャー型）:**
- モードテーブルなし
- ユーザーの指示を LLM が文脈から解釈し、適切なアクションを選択
- 例: 「Issue 実装して」→ co-autopilot spawn + observe、「テストして」→ co-self-improve spawn + observe、「状況は？」→ observe + 報告
- spawn / observe / intervene / report / compact を状況判断で実行（「モード切替」ではなく自然な対話の中で）

**ADR-014 および supervision.md との関係:**
- ADR-014 のライフサイクル設計（常駐、spawn 型）は正しい — 維持
- supervision.md のワークフロー図はほぼ正しい（モードという単語を使っていない） — 軽微修正のみ
- SU-1〜SU-7 制約は全て維持

## スコープ

**含む:**

- su-observer SKILL.md の全面書き換え（モード分離廃止、常駐セッションマネージャー型、全 spawn、session plugin 活用）
- su-observer-skill-design.md のモード分離廃止（ルーティングテーブル → 行動判断ガイドライン）
- supervision.md のワークフロー図でモード言及があれば削除（軽微）
- co-self-improve SKILL.md の spawn 前提修正（Skill() 直接呼出し記述の削除、spawn される側の設計追加）
- deps.yaml: su-observer.supervises に co-self-improve を追加

**含まない:**

- ADR-014 自体の変更（設計判断は正しいため維持）
- session plugin スクリプト群の変更（既存実装をそのまま活用）
- compaction/知識外部化の再設計（Step 設計は変わるがロジック自体は維持）
- SU-* 制約の変更（全て維持）
- co-self-improve 自身の内部モード判定（scenario-run/retrospect/test-project-manage）の変更（su-observer のモード廃止とは独立）

## 技術的アプローチ

### SKILL.md の再設計構造

```
Step 0: セッション初期化
  - bare repo 検証、SupervisorSession 復帰/新規作成
  - Project Board 状態取得、doobidoo 記憶復元

Step 1: 常駐ループ（ユーザー入力を待ち、文脈に応じて判断・行動）
  - controller spawn が必要 → session:spawn で起動 + observe
  - 既存セッションの状態確認が必要 → observe-once + 報告
  - 問題検出 → intervention-catalog 照合 → Auto/Confirm/Escalate
  - compaction が必要 → su-compact 実行
  - Wave 管理が必要 → Wave 計画 + co-autopilot spawn + observe ループ
  - 全て「モード」ではなく、LLM の状況判断で実行

Step 2: セッション終了
```

### 設計ドキュメントの修正方針

su-observer-skill-design.md:
- 6 モードのルーティングテーブルを削除
- 代わりに「行動判断ガイドライン」を記述（どのような文脈でどの行動が適切かの指針）
- Step 構造を SKILL.md に合わせて簡素化（Step 0 初期化 / Step 1 常駐ループ / Step 2 終了）

### co-self-improve の修正

- su-observer SKILL.md Step 2 の `Skill(twl:co-self-improve)` 直接呼出しを `session:spawn` 経由に変更
- su-observer から spawn される側としての受取手順（spawn 時プロンプトからのモード・対象情報の受取）を追加
- co-self-improve 自身の内部モード判定（scenario-run/retrospect/test-project-manage）は維持（本 Issue のスコープ外）

### deps.yaml の修正

- su-observer.supervises に co-self-improve を追加（spawnable_by との非対称性を解消）
- su-observer.tools に session:spawn 関連の参照が必要か確認し、必要なら追加

### supervision.md の修正方針

supervision.md のワークフロー図にある分岐ラベル（「autopilot 指示」「issue 指示」等）は「モード」ではなく「LLM が文脈から判断した結果の例示」であり、維持する。「モード」という単語が使われている箇所があれば削除する。

## 受け入れ基準

- [ ] su-observer SKILL.md にモード判定テーブルが存在しない
- [ ] su-observer SKILL.md が常駐ループ構造（Step 0 初期化 → Step 1 ループ → Step 2 終了）になっている
- [ ] ユーザー入力に対する行動選択が LLM の文脈判断に委ねられている（AskUserQuestion でのモード選択を強制しない）
- [ ] 全 controller（co-autopilot, co-issue, co-architect, co-project, co-utility, co-self-improve）の起動が `session:spawn`（`plugins/session/scripts/cld-spawn`）経由になっている
- [ ] co-autopilot のみ `cld-observe-loop`（`plugins/session/scripts/cld-observe-loop`）による能動 observe がある
- [ ] 他 controller は spawn 後、状況に応じて `cld-observe`（`plugins/session/scripts/cld-observe`）で単発確認 or 指示待ちに戻る
- [ ] SKILL.md の Step 1 で session plugin スクリプト群が具体的に参照されている: `cld-spawn`（spawn）, `cld-observe`/`cld-observe-loop`（observe）, `session-state.sh`（状態確認）, `session-comm.sh`（inject/介入）
- [ ] su-observer-skill-design.md のモードルーティングテーブルが廃止され、行動判断ガイドラインに置換されている
- [ ] supervision.md のワークフロー図に「モード」という単語が残存しない（分岐ラベルは文脈判断の例示として維持可）
- [ ] su-observer SKILL.md Step 2 の `Skill(twl:co-self-improve)` 直接呼出しが `session:spawn` 経由に変更されている
- [ ] co-self-improve SKILL.md に spawn 時プロンプトからの情報受取手順が記載されている
- [ ] deps.yaml の su-observer.supervises に co-self-improve が含まれている
- [ ] SU-1〜SU-7 制約が全て維持されている

## Touched files

- plugins/twl/skills/su-observer/SKILL.md
- plugins/twl/architecture/designs/su-observer-skill-design.md
- plugins/twl/architecture/domain/contexts/supervision.md
- plugins/twl/skills/co-self-improve/SKILL.md
- plugins/twl/deps.yaml

## 推奨ラベル

- `scope/plugins-twl`: plugins/twl コンポーネント
- `ctx/supervision`: Supervision Context (Cross-cutting)
- `ctx/observation`: Live Observation Context (Supporting)

<!-- arch-ref-start -->
plugins/twl/architecture/domain/contexts/supervision.md
<!-- arch-ref-end -->
