## Context

ubuntu-note-system に散在する tmux セッション管理スクリプト（session-state.sh 271L, session-comm.sh 315L, cld 28L, cld-spawn 54L, cld-observe 104L, cld-fork 26L）とスキル（spawn, observe, fork）を、独立した loom 型 plugin `loom-plugin-session` として切り出す。

現在これらは `~/ubuntu-note-system/scripts/` と `~/.claude/skills/` に散在しており、loom の管轄外で追跡不能。dev plugin の autopilot がこれらに依存しているため配布不可の状態。

## Goals / Non-Goals

**Goals:**

- bare repo + main worktree 構成で `shuu5/loom-plugin-session` リポジトリを作成する
- スクリプト 7 件を `scripts/` に移植し、パス参照を plugin-relative に更新する
- スキル 3 件を `skills/` に移植し、SKILL.md 内のパス参照を `${CLAUDE_PLUGIN_ROOT}` ベースに更新する
- deps.yaml v3 に全コンポーネントを登録し、`loom check` / `loom validate` を PASS させる
- claude-session-save.sh を 7 件目のスクリプトとして含める（tmux resurrect 連携）

**Non-Goals:**

- cld-fork-cd の移植（DEPRECATED、廃止）
- cld-ch の移植（Discord plugin スコープ）
- dev plugin 側の参照切り替え（別 Issue #B）
- ユーザースコープの廃止（別 Issue #E）
- loom 本体の plugin 間依存サポート（別 Issue #D）
- claude-session-restore.sh / claude-session-postsave.sh の移植（tmux-resurrect hook 側で管理、plugin スコープ外）

## Decisions

### D1: リポジトリ構成

bare repo + worktree パターンを採用（loom-plugin-dev と同じ構成）。

```
loom-plugin-session/
├── .bare/                    # bare repository
├── main/                     # main worktree
│   ├── .git                  # → .bare を指すファイル
│   ├── deps.yaml             # v3.0 SSOT
│   ├── CLAUDE.md             # plugin 説明
│   ├── scripts/
│   │   ├── session-state.sh
│   │   ├── session-comm.sh
│   │   ├── cld
│   │   ├── cld-spawn
│   │   ├── cld-observe
│   │   ├── cld-fork
│   │   └── claude-session-save.sh
│   └── skills/
│       ├── spawn/SKILL.md
│       ├── observe/SKILL.md
│       └── fork/SKILL.md
└── worktrees/                # feature worktrees
```

### D2: deps.yaml v3 構成

```yaml
version: "3.0"
plugin: session

entry_points:
  - skills/spawn/SKILL.md
  - skills/observe/SKILL.md
  - skills/fork/SKILL.md

skills:
  spawn:
    type: atomic
    path: skills/spawn/SKILL.md
    spawnable_by: [user]
    can_spawn: []
    calls:
      - script: cld-spawn
      - script: session-state
      - script: session-comm
    description: "新規セッション spawn"

  observe:
    type: atomic
    path: skills/observe/SKILL.md
    spawnable_by: [user]
    can_spawn: []
    calls:
      - script: cld-observe
      - script: session-state
      - script: session-comm
    description: "tmux ウィンドウ観察"

  fork:
    type: atomic
    path: skills/fork/SKILL.md
    spawnable_by: [user]
    can_spawn: []
    calls:
      - script: cld-fork
      - script: session-state
      - script: session-comm
    description: "セッション fork"

scripts:
  session-state:
    type: script
    path: scripts/session-state.sh
    description: "セッション状態検出ライブラリ"

  session-comm:
    type: script
    path: scripts/session-comm.sh
    calls:
      - script: session-state
    description: "セッション間通信"

  cld:
    type: script
    path: scripts/cld
    description: "Claude Code ランチャー"

  cld-spawn:
    type: script
    path: scripts/cld-spawn
    calls:
      - script: cld
    description: "新規セッション起動"

  cld-observe:
    type: script
    path: scripts/cld-observe
    calls:
      - script: session-comm
      - script: session-state
    description: "ペイン出力キャプチャ"

  cld-fork:
    type: script
    path: scripts/cld-fork
    calls:
      - script: cld
    description: "セッション fork 起動"

  claude-session-save:
    type: script
    path: scripts/claude-session-save.sh
    description: "セッション ID ↔ tmux ペイン マッピング保存"
```

### D3: パス参照の更新方針

- スクリプト間参照: `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` パターンで自己解決
- SKILL.md 内参照: `${CLAUDE_PLUGIN_ROOT}/scripts/` プレフィックスを使用
- session-comm.sh → session-state.sh の依存: 同一ディレクトリ内相対パスで解決

### D4: cld スクリプトの plugin 化対応

cld は現在 `$HOME/.claude/plugins/*/` を走査して `--plugin-dir` を組み立てている。plugin 内に移植しても、この走査ロジックは維持する（plugin 自体が自分を発見する必要はない）。

## Risks / Trade-offs

### R1: スクリプト間依存の循環リスク

session-comm.sh → session-state.sh の一方向依存のみ。循環なし。

### R2: systemd-run 依存（cld）

cld は `systemd-run --user` でメモリ制限を適用している。Linux 固有のため macOS では動作しない。現時点では Linux のみをサポートするため許容。

### R3: tmux 必須

全スクリプトが tmux 前提。tmux なし環境では機能しない。これは既存の制約であり、plugin 化では解決しない。

### R4: plugin 間依存（将来）

dev plugin の autopilot が session 機能を利用するが、loom 本体の plugin 間依存サポート（Issue #D）が未実装のため、当面は PATH 経由での暗黙的依存となる。
