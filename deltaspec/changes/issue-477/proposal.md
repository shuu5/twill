## Why

#444 で採択された「test-target real-issues モード」の ADR 本文が未作成のまま #444 がクローズされた。`plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` が存在しないため、後続の実装 Issue（Issue C/D/E/F/G）の設計前提が欠けており、co-self-improve の full chain テストを進められない。

## What Changes

- `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` を新規作成する
  - 3 選択肢（専用テストリポ / 実リポ test ラベル / mock GitHub API）の比較表と選定根拠
  - co-self-improve との統合フロー図（`--real-issues` モード）
  - クリーンアップフロー（PR close → Issue close → branch 削除、月次ローテーション）
  - リポジトリ管理の責務帰属決定（既存 `test-project-init` の `--mode real-issues` 拡張）

## Capabilities

### New Capabilities

- **ADR-016 設計文書**: test-target real-issues モードの設計決定を公式に文書化する。専用テストリポ採用の根拠・クリーンアップ設計・統合フローを含む。

### Modified Capabilities

なし。

## Impact

- `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md`（新規）
