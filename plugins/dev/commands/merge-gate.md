# マージ判定（chain-driven）

## Context (auto-injected)
- Branch: !`git branch --show-current`
- Issue: !`source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo ""`
- PR: !`gh pr view --json number -q '.number' 2>/dev/null || echo "none"`

PR の最終判定を行う。動的レビュアー構築 → 並列 specialist 実行 → 結果集約 → PASS/REJECT。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 8 | merge-gate（本コンポーネント） | composite |

## ドメインルール

### 動的レビュアー構築

PR diff のファイルリストから specialist を動的に構築する。
旧 standard/plugin 2 パスの分岐は**存在しない**（単一パス）。

#### 基本ルール

| 条件 | 追加される specialist |
|------|----------------------|
| deps.yaml 変更あり | worker-structure + worker-principles |
| コード変更あり | worker-code-reviewer + worker-security-reviewer |
| `architecture/` が存在する | worker-architecture（`pr_diff` モードで呼び出し） |

`architecture/` 存在チェック:

```bash
if [ -d "$(git rev-parse --show-toplevel)/architecture" ]; then
  # worker-architecture を specialist リストに追加
  # 呼び出し時は pr_diff モードを指定する
fi
```

`architecture/` が存在しないプロジェクトでは worker-architecture を追加してはならない（MUST NOT）。

#### conditional specialist

```bash
CONDITIONAL=$(bash scripts/tech-stack-detect.sh < <(git diff --name-only origin/main))
```

#### 補完的レビュアー（codex 環境チェック）

コード変更がある場合のみ、以下のチェックを実施して条件を満たせば worker-codex-reviewer をリストに追加する。

```bash
if command -v codex >/dev/null 2>&1 && [ -n "${CODEX_API_KEY:-}" ]; then
  # worker-codex-reviewer をリストに追加
fi
```

| 条件 | 追加される specialist |
|------|----------------------|
| コード変更あり AND `command -v codex` 成功 AND `CODEX_API_KEY` 設定済み | worker-codex-reviewer |

条件未達（codex 未インストール or `CODEX_API_KEY` 未設定）の場合は specialist リストに追加しない。

#### specialist リスト空の場合

レビュー対象外の変更のみ → 自動 PASS。

### 並列 specialist 実行

全 specialist を Task spawn で並列実行する。

```
各 specialist について:
  Task(subagent_type="dev:<specialist-name>", prompt="PR diff を入力としてレビューを実行")
```

各 specialist は共通出力スキーマ（ref-specialist-output-schema）に準拠した結果を返す。

### 結果集約

specialist-output-parse スクリプトで全出力をパースし findings を統合する。

```bash
PARSED=$(echo "$OUTPUT" | bash scripts/specialist-output-parse.sh)
```

**AI による自由形式の変換は禁止**。パーサーの構造化データのみを使用する。

### severity フィルタ判定

```
BLOCKING = findings WHERE severity == "CRITICAL" AND confidence >= 80
```

| 条件 | 判定 |
|------|------|
| BLOCKING が 0 件 | **PASS** |
| BLOCKING が 1 件以上 | **REJECT** |

AI 推論による判定は禁止。上記の機械的フィルタのみで判定する。

### PASS 時の状態遷移

autopilot 状態を state-read で確認し、フローを分岐する（不変条件 C）。

```bash
AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "${ISSUE_NUM}" --field status 2>/dev/null || echo "")

if [[ "$AUTOPILOT_STATUS" == "running" || "$AUTOPILOT_STATUS" == "merge-ready" ]]; then
  # autopilot 時（Worker が実行）: merge-ready を宣言して停止する
  # 既に merge-ready の場合は宣言済みのためスキップ
  if [[ "$AUTOPILOT_STATUS" != "merge-ready" ]]; then
    bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=merge-ready"
  fi
  echo "merge-gate: PASS。merge-ready 宣言済み。Pilot による merge を待機中。"
else
  # 非 autopilot 時（Pilot が実行）: merge-gate-execute.sh 経由でマージを実行する
  ISSUE="${ISSUE_NUM}" PR_NUMBER="${PR_NUMBER}" BRANCH="${BRANCH}" bash scripts/merge-gate-execute.sh
fi
```

### REJECT 時の状態遷移（1回目、retry_count=0）

```bash
# issue-{N}.json: merge-ready → failed → running
# retry_count は failed→running 遷移時に state-write.sh が自動インクリメント（L232）
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=failed"
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "fix_instructions=${BLOCKING_FINDINGS}"
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=running"

# Worker が fix-phase を実行
```

### REJECT 時の状態遷移（2回目、retry_count>=1 — 不変条件 E）

```bash
# issue-{N}.json: status → failed（確定）
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role pilot --set "status=failed"

# Pilot に手動介入を要求
echo "merge-gate: 確定失敗（リトライ上限到達）。Pilot の手動介入が必要です。"
```

### 設計方針

動的レビュアー構築による単一パス設計のため、旧プラグインのパス分岐・フラグ分岐・マーカーファイル管理は不要。
状態管理は issue-{N}.json と state-write.sh に一元化されている。

## チェックポイント（MUST）

チェーン完了。

