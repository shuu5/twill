## 1. deps.yaml pr-cycle chain 定義

- [x] 1.1 deps.yaml の chains セクションに pr-cycle chain を追加（type: "A", steps リスト）
- [x] 1.2 workflow-pr-cycle を skills セクションに追加（type: workflow, calls リスト）
- [x] 1.3 `loom chain validate` で pr-cycle chain の整合性を検証

## 2. atomic コンポーネント登録・作成

- [x] 2.1 ts-preflight を deps.yaml に登録し COMMAND.md を作成（chain: pr-cycle, step: 1）
- [x] 2.2 scope-judge を deps.yaml に登録し COMMAND.md を作成（chain: pr-cycle, step: 2.5）
- [x] 2.3 pr-test を deps.yaml に登録し COMMAND.md を作成（chain: pr-cycle, step: 3）
- [x] 2.4 post-fix-verify を deps.yaml に登録し COMMAND.md を作成（chain: pr-cycle, step: 4.5）
- [x] 2.5 warning-fix を deps.yaml に登録し COMMAND.md を作成（chain: pr-cycle, step: 5）
- [x] 2.6 pr-cycle-report を deps.yaml に登録し COMMAND.md を作成（chain: pr-cycle, step: 7）
- [x] 2.7 all-pass-check を deps.yaml に登録し COMMAND.md を作成（chain: pr-cycle, step: 7.5）
- [x] 2.8 ac-verify を deps.yaml に登録し COMMAND.md を作成

## 3. composite コンポーネント登録・作成

- [x] 3.1 phase-review を deps.yaml に登録し SKILL.md を作成（chain: pr-cycle, step: 2, calls: 動的 specialist）
- [x] 3.2 fix-phase を deps.yaml に登録し SKILL.md を作成（chain: pr-cycle, step: 4）
- [x] 3.3 e2e-screening を deps.yaml に登録し SKILL.md を作成（chain: pr-cycle, step: 6）
- [x] 3.4 merge-gate を deps.yaml に登録し SKILL.md を作成（chain: pr-cycle, step: 8, calls: phase-review + 判定ロジック）

## 4. tech-stack-detect スクリプト

- [x] 4.1 tech-stack-detect を deps.yaml の scripts セクションに登録
- [x] 4.2 scripts/tech-stack-detect.sh を実装（ファイルパスリスト → specialist リスト出力）
- [x] 4.3 判定ルール実装（Next.js, FastAPI, Supabase migration, R, E2E）

## 5. specialist 出力パーサー

- [x] 5.1 specialist-output-parse を deps.yaml の scripts セクションに登録
- [x] 5.2 scripts/specialist-output-parse.sh を実装（status 行抽出 + JSON findings パース）
- [x] 5.3 パース失敗フォールバック実装（WARNING, confidence=50）

## 6. merge-gate 単一パス統合

- [x] 6.1 merge-gate SKILL.md に動的レビュアー構築ロジックを記述（deps.yaml 変更 / コード変更 / tech-stack 条件）
- [x] 6.2 merge-gate SKILL.md に並列 specialist 実行（Task spawn）のドメインルールを記述
- [x] 6.3 merge-gate SKILL.md に severity フィルタ判定ルールを記述（CRITICAL && confidence >= 80）
- [x] 6.4 PASS/REJECT 時の issue-{N}.json 状態遷移を記述（state-write.sh 連携）

## 7. all-pass-check 簡素化

- [x] 7.1 all-pass-check COMMAND.md を autopilot-first 前提で実装（--auto-merge 分岐なし）
- [x] 7.2 issue-{N}.json の status を merge-ready に遷移するロジックを実装
- [x] 7.3 マーカーファイル（.done, .fail, .merge-ready）の参照を排除

## 8. workflow-pr-cycle SKILL.md chain-driven 縮小

- [x] 8.1 workflow-pr-cycle SKILL.md を新規作成（ドメインルールのみ）
- [x] 8.2 fix ループ条件（テスト失敗 → fix-phase → 再テスト）を記述
- [x] 8.3 merge-gate エスカレーション条件（retry_count >= 1 → Pilot 報告）を記述
- [x] 8.4 chain ステップ順序やルーティングロジックが含まれないことを確認

## 9. 検証

- [x] 9.1 `loom chain validate` が pr-cycle chain に対して pass する
- [x] 9.2 `loom check` が全コンポーネントに対して pass する
- [x] 9.3 `loom update-readme` で README を更新する
