# マージ判定（chain-driven）

## Context (auto-injected)
- Branch: !`git branch --show-current`
- Issue: !`source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo ""`
- PR: !`gh pr view --json number -q '.number' 2>/dev/null || echo "none"`

PR の最終判定を行う。動的レビュアー構築 → 並列 specialist 実行 → 結果集約 → PASS/REJECT。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

## ドメインルール

### PR 存在確認（MUST — 最初に実行）

merge-gate は PR が存在しない状態で実行してはならない（Issue #649）。動的レビュアー構築より先に実行すること。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-pr.sh"
```

PR が存在しない場合は即座に REJECT。Supervisor / Pilot が PR を作成（`intervene-auto --pattern pr-create`）してから再実行すること。

### 動的レビュアー構築

```bash
eval "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-build-manifest.sh")"
trap 'rm -f "$MANIFEST_FILE" "$SPAWNED_FILE"' EXIT
```

マニフェスト各行を Task spawn 対象とする（手動追加・削除は MUST NOT）。**quick ラベルが付与されていても specialist マニフェスト生成・spawn を省略してはならない（MUST NOT）**。quick が影響するのは phase-review checkpoint チェックのスキップのみであり、specialist review の実行には影響しない。`pr-review-manifest.sh` は merge-gate モードで最低限 `worker-code-reviewer` と `worker-security-reviewer` を必ず出力するため、マニフェスト 0 行は自動 PASS としない。クリーンアップは eval 直後に設定した親シェル側 trap で行う。

### 並列 specialist 実行（MUST: 全 specialist 一括 spawn）

マニフェストファイルを読み、**全行の specialist を 1 回のメッセージで同時に Task spawn すること**。
部分的な spawn は禁止。spawn 漏れは merge 判定の信頼性を毀損する。
```bash
# マニフェスト読み込み
mapfile -t SPECIALIST_LIST < <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$')
echo "spawn 対象 specialist (${#SPECIALIST_LIST[@]} 件):"
printf '  - %s\n' "${SPECIALIST_LIST[@]}"
```

上記で出力された全 specialist を以下の形式で **1 回のメッセージ内に全て並列で** Task spawn する:
```
Task(subagent_type="twl:<name>", prompt="PR diff を入力としてレビューを実行")
```
出力は ref-specialist-output-schema 準拠。

### spawn 完了確認（MUST: 結果集約の前提条件）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-spawn.sh"
```

このチェックが ERROR を返した場合、**未 spawn の specialist を追加 spawn** してから再度チェックを実行する。PASS するまで結果集約に進んではならない。

### 結果集約

```bash
PARSED=$(echo "$OUTPUT" | python3 -m twl.autopilot.parser)
STATUS=$(echo "$PARSED" | jq -r '.status')
FINDINGS=$(echo "$PARSED" | jq -c '.findings')
python3 -m twl.autopilot.checkpoint write --step merge-gate --status "$STATUS" --findings "$FINDINGS"
```

AI による自由形式変換は禁止。

### PR コメント投稿（specialist findings 永続化）

checkpoint 書き込み後、specialist findings を PR コメントとして投稿する。
findings が 0 件でも投稿（証跡として「No findings」を記録）。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-comment-findings
```

### checkpoint 統合（MUST）

```bash
COMBINED_FINDINGS=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-checkpoint-merge.sh" "$FINDINGS")
```

all-pass-check checkpoint も同形式で読み込む。ac-verify checkpoint 不在時は WARN を出して継続（autopilot 配下では異常ケース）。

### phase-review checkpoint 必須チェック（MUST）

phase-review checkpoint は merge-gate の必須ゲートである（defense-in-depth、Issue #439）。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-phase-review.sh" ${MERGE_GATE_FORCE:-}
```

- `scope/direct` / `quick` ラベル付き Issue は phase-review チェックをスキップ（軽微変更のため除外）
- phase-review 不在かつ `--force` フラグあり: WARNING ログ記録して継続
- `--force` を有効にするには `MERGE_GATE_FORCE=--force` 環境変数を設定する（緊急回避用。通常は使用しない）

### severity フィルタ判定（機械的のみ）

```
BLOCKING = COMBINED_FINDINGS WHERE severity == "CRITICAL" AND confidence >= 80
PASS  ⇔ BLOCKING == 0
REJECT ⇔ BLOCKING >= 1
```

### PASS / REJECT 時の状態遷移

PASS / REJECT 後の状態遷移ロジック（autopilot/Pilot 分岐、retry_count 管理、fix_instructions 記録、不変条件 C/E）の正典は `plugins/twl/architecture/domain/contexts/autopilot.md` および `cli/twl/src/twl/autopilot/state.py`。本 composite は judgement を出力するのみで、状態遷移の実装は呼び出し元 controller / state.py に委譲する。

## チェックポイント（MUST）

チェーン完了。
