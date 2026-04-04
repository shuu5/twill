## Context

loom-plugin-dev は B-2（bare repo + deps.yaml v3.0）完了後の状態を前提とする。現在 co-autopilot の SKILL.md はスタブ（「C-1 以降で実装」）であり、autopilot の実行基盤が存在しない。B-3 では co-autopilot 本体（C-1）が依存する状態管理基盤を先に構築する。

### 現在のファイル構造

- `scripts/hooks/` に PostToolUse hook 2件（B-7 で追加済み）
- `scripts/worktree-create.sh` が worktree 作成を担当（B-2 で追加予定）
- autopilot 用の状態管理スクリプトは未実装

### 制約

- 状態ファイルの格納場所は worktree ではなく `main/` 配下（Pilot が読み取るため）
- bash スクリプトのみで実装（jq 依存は許可）
- Pilot/Worker 間のアクセス方向: Pilot = read only, Worker = write（issue-{N}.json）
- session.json は Pilot のみが read/write

## Goals / Non-Goals

**Goals:**

- `state-read.sh` / `state-write.sh` を script 型コンポーネントとして実装し、deps.yaml に登録する
- issue-{N}.json の状態遷移を検証し、不正遷移を拒否するバリデーションロジックを実装する
- session.json によるセッション排他制御を実装する
- worktree 削除の pilot 専任ルールを worktree-delete.sh のガード条件として実装する
- ポーリング機構を issue-{N}.json の status フィールド監視に簡素化する
- 9件の不変条件をテスト仕様として明文化する（テスト実装は C-5）

**Non-Goals:**

- co-autopilot SKILL.md 本体の実装（C-1 スコープ）
- merge-gate ロジックの実装（B-5 スコープ）
- 既存 scripts の移植（C-4 スコープ）
- chain 定義の実装（B-4 スコープ）
- plan.yaml 生成ロジック（C-1 スコープ）

## Decisions

### D1: 状態ファイル格納場所 = `.autopilot/` ディレクトリ

`main/.autopilot/` ディレクトリに格納する。

```
main/.autopilot/
  session.json        # per-autopilot-run
  issues/
    issue-42.json     # per-issue
    issue-43.json
```

**理由**: Pilot（main/）から直接アクセス可能。worktree 内には配置しない（Worker が削除できないため Pilot の管轄）。`.gitignore` に追加して git 管理外とする。

### D2: state-write.sh の遷移バリデーション

state-write.sh は status フィールドの更新時に遷移表を検証する。

```bash
# 許可される遷移
VALID_TRANSITIONS=(
  "running:merge-ready"
  "running:failed"
  "merge-ready:done"
  "merge-ready:failed"
  "failed:running"   # retry (retry_count < 1)
)
```

不正遷移時は exit 1 で拒否。`failed → running` は `retry_count` が 1 未満の場合のみ許可。

**理由**: 不変条件 A（状態の一意性）を機械的に保証。LLM 判断に依存しない。

### D3: Pilot/Worker アクセス方向の強制

state-write.sh に `--role` フラグを追加。

- `--role pilot`: session.json のみ書き込み可。issue-{N}.json は読み取り専用
- `--role worker`: issue-{N}.json のみ書き込み可。session.json は読み取り専用

**理由**: 不変条件 C（Worker マージ禁止）を含む Pilot/Worker 責務分離を script レベルで強制。

### D4: ポーリングは state-read.sh のラッパー

旧プラグインのマーカーファイル監視を廃止し、`state-read.sh --field status` の繰り返し呼び出しに簡素化。

ポーリング間隔: 10秒（旧プラグインと同一）。タイムアウト: 環境変数 `AUTOPILOT_POLL_TIMEOUT` で設定可能（デフォルト: なし）。

### D5: crash 検知 = tmux ペイン不在 + status 未更新

Worker の crash を検知するために:
1. tmux ペインの存在チェック（`tmux list-panes -t <window>`）
2. status が `running` のまま tmux ペインが消失 → `failed` に遷移

**理由**: 不変条件 G（クラッシュ検知保証）を tmux レベルで実装。

### D6: TaskCreate/TaskUpdate の使用箇所

| タイミング | 操作 | 内容 |
|---|---|---|
| Phase 開始 | TaskCreate | `Phase {N}: Issue #{a}, #{b}, #{c}` |
| Issue 完了 | TaskUpdate | status = completed |
| Phase 失敗 | TaskUpdate | status に失敗情報を追記 |

specialist 内部や atomic コマンド内部では不使用（短命タスクのオーバーヘッド回避）。

## Risks / Trade-offs

### R1: jq 依存

state-read.sh / state-write.sh は jq に依存する。jq が未インストールの環境では動作しない。

**軽減策**: scripts 実行前に `command -v jq` で存在チェック。未インストール時はエラーメッセージで案内。

### R2: ファイルシステム競合

Pilot と Worker が同時に issue-{N}.json にアクセスした場合の競合リスク。

**軽減策**: D3 の role ベースアクセス制御で write 方向を一方向に限定。Pilot は read only のため write-write 競合は発生しない。

### R3: session.json の残留

autopilot セッションが crash した場合、session.json が残留し次回起動をブロックする可能性。

**軽減策**: session.json に `started_at` を記録。24時間以上経過した session.json は stale として警告し、ユーザー確認の上で削除を許可。
