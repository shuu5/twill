# 全パス判定（autopilot-first）

PR-cycle の全ステップ結果を検証し、merge-ready への遷移可否を判定する。
autopilot-first 前提で設計。旧フラグ分岐・マーカーファイル不使用。

## 入力

- 各ステップの実行結果（pr-cycle-report の構造化データ）
- issue-{N}.json の現在の status

## 出力

- 判定結果（PASS → merge-ready 遷移 / FAIL → failed 遷移）

## 実行ロジック（MUST）

### Step 1: 全ステップ PASS 判定

```
IF 全ステップの status が PASS または WARN（WARNING のみ、CRITICAL なし）
THEN → PASS
ELSE → FAIL
```

### Step 2: 状態遷移

#### PASS の場合

```bash
bash scripts/state-write.sh issue "${ISSUE_NUM}" status merge-ready
```

issue-{N}.json の status を `merge-ready` に遷移。Pilot が merge-gate を実行する。

#### FAIL の場合

```bash
bash scripts/state-write.sh issue "${ISSUE_NUM}" status failed
```

issue-{N}.json の status を `failed` に遷移。失敗ステップと理由を記録。

### 設計方針

autopilot-first 前提のため、旧プラグインのフラグ分岐・環境変数チェック・マーカーファイル管理は不要。
状態管理は issue-{N}.json と state-write.sh に一元化されている。
