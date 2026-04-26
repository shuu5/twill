# su-observer 監視受入・chain 連携起動

co-autopilot は su-observer から spawn・監視される設計（ADR-014 Decision 2）。
su-observer が `supervise` モードで起動すると、co-autopilot の tmux window を監視対象として選択し
3 層介入プロトコル（Auto/Confirm/Escalate）に従って問題を検出・対処する。

**起動パターン:**

1. **co-autopilot 単独起動**（後方互換）: ユーザーが直接 `co-autopilot` を起動し、su-observer は別途起動して監視にアタッチする
2. **su-observer spawn 起動**: su-observer がユーザー指示に基づき co-autopilot セッションを spawn する（ADR-014 Decision 2 の正規フロー）

## spawn-controller.sh 経由 chain 連携起動（`--with-chain`）

su-observer が `spawn-controller.sh` 経由で co-autopilot を起動する場合、2 種類のモードを使い分ける:

| モード | コマンド例 | window 名 | state file | chain |
|--------|-----------|-----------|------------|-------|
| **standalone**（デフォルト） | `spawn-controller.sh co-autopilot /tmp/prompt.txt` | `wt-co-autopilot-<HHMMSS>` | 未生成 | 不回転 |
| **chain 連携**（`--with-chain`） | `spawn-controller.sh co-autopilot /tmp/ctx.txt --with-chain --issue N` | `ap-#N` | `issue-N.json` 生成 | 回転 |

chain 連携モード（`--with-chain`）では `spawn-controller.sh` が `autopilot-launch.sh` に委譲する。`autopilot-launch.sh` が state file 初期化・worktree 作成・orchestrator 起動・crash-detect hook 設定を担う。

```bash
# chain 連携起動例（su-observer からの典型的な呼び出し）
spawn-controller.sh co-autopilot /tmp/issue-835-ctx.txt --with-chain --issue 835

# --project-dir / --autopilot-dir は省略時に bare repo 構造から自動解決される
spawn-controller.sh co-autopilot /tmp/ctx.txt --with-chain --issue 835 \
  --project-dir /path/to/project --autopilot-dir /path/to/.autopilot
```

co-autopilot は su-observer の存在を前提とせず動作する。su-observer との連携は state ファイル（`$AUTOPILOT_DIR/session.json`, `issue-{N}.json`）と tmux window 名を通じて疎結合に行われる。

## 起動経路比較（#836 文書化）

co-autopilot 起動には 2 経路が存在する。混同すると chain が不回転になる（`pitfalls-catalog §13` 参照）。

| 項目 | 経路 A: `autopilot-launch.sh`（Worker 起動） | 経路 B: `spawn-controller.sh co-autopilot`（Pilot spawn） |
|------|---------------------------------------------|----------------------------------------------------------|
| **呼び出し元** | co-autopilot Pilot（`autopilot-launch.md`） | su-observer |
| **window 名** | `ap-<N>`（Issue 番号ベース） | `wt-co-autopilot-<HHMMSS>` |
| **state file** | `issue-<N>.json` 生成（`--init`） | Pilot が内部で生成（経路 A を経由） |
| **起動対象** | Worker セッション（Issue 1 件） | Pilot セッション全体（co-autopilot SKILL） |
| **chain** | 回転（`/twl:workflow-setup #N` を inject） | co-autopilot Step 1-5 が回転 |
| **使用場面** | Issue 単位 Worker 起動（co-autopilot 内部） | observer から Issue 群を一括実装する場合 |
| **注意** | 直接呼び出し禁止（co-autopilot 内部専用） | state file は Pilot 経由（経路 A）で生成される |
