## 1. wave-collect コマンド作成

- [ ] 1.1 `plugins/twl/commands/wave-collect.md` を新規作成（frontmatter: type: atomic）
- [ ] 1.2 Wave 番号引数の受け取りロジックを記述
- [ ] 1.3 `.autopilot/plan.yaml` から対象 Phase の Issue リストを取得するロジックを記述
- [ ] 1.4 各 Issue の `.autopilot/issues/issue-{N}.json` を読み込んで status/pr/retry_count を取得するロジックを記述
- [ ] 1.5 統計計算（total/done/failed/介入率/平均介入回数）ロジックを記述
- [ ] 1.6 `.supervisor/wave-{N}-summary.md` への構造化 Markdown 出力ロジックを記述（出力先ディレクトリ自動作成含む）

## 2. deps.yaml 更新

- [ ] 2.1 `plugins/twl/deps.yaml` に `wave-collect` エントリを追加（type: atomic, path: commands/wave-collect.md）
- [ ] 2.2 `twl check` で deps.yaml が valid であることを確認

## 3. 検証

- [ ] 3.1 `twl validate` でコマンドファイルの構造検証
- [ ] 3.2 `twl update-readme` で README 更新
