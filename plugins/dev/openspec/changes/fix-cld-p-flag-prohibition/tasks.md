## 1. 禁止事項セクション更新

- [x] 1.1 `commands/autopilot-launch.md` の禁止事項セクション末尾に `cld -p` / `cld --print` 使用禁止ルールを追加（理由: 非対話 print モードで Worker が即終了する）

## 2. Step 5 コード例への注意コメント

- [x] 2.1 Step 5 の tmux 起動コード例に `-p` / `--print` フラグ禁止のインラインコメントを追加

## 3. 検証

- [x] 3.1 変更後の `autopilot-launch.md` が Markdown として正しくレンダリングされることを確認
