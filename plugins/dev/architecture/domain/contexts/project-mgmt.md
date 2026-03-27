## Name
Project Management

## Responsibility
プロジェクト作成、移行、スナップショット、プラグイン管理

## Key Entities
- Project, Template, Manifest, ProjectBoard, Governance

## Dependencies
- なし（他の Context から参照される）

## Bare repo 正規構造

全プロジェクトで bare repo 必須。branch モード廃止。

```
project-name/
├── .bare/                 # git データ
├── main/                  # main worktree（セッション起動場所）
│   └── .git (file)        # → .bare を指す
├── worktrees/{feat,fix,docs}/
└── autopilot-plan.yaml
```

### 検証条件（セッション開始時チェック）

| # | 条件 | 失敗時の対処 |
|---|------|-------------|
| 1 | `.bare/` が存在する（`.git/` ディレクトリではない） | co-project migrate で変換 |
| 2 | `main/.git` がファイル（ディレクトリではない）で `.bare` を指す | 構造破損。手動修復が必要 |
| 3 | CWD が `main/` 配下である（worktrees/ 配下は危険） | Pilot に警告し、main/ への移動を要求 |

## Project Board = SSOT

- 全プロジェクトで一律有効。autopilot が Status=Todo をクエリして対象選択
- project-create が自動で Project V2 作成+リンク
- 二層構造: ローカル状態ファイル（即時性）+ Project Board（永続化・可視化）

### 同期ルール

- **同期タイミング**: issue-{N}.json の status が `done` に遷移した時点でローカル → Board 同期
- **同期失敗時**: WARNING ログ出力、次回セッション開始時にリトライ。Board 同期失敗は autopilot をブロックしない
- **実装の分散先**:
  - co-project: create 時の Board 自動作成
  - co-autopilot: Issue 選択時の Board クエリ、完了時の Board 更新
