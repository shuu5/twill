## Context

loom-plugin-dev は 25 本の bash スクリプト（scripts/）を持ち、autopilot セッション管理・merge-gate 判定・worktree 操作・状態管理など複雑なロジックを含む。既存の tests/scenarios/ には 40 本のシェルテスト（~17K 行）があるが、独自 assert 関数で書かれており、テストフレームワーク未統一。Issue #5 で定義された 9 件の Autopilot 不変条件のテストカバレッジも体系的に検証されていない。

制約:
- E2E テスト（Claude Code セッション実行）はスコープ外
- 既存 tests/scenarios/ は変更しない（共存）
- テストは sandbox（tmpdir）内で実行し、本体リポジトリに副作用を残さない

## Goals / Non-Goals

**Goals:**

- bats-core ベースの統一テストスイートを `tests/bats/` に構築
- scripts/ 25 本全てに対する単体テスト
- Autopilot 不変条件 9 件（A〜I）の明示的テスト
- merge-gate 3 段階（init → execute → issues）のロジックテスト
- chain 定義（deps.yaml chains:）と loom chain validate の整合性テスト
- deps.yaml 構造バリデーション（型ルール、参照整合性）
- `bash tests/run-tests.sh` で全件 pass

**Non-Goals:**

- 既存 tests/scenarios/ の bats 移行
- E2E テスト（実 Claude Code セッション）
- CI/CD パイプライン構築
- コードカバレッジ計測

## Decisions

### D1: bats-core を git submodule で導入

bats-core + bats-assert + bats-support を `tests/lib/` に git submodule として追加。npm/apt 依存を避け、リポジトリ clone のみでテスト実行可能にする。

### D2: ディレクトリ構成

```
tests/
├── bats/                    # 新規 bats テスト
│   ├── scripts/             # scripts/ 単体テスト（1:1 対応）
│   │   ├── state-write.bats
│   │   ├── state-read.bats
│   │   ├── crash-detect.bats
│   │   ├── ...
│   │   └── worktree-delete.bats
│   ├── invariants/          # Autopilot 不変条件テスト（A〜I）
│   │   └── autopilot-invariants.bats
│   ├── merge-gate/          # merge-gate 判定テスト
│   │   └── merge-gate-flow.bats
│   ├── structure/           # deps.yaml + chain 構造テスト
│   │   ├── deps-yaml.bats
│   │   └── chain-definition.bats
│   └── helpers/             # 共通 setup/teardown
│       └── common.bash
├── lib/                     # bats submodules
│   ├── bats-core/
│   ├── bats-assert/
│   └── bats-support/
├── scenarios/               # 既存テスト（変更なし）
└── run-tests.sh             # 統合テストランナー（刷新）
```

### D3: sandbox パターン

全スクリプトテストは `setup()` で tmpdir を作成し `teardown()` で削除。スクリプトが参照する `PROJECT_ROOT` を sandbox に差し替えて実行。必要なファイル（deps.yaml、.autopilot/ 等）は fixture として sandbox にコピー。

### D4: 不変条件テストの設計

9 件の不変条件をそれぞれ独立した `@test` ブロックで検証:

| ID | 不変条件 | テスト方法 |
|----|----------|-----------|
| A | 状態一意性 | state-write で同一 issue に並列書き込み → 排他制御確認 |
| B | Worktree 削除 pilot 専任 | worktree-delete に role=worker で実行 → 拒否確認 |
| C | Worker マージ禁止 | merge-gate-execute に role=worker → 拒否確認 |
| D | 依存先 fail skip 伝播 | autopilot-should-skip で依存先 failed → skip 確認 |
| E | merge-gate リトライ制限 | retry_count=1 の状態で retry → 拒否確認 |
| F | rebase 禁止 | merge-gate-execute のマージ戦略確認（squash のみ） |
| G | クラッシュ検知保証 | crash-detect でペイン不在 → failed 遷移確認 |
| H | deps.yaml 変更排他性 | 構造テストで排他ルール確認 |
| I | 循環依存拒否 | autopilot-plan で循環グラフ → エラー確認 |

### D5: run-tests.sh の刷新

bats テストと既存 scenarios テストの両方を実行。bats テストは `tests/lib/bats-core/bin/bats` で実行し、scenarios テストは既存の `bash` 実行を維持。終了コードは両方の OR。

## Risks / Trade-offs

- **Risk: 一部スクリプトが gh/tmux 等の外部コマンドに依存** → 外部コマンド呼び出し部分は stub 関数で置換。テスト対象はロジック部分のみ。
- **Risk: git submodule の管理コスト** → bats は安定しており更新頻度低。初期設定のみで長期運用可能。
- **Trade-off: 既存 scenarios を移行しない** → 二重管理のコストはあるが、40 ファイル移行のリスクを回避。新規テストは全て bats で統一。
