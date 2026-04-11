## Context

`test-project-init --mode real-issues` (Issue #479, PR #515) の実装によって、専用テストリポへの紐付けが `.test-target/config.json` の `repo` フィールドに保存される設計になった。`test-project-scenario-load` は現状 `--local-only` モードのみ実装されており、co-autopilot の full chain テストに必要な実 GitHub Issue 起票フローが欠けている。

制約:
- `test-project-init --mode real-issues` を事前に実行し、`.test-target/config.json` に `mode: real-issues` と `repo` が設定されていること
- `test-project-scenario-load --real-issues` は `config.json` の `repo` フィールドを読み取り、`gh issue create` に使用する
- `--local-only`（未指定含む）時の動作は変更しない（後退互換保証）

## Goals / Non-Goals

**Goals:**
- `--real-issues` フラグ追加（`.test-target/config.json` の `repo` に `gh issue create` で起票）
- 起票 Issue 番号と scenario ID のマッピングを `.test-target/loaded-issues.json` に記録
- 二重起票ガード（`loaded-issues.json` 既存時は skip、`--force` で強制再起票）
- `--local-only`（未指定）時の後退互換保証

**Non-Goals:**
- 専用テストリポの作成（Issue #479 で実装済み）
- 起票後のクリーンアップ（Issue #482 で実装済み）
- Project Board への追加（ADR-016 のスコープ外、手動操作）

## Decisions

**D1: `config.json` から repo を読む**
`test-project-scenario-load --real-issues` は `--repo` を引数に取らず、`.test-target/config.json` の `repo` フィールドを参照する。理由: `test-project-init` が SSOT として repo 情報を管理しており、散在を防ぐ。

**D2: `loaded-issues.json` のスキーマ**
```json
{
  "scenario": "smoke-001",
  "repo": "shuu5/twill-test-202604",
  "loaded_at": "2026-04-12T00:00:00Z",
  "issues": [
    {"id": "TEST-001", "number": 42, "url": "https://github.com/shuu5/twill-test-202604/issues/42"}
  ]
}
```

**D3: 二重起票ガード**
`loaded-issues.json` が存在し、かつ `scenario` フィールドが一致する場合は skip（警告表示）。`--force` フラグで強制再起票（先に `gh issue close` してから再作成）。

**D4: commit**
`--real-issues` 時も `loaded-issues.json` を commit する（`git commit -m "chore(test): load real-issues <scenario>"`）。

## Risks / Trade-offs

- **GitHub API レートリミット**: 多 Issue シナリオ（10件超）では連続 `gh issue create` が制限される可能性。現在のカタログは最大2件のため当面問題なし。
- **ネットワーク依存**: `gh issue create` はインターネット接続を必要とする。オフライン環境では使用不可。
- **config.json 未設定時の失敗**: `--mode local` で init された場合に `--real-issues` を実行するとエラー。ユーザーへの明確なエラーメッセージで対処する。
