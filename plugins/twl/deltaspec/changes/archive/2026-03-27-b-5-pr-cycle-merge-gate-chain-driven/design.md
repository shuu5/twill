## Context

loom-plugin-dev は旧 dev plugin の後継として新規構築中。B-4 で setup chain を定義し chain-driven パターンを確立した。B-5 では同パターンを pr-cycle に適用し、より複雑な分岐（merge-gate 判定、fix ループ、並列 specialist）を chain で表現する。

chain の仕組み（B-4 で確立済み）:
- deps.yaml `chains` セクション: chain 名、type、steps リスト
- 各コンポーネント: `chain` フィールド（所属 chain）、`step_in`（親と step 番号）、`calls`（呼び出し先と step 番号）
- `loom chain validate`: 双方向参照整合性を検証

前提となる成果:
- B-3: 統一状態ファイル（issue-{N}.json / session.json）、state-read.sh / state-write.sh
- B-4: setup chain による chain-driven パターンの実践例
- B-6: specialist 共通出力スキーマ（ref-specialist-output-schema）
- architecture/domain/contexts/pr-cycle.md: エンティティ定義、ワークフロー、動的レビュアールール
- architecture/contracts/autopilot-pr-cycle.md: Autopilot-PR Cycle 間のインターフェース定義

## Goals / Non-Goals

**Goals:**

- deps.yaml に pr-cycle chain を定義し、chain-driven パターンの 2 番目の実践例とする
- merge-gate を standard/plugin 2 パスから動的レビュアー構築による単一パスに統合する
- specialist 出力パーサーを実装し、共通スキーマに基づく機械的な結果集約を行う
- --auto-merge 関連コードを排除し、autopilot-first 前提で all-pass-check を簡素化する
- `loom chain validate` が pr-cycle chain に対して pass する状態を達成する

**Non-Goals:**

- specialist（レビュアー）の内容やプロンプトの変更（C-2 系 Issue のスコープ）
- 新しい specialist の追加（既存の specialist を動的に選択するのみ）
- fix-phase の内部ロジック変更（既存の自動修正ループを chain ステップとして参照するのみ）
- visual screening / E2E テストの変更
- loom CLI 自体の機能拡張

## Decisions

### D1: Chain type の選択

pr-cycle chain は **Type A**（workflow + atomic）を採用する。

理由: pr-cycle の参加者は workflow-pr-cycle（workflow）、merge-gate / phase-review / fix-phase（composite）、および各 atomic で構成される。specialist は chain の step ではなく、phase-review 内部で動的に spawn されるため chain 定義には含まない。

### D2: Chain ステップ構成

pr-cycle chain を以下のステップで定義する:

| Step | コンポーネント | 型 | 説明 |
|------|--------------|------|------|
| 1 | ts-preflight | atomic | TypeScript 機械的検証 |
| 2 | phase-review | composite | 並列 specialist レビュー |
| 2.5 | scope-judge | atomic | スコープ判定 + Deferred Issue |
| 3 | pr-test | atomic | テスト実行 |
| 4 | fix-phase | composite | 自動修正ループ |
| 4.5 | post-fix-verify | atomic | fix 後の軽量レビュー |
| 5 | warning-fix | atomic | Warning ベストエフォート修正 |
| 6 | e2e-screening | composite | Visual 検証 |
| 7 | pr-cycle-report | atomic | 結果フォーマット・投稿 |
| 7.5 | all-pass-check | atomic | 全パス判定 |
| 8 | merge-gate | composite | マージ判定・実行 |

fix-phase → post-fix-verify のループは chain のリニアなステップ定義では表現しきれないため、workflow-pr-cycle SKILL.md のドメインルールとして残す。

### D3: merge-gate 単一パス設計

旧 standard/plugin 2 パスを廃止し、以下の単一フローに統合する:

1. **動的レビュアー構築**: PR diff のファイルリストから specialist を決定
   - deps.yaml 変更あり → worker-structure + worker-principles
   - コード変更あり → worker-code-reviewer + worker-security-reviewer
   - Tech-stack 該当あり → conditional specialist（tech-stack-detect スクリプトで判定）
2. **並列 specialist 実行**: 全 specialist を Task spawn
3. **結果集約**: 共通出力スキーマをパースし findings を統合
4. **判定**: `severity == CRITICAL && confidence >= 80` の finding 有無で PASS/REJECT

plugin 固有の loom validate / check は worker-structure が内部で実行するため、merge-gate 側でのパス分岐は不要。

### D4: specialist 出力パーサーの実装方針

script 型コンポーネント（`specialist-output-parse`）として実装する。

パースロジック:
1. 出力先頭行から `status: (PASS|WARN|FAIL)` を正規表現で抽出
2. JSON ブロック（```json ... ```）から findings 配列を抽出
3. 各 finding の必須フィールド（severity, confidence, file, line, message, category）を検証
4. パース失敗時: 出力全文を 1 つの WARNING finding（confidence=50）として扱う

消費側（merge-gate / phase-review）はパーサーを呼び出し、構造化データのみを扱う。AI による自由形式の変換は禁止。

### D5: all-pass-check の簡素化

autopilot-first 前提により以下を廃止:
- `--auto-merge` フラグの解析と分岐
- `DEV_AUTOPILOT_SESSION` 環境変数チェック
- `.merge-ready` マーカーファイルの書き込み

代替: issue-{N}.json の status フィールドで状態を管理（state-write.sh 経由）。
全ステップ PASS 時は status を `merge-ready` に遷移し、Pilot が merge-gate を実行する。

### D6: tech-stack-detect スクリプト

script 型コンポーネントとして実装する。入力はファイルパスのリスト、出力は追加すべき specialist のリスト。

判定ルール（初期実装）:
- `.tsx` / `.jsx` + Next.js プロジェクト（next.config.* 存在）→ worker-nextjs-reviewer
- `.py` + FastAPI（main.py or app.py に FastAPI import）→ worker-fastapi-reviewer
- Supabase migration（supabase/migrations/）→ worker-supabase-migration-checker
- `.R` / `.Rmd` / `.qmd` → worker-r-reviewer
- E2E テスト（*.spec.ts, *.test.ts in e2e/）→ worker-e2e-reviewer

## Risks / Trade-offs

### R1: Chain のリニアステップ制限

chain は基本的にリニアなステップ定義。fix-phase → 再レビュー → 再判定のループや、テスト失敗時の fix 分岐は chain 定義では表現できない。

**緩和**: これらの条件分岐は workflow-pr-cycle SKILL.md のドメインルールとして残す。chain はステップの順序と参加コンポーネントの宣言に責務を限定する。

### R2: specialist 出力パース精度

specialist が共通スキーマに厳密に準拠しない場合、パースが失敗する。

**緩和**: パース失敗のフォールバック（WARNING, confidence=50）を実装済み設計。B-6 の few-shot テンプレートが準拠率を担保。パース失敗は merge-gate のブロック閾値に達しないため、自動 REJECT にはならず手動レビューで対応可能。

### R3: loom#30 / loom#34 への依存

loom#30（chain generate --check/--all）と loom#34（JSON 出力）が未完了の場合、chain 乖離検出と機械的な validate 結果消費が制限される。

**緩和**: loom#30 なしでも `loom chain validate` の基本検証は動作する。loom#34 なしでもテキスト出力のパースで対応可能（ただし脆弱）。これらの依存は「あれば活用」レベルとし、B-5 の実装をブロックしない。
