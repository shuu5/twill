# Worker auto mode 確認方針（observer 観察用 — Issue #800）

Pilot が `autopilot-launch.sh` で起動する Worker は `--permission-mode auto` 付きで cld 経由起動される。Worker pane tail に `⏵⏵ auto mode on` が出ない場合でも auto mode は有効である（positional prompt 即送信で status bar が上書きされる仕様。Issue #800 explore で全起動経路を検証済み）。observer / Pilot は以下の手順で間接的に確認する。

## 確認方法 A（一次指標 — heartbeat / state file existence）

`autopilot-launch.sh` 起動後 5 秒以内に以下を実行し、Worker が正常起動したことを確認する:

```bash
# heartbeat ファイル または worker-*.json の存在を確認
ls .supervisor/events/heartbeat-* 2>/dev/null || ls .supervisor/events/worker-*.json 2>/dev/null
```

**期待出力**: 1 つ以上のファイル名が出力される（exit 0 + stdout に 1 行以上）。0 件かつ exit 非 0 の場合は Worker 起動失敗または delay。10 秒待って再試行する。

## 確認方法 B（二次指標 — pane capture grep）

Worker が起動済み（pane が `Brewing` / `Concocting` / `idle` 等の LLM indicator を表示）状態で:

```bash
tmux capture-pane -t <worker-win> -p -S -50 | grep -E '⏵⏵ auto mode|permission_mode'
```

**期待出力**: 1 行以上のマッチ（exit 0）。マッチが見られれば auto mode 有効と判定。マッチが 0 行でも `autopilot-launch.sh` の起動行に `--permission-mode auto` が含まれる限り auto mode は有効（pane 上の表示有無は status bar 上書きタイミングに依存する）。

## 注意事項

- pane tail に `⏵⏵ auto mode on` が出ないこと自体を「auto mode 効いていない」と誤認してはならない
- Worker bash で permission prompt（`1. Yes, proceed` / `2. No, and tell ...`）が出た場合、auto mode classifier の `soft_deny` 該当（仕様）の可能性が高い → su-observer の `refs/pitfalls-catalog.md` §4.7 / §4.8 で対処
