## Why

旧プラグインでは autopilot の状態が6種（マーカーファイル、環境変数、tmux名、.failファイル、ブランチ名、PRラベル）に散在し、Compaction時の環境変数喪失や状態不整合が頻発していた。また `--auto`/`--auto-merge` フラグによる3パス分岐がテストの不完全性と保守コストを増大させていた。統一状態ファイルと不変条件による形式的保証で、これらの問題を構造的に解決する。

## What Changes

- `issue-{N}.json`（per-issue）と `session.json`（per-autopilot-run）の2ファイルに状態を統合
- 状態の read/write ヘルパースクリプト（`state-read.sh`, `state-write.sh`）を実装
- 6種マーカーファイル（`.auto-mode`, `.merge-pending` 等）を廃止
- `--auto`/`--auto-merge` フラグを廃止（ADR-001: 全操作が co-autopilot 経由）
- `DEV_AUTOPILOT_SESSION` 環境変数を廃止
- worktree 削除の pilot 専任ルールをスクリプトレベルで強制
- ポーリング機構を status フィールド監視に簡素化
- autopilot Phase/Issue 進捗管理に TaskCreate/TaskUpdate を活用

## Capabilities

### New Capabilities

- **統一状態ファイル管理**: `state-read.sh` / `state-write.sh` による JSON ベースの状態 read/write
- **状態遷移の形式的検証**: 定義された遷移パス（running → merge-ready → done / failed）のみを許可し、不正遷移を拒否
- **セッション排他制御**: session.json の存在チェックによる同一プロジェクト内の並行セッション検出
- **cross-issue 警告格納**: session.json にファイル重複警告を構造化保存
- **TaskCreate/TaskUpdate 進捗追跡**: Phase/Issue 単位の CLI 上リアルタイム進捗表示

### Modified Capabilities

- **ポーリング機構**: マーカーファイル監視 → issue-{N}.json の status フィールド監視に変更
- **crash 検知**: tmux ペイン存在チェック + status 更新の組み合わせに変更（不変条件G）
- **worktree ライフサイクル**: Worker は作成のみ、削除は Pilot 専任に役割分離（不変条件B）

## Impact

- **scripts/**: `state-read.sh`, `state-write.sh` を新規追加。既存の `worktree-create.sh`, `worktree-delete.sh` は変更なし
- **skills/co-autopilot/**: SKILL.md を統一状態ファイル前提に再設計（C-1 で実装する本体の基盤）
- **deps.yaml**: script 型コンポーネント2件を追加（state-read, state-write）
- **hooks.json**: Compact hooks の移行（環境変数保存 → 不要化）
- **テスト**: 状態遷移テスト仕様を定義（テスト実装自体は C-5 で実施）
