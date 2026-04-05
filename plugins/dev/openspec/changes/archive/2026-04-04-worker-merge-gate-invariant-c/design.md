## Context

autopilot Worker の不変条件C（Worker マージ禁止）が、コンテキスト乱れ（nudge 後の IS_AUTOPILOT 消失）や LLM 分岐の不確実性によって破られる。既存ガードの現状:

- `merge-gate-execute.sh` Layer 3 (L79-82): status=running/merge-ready を検出してログ出力するが、merge を **拒否しない**
- `auto-merge.sh` Layer 1: AUTOPILOT_STATUS=running → IS_AUTOPILOT=true と判定するが、state-read.sh が失敗した場合（|| echo ""）は IS_AUTOPILOT=false になり Layer 4 フォールバックに委ねる

2層の機械的ガードを追加することで、LLM の判断に依存せず不変条件Cを保証する。

## Goals / Non-Goals

**Goals:**
- `merge-gate-execute.sh` の merge 実行パスで status=running 時に exit 1 でブロック
- `auto-merge.sh` に IS_AUTOPILOT=false && AUTOPILOT_STATUS=running の矛盾検出フォールバックを追加
- 既存テストの全 PASS を維持
- 非 autopilot 環境（status 空）への影響ゼロ

**Non-Goals:**
- `commands/merge-gate.md` の変更（LLM 実行フローは #200 で対処）
- IS_AUTOPILOT 判定のスクリプト化（中期 Issue #129 で検討）
- chain-runner.sh / chain-steps.sh の変更
- compaction 復帰プロトコルの変更

## Decisions

### Fix 1: merge-gate-execute.sh の merge パスに status=running ブロックを追加

**場所**: `case "$MODE"` の `*)` ブランチ（デフォルト: merge 実行）の先頭、`REPO_MODE` 判定の前。

**実装**:
```bash
# 不変条件C: status=running での merge 実行を拒否（Worker が merge-ready 未宣言）
_autopilot_status=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$ISSUE" --field status 2>/dev/null || echo "")
if [[ "$_autopilot_status" == "running" ]]; then
  echo "[merge-gate-execute] ERROR: status=running（merge-ready 未宣言）での merge 実行は禁止されています（不変条件C）" >&2
  exit 1
fi
if [[ "$_autopilot_status" == "merge-ready" ]]; then
  echo "[merge-gate-execute] autopilot 検出 (status=merge-ready): Pilot セッションとして merge を実行"
fi
```

**既存 Layer 3 との関係**: 既存の Layer 3 (L79-82) は merge/reject 両パスを横断する位置にある。Fix 1 は **merge パスのみ** に限定して、reject パスへの影響を回避する。既存 Layer 3 は削除せず、Fix 1 を merge パス先頭に **追加** する。

**根拠**: Pilot は Worker が merge-ready を宣言した後のみ merge-gate-execute.sh の merge パスを呼ぶ。status=running で呼ばれることは正常フローでは発生しない → exit 1 は safe。

### Fix 2: auto-merge.sh に IS_AUTOPILOT=false && AUTOPILOT_STATUS=running の矛盾検出を追加

**場所**: Layer 1（IS_AUTOPILOT 判定）の直後、Layer 4 フォールバックの前。

**実装**:
```bash
if [[ "$IS_AUTOPILOT" == "false" && "$AUTOPILOT_STATUS" == "running" ]]; then
  echo "[auto-merge] ⚠️ 状態矛盾検出: IS_AUTOPILOT=false だが status=running" >&2
  bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready 2>/dev/null || true
  echo "[auto-merge] autopilot 配下（状態矛盾検出）: merge-ready 宣言。Pilot による merge-gate を待機。"
  exit 0
fi
```

**根拠**: 現行ロジックでは AUTOPILOT_STATUS=running → IS_AUTOPILOT=true なので本来発生しない。将来のリファクタリング時の安全弁。state-write.sh 失敗時は `|| true` で握りつぶして exit 0 とし、merge を実行しないことを最優先とする。

### テスト設計

新規ファイル `tests/bats/scripts/fix-worker-merge-gate-invariant-c.bats`:

- `merge-gate-execute.sh`: status=running 時に exit 1 を返すこと
- `merge-gate-execute.sh`: --reject モードが status=running 時に exit 1 を返さないこと（非回帰）
- `merge-gate-execute.sh`: status=merge-ready 時（Pilot フロー）に merge を試みること
- `auto-merge.sh`: IS_AUTOPILOT=false && status=running 矛盾時に merge-ready 宣言して exit 0 を返すこと

## Risks / Trade-offs

- **state-read.sh が失敗する場合**: `|| echo ""` により status が空になり Fix 1 はスキップされる。Layer 4 フォールバック（issue-{N}.json 存在チェック）が次の防御層として機能する。
- **非 autopilot 環境**: status が空（state-read.sh がファイル不在でエラー）のため Fix 1/2 ともにスキップ。既存フローに影響なし。
- **Pilot の正常フロー**: status=merge-ready の場合、Fix 1 は merge を許可（exit しない）。正常動作を維持。
