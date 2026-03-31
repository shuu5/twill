## Context

autopilot-init.sh は .autopilot/ ディレクトリの初期化とセッション排他制御を担う。現在の実装では、session.json が存在し 24h 未満の場合、セッション状態に関係なく一律ブロックする。しかし全 issue が done の完了済みセッションは実質 inactive であり、再実行をブロックする理由がない。

autopilot-init.md は co-autopilot Step 3 から呼ばれるラッパーで、`eval "$(bash autopilot-init.sh)"` を使用しているが、スクリプトの出力は人間向けメッセージ（"OK: .autopilot/ を初期化しました"）であり、eval 対象として不適切。

## Goals / Non-Goals

**Goals:**

- 完了済みセッション（全 issue done）を `--force` で経過時間に関係なく削除可能にする
- running issue がある場合のみ 24h 制限を維持する
- autopilot-init.md から `eval` を除去し、直接 bash 実行に変更する

**Non-Goals:**

- session.json のスキーマ変更
- 自動 stale 検出（cronベースのクリーンアップ等）
- --force なしでの自動削除

## Decisions

1. **完了判定は session.json の issues フィールドで行う**: session.json 内の全 issue の status が "done" であれば完了済みと判定。jq で `[.issues[].status] | all(. == "done")` を評価する。issues フィールドが存在しない、または空の場合も完了済みとして扱う（レガシー互換）。

2. **判定順序**: `--force` + 完了済み → 即削除。`--force` + running issue あり + 24h 超 → 削除。`--force` + running issue あり + 24h 未満 → ブロック。`--force` なし → 従来通り。

3. **eval 除去**: `eval "$(bash ...)"` を `bash ...` に変更。スクリプトの戻り値は `$?` で確認する。

## Risks / Trade-offs

- **issues フィールド不在時の扱い**: レガシー session.json に issues フィールドがない可能性がある。安全側に倒して「完了済み」扱いとする（不明なセッションの再利用をブロックするより、初期化を許可する方が実用的）
- **競合状態**: 完了判定と削除の間に issue status が変わる可能性は理論上あるが、autopilot は単一プロセス実行のため実質無視できる
