# Security Review: Phase Z Wave A-G1

実施日: 2026-04-24
対象: 62e67a3..b7ad439 (14 PR, plugins/twl/scripts 中心)
ベースライン: refs/baseline-security-checklist.md, refs/baseline-input-validation.md

## CRITICAL (即時修正必要)

なし。

## WARNING (要注意)

なし。

## PASS (問題なし)

### 1. シークレット/トークン漏洩
- `auto-merge.sh` L183: GitHub トークンを `ghp_***MASKED***` でマスキング済み ✅
- 削除ファイルに認証情報なし ✅

### 2. コマンドインジェクション
- `chain-runner.sh` の `step_id` バリデーション (`^[a-z0-9-]+$`) ✅
- `auto-merge.sh` の `BRANCH` バリデーション (`^[a-zA-Z0-9._/-]+$`) ✅
- `autopilot-orchestrator.sh` の workflow allow-list `/twl:workflow-[a-z][a-z0-9-]*( #[0-9]+)?$` ✅
- `inject-next-workflow.sh` の allow-list ✅
- `autopilot-launch.sh`: `printf '%q'` によるエスケープ ✅
- `specialist-audit.sh` の ISSUE_NUM 数値検証 ✅

### 3. パストラバーサル
- `arch-ref` ステップ: `grep -q '\.\.'` による `..` 拒否 ✅
- `autopilot-orchestrator.sh`: 絶対パスチェック + `/\.\./` 拒否 ✅
- `autopilot-launch.sh`: 全 DIR 引数にパス検証 ✅

### 4. 削除による認証バイパス
- `DIRECT_SKIP_STEPS=()` が空のため direct モードでもステップスキップなし ✅
- `pr-review-manifest.sh` L157-162: merge-gate モードで worker-code-reviewer と worker-security-reviewer が常に必須 ✅ (quick 廃止後も維持)

### 5. 新規追加コード入力検証 (state.py)
- `_VALID_SET_KEY_RE`, `_VALID_FIELD_RE`, `_VALID_REPO_RE` の正規表現バリデーション ✅
- `_validate_issue_num` の整数チェック ✅

## 総評

**status: PASS**

Phase Z Wave A-G1 はセキュリティ観点で問題なし。入力バリデーションは一貫して正規表現ホワイトリスト方式。
quick ラベル廃止後も specialist review の必須化ルールが維持されており、セキュリティ審査バイパスリスクなし。
