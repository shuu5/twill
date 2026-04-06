## Why

C-2a で独立系コンポーネント48個を移植済みだが、setup chain / test-ready chain に関連する11コンポーネントのうち4個（services, ui-capture, e2e-plan, test-scaffold）が未移植。これらが欠けているため workflow-test-ready が test-scaffold を spawn できず、setup → test-ready → apply の完全なチェーンが成立しない。

## What Changes

- 4個の未移植コンポーネント（services, ui-capture, e2e-plan, test-scaffold）の COMMAND.md を新規作成し deps.yaml に登録
- workflow-test-ready の calls 定義を補完（test-scaffold, opsx-apply の呼び出し関係を明示）
- worktree-delete を script → atomic command に昇格（COMMAND.md 作成 + deps.yaml 更新）
- 全11コンポーネントの chain step / step_in 整合性を確認・修正

## Capabilities

### New Capabilities

- **services**: 開発サービス起動管理（コンテナ、Supabase、開発サーバー）の COMMAND.md
- **ui-capture**: UI スクショ撮影 + セマンティック解析の COMMAND.md
- **e2e-plan**: E2E テスト計画作成の COMMAND.md
- **test-scaffold**: テスト生成の統合コマンド（composite）の COMMAND.md
- **worktree-delete（command 版）**: script ラッパーとしての COMMAND.md

### Modified Capabilities

- **deps.yaml**: 5コンポーネント追加（services, ui-capture, e2e-plan, test-scaffold, worktree-delete command 化）
- **workflow-test-ready**: calls フィールドに test-scaffold, opsx-apply を追加

## Impact

- **deps.yaml**: commands セクションに5エントリ追加、workflow-test-ready の calls 補完
- **プロンプトファイル**: 5個の COMMAND.md 新規作成
- **既存 script**: worktree-delete.sh は残存（command が script を呼び出す形）
- **loom validate**: 全コンポーネント登録後に PASS が必要
