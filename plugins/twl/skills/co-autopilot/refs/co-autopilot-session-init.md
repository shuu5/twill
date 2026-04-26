# セッション初期化・終了手順（Step 3 / Step 5）

## Step 3: セッション開始時

### PYTHONPATH 設定（MUST）

まず python-env.sh を source して PYTHONPATH を設定する:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/python-env.sh"
```

これにより `cli/twl/src` の絶対パスが `PYTHONPATH` に追加される（python-env.sh が BASH_SOURCE から絶対パスを自動解決）。省略すると `python3 -m twl.autopilot.*` 呼び出し時に `ModuleNotFoundError` が発生する。

### 条件付き audit on（MUST）

PYTHONPATH 設定後、audit が非アクティブな場合のみ audit を開始する（二重呼び出しによるセッション上書きを防止）:

```bash
if ! twl audit status 2>/dev/null | grep -q "^active: true"; then
  twl audit on
fi
```

### AUTOPILOT_DIR 一致確認（MUST）

`autopilot-init` 実行前に、`AUTOPILOT_DIR` が `plan.yaml` と同じディレクトリを指していることを確認する。bare repo レイアウトでは `autopilot-plan.sh` が `.bare/` を検出して `main/.autopilot/` に plan.yaml を配置するため、Pilot も同じパスを使用すること。不一致はパストラバーサルエラーの原因になる (#660)。

## Step 5: セッション終了時

### クリーンアップ

サマリー報告後、一括クリーンアップを実行:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-cleanup.sh" --autopilot-dir "$AUTOPILOT_DIR"
```

done state file を即座にアーカイブし、TTL 超過の failed state file もアーカイブ。孤立 worktree を検出・削除する。`--dry-run` で事前確認も可能。

### 条件付き audit off（MUST）

クリーンアップ後、audit がアクティブな場合のみ停止する（非 active 時の RuntimeError を防止）:

```bash
if twl audit status 2>/dev/null | grep -q "^active: true"; then
  twl audit off
fi
```
