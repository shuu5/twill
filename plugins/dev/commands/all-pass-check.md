# 全パス判定（autopilot-first）

## Context (auto-injected)
- Branch: !`git branch --show-current`
- Issue: !`git branch --show-current | grep -oP '^\w+/\K\d+(?=-)' 2>/dev/null || echo ""`
- PR: !`gh pr view --json number -q '.number' 2>/dev/null || echo "none"`

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

### Step 1.5: autopilot 配下判定（不変条件B/C）

ISSUE_NUM が取得できる場合、autopilot 配下かを判定する。

```bash
AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
```

### Step 2: 状態遷移

#### PASS の場合

autopilot 配下判定結果に応じて遷移先を決定:

**IS_AUTOPILOT=true の場合（MUST）:**

```bash
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=merge-ready"
echo "autopilot 配下: merge-ready 宣言。Pilot による merge-gate を待機。"
```

merge-ready に遷移し、Pilot による merge-gate を待機する。merge は実行しない。

**IS_AUTOPILOT=false の場合:**

```bash
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=merge-ready"
```

issue-{N}.json の status を `merge-ready` に遷移。Pilot が merge-gate を実行する。

#### FAIL の場合

```bash
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=failed"
```

issue-{N}.json の status を `failed` に遷移。失敗ステップと理由を記録。

### 設計方針

autopilot-first 前提で設計。旧プラグインのフラグ分岐・環境変数チェック・マーカーファイル管理は不要。
状態管理は issue-{N}.json と state-write.sh に一元化されている。

## チェックポイント（MUST）

`/dev:merge-gate` を Skill tool で自動実行。
