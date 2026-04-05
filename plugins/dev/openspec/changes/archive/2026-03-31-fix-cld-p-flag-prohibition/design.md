## Context

`autopilot-launch.md` は Pilot Claude が Worker を起動する際の手順を定義するコマンドファイル。Step 5 のコード例は positional arg 方式で正しく記述されているが、禁止事項セクションに `cld -p` / `cld --print` の言及がない。Pilot Claude が `cld --help` を参照した際、`-p` を「プロンプト指定フラグ」と誤解して使用するリスクがある。

## Goals / Non-Goals

**Goals:**

- `autopilot-launch.md` の禁止事項に `cld -p` / `cld --print` 使用禁止を明記
- 禁止理由（非対話 print モードで即終了する）を記載
- Step 5 のコード例にコメントで注意書きを追加

**Non-Goals:**

- cld CLI 自体の変更
- autopilot-launch.md のロジック変更（Step 5 の positional arg 方式は正しい）
- 他のコマンドファイルの修正

## Decisions

1. **禁止事項セクション末尾に追加**: 既存の3項目に続けて4項目目として追加する。箇条書きスタイルを統一する。
2. **Step 5 コード例にインラインコメント**: tmux 起動行の直前にコメントで `-p` / `--print` を使わない旨を記載。コード例自体は変更しない。

## Risks / Trade-offs

- リスク: 極めて低。Markdown ドキュメントへの追記のみで、実行ロジックへの影響なし
- トレードオフ: なし
