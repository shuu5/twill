# Pseudo-Pilot Helper Scripts

Pseudo-Pilot 運用（autopilot bypass で Pilot が手動 spawn/verify/merge するモード）で必要な helper スクリプト群。

## 目的

PC 再起動後も helper が再利用可能なように、git 管理下（`plugins/twl/scripts/pseudo-pilot/`）に永続化されている。
`git pull` 後にすぐ利用可能であり、`/tmp/` の ad-hoc スクリプトのように再起動で消失しない。

## スクリプト一覧

### pr-wait.sh

指定 branch で PR が作成されるまで polling する。

**使い方:**
```bash
./pr-wait.sh <branch> [--timeout SECONDS] [--interval SECONDS]
```

**引数:**
- `<branch>` — polling 対象の branch 名（必須）
- `--timeout SECONDS` — 最大待機時間（default: 1800 秒）
- `--interval SECONDS` — polling 間隔（default: 10 秒）

**exit code:**
- `0` — PR 検出成功（PR 番号を stdout に出力）
- `1` — timeout
- `2` — 依存エラー（`gh` CLI 未インストール）または引数エラー

**依存:** `gh` CLI（auth 済み前提）

**例:**
```bash
# feat/123-my-feature ブランチの PR を待機
./pr-wait.sh feat/123-my-feature

# タイムアウトと polling 間隔を指定
./pr-wait.sh feat/123-my-feature --timeout 600 --interval 5
```

---

### worker-done-wait.sh

指定 tmux window が `input-waiting` 状態になるまで polling する。

**使い方:**
```bash
./worker-done-wait.sh <window> [--timeout SECONDS] [--interval SECONDS]
```

**引数:**
- `<window>` — 監視対象の tmux window 名（必須）
- `--timeout SECONDS` — 最大待機時間（default: 1800 秒）
- `--interval SECONDS` — polling 間隔（default: 5 秒）

**exit code:**
- `0` — `input-waiting` 状態を検出
- `1` — timeout
- `2` — 依存エラー（`tmux` 未インストール / `session-state.sh` 未存在）または引数エラー

**依存:** `tmux` および `plugins/session/scripts/session-state.sh`

**設計判断:** `session-state.sh` の `wait` サブコマンドは使わず、`state <window>` を polling して厳密一致 `input-waiting` を確認する。これにより `wait` の信頼性問題（Issue 背景参照）を内包しない。

**例:**
```bash
# tmux window "worker-01" が input-waiting になるまで待機
./worker-done-wait.sh worker-01

# タイムアウトを指定
./worker-done-wait.sh worker-01 --timeout 300
```

---

## 永続化要件

本ディレクトリは git 管理されているため、`git pull` 後に再起動を跨いでも helper が再利用可能。
`/tmp/` の ad-hoc スクリプトとは異なり、PC 再起動後も消失しない。
