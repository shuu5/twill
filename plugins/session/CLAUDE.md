# plugin-session

tmux セッション管理 plugin。Claude Code の tmux ウィンドウ操作（spawn/observe/fork）と状態検出を提供する。TWiLL モノリポ `plugins/session/` として管理。

## 構成

- モノリポ: `~/projects/local-projects/twill/main/plugins/session/`

## tmux Window 命名規則

### フォーマット

```
<prefix>-<repo>-<branch>[-i<issue>]-<h8>
```

| フィールド | 内容 |
|-----------|------|
| `prefix` | `wt`（spawn）/ `fk`（fork）/ `ap`（autopilot） |
| `repo` | リポジトリ名（slug化、最大16文字） |
| `branch` | ブランチ名（slug化、最大24文字）|
| `-i<issue>` | ブランチ末尾の Issue 番号（厳格抽出時のみ）|
| `h8` | sha256の先頭8文字（`worktree_path\|cwd\|prefix` のハッシュ）|
| 全体最大長 | 50文字（超過時は `branch` を truncate、hash は末尾固定）|

### Slug 仕様

- 英数字・ハイフンのみ許容（`LC_ALL=C tr -c '[:alnum:]-' '-'`）
- 連続ハイフンは1文字に圧縮
- 先頭・末尾のハイフンを除去
- 空文字の場合は `x` にフォールバック
- 日本語等の非ASCII文字はハイフン→slug化

### Issue 番号抽出（厳格パターン）

ブランチ名（slug化後）の末尾が `-<NNN>` または `_<NNN>` の場合のみ Issue 番号を抽出する。

```
fix/issue-291  → slug → fix-issue-291 → i291 抽出 ✓
feature/v2     → slug → feature-v2    → 抽出なし  ✓（v2 は数字のみでない）
feat/170-desc  → slug → feat-170-desc → 抽出なし  ✓（170 が末尾でない）
```

### 共通ヘルパー

`scripts/session-name.sh` を source して使う:

```bash
source "$(dirname "$0")/session-name.sh"
WINDOW_NAME=$(generate_window_name wt "$CWD" "$CWD")
```

### 同一 Worktree の再利用

`cld-spawn` は `find_existing_window` で既存 window を確認し、同一 canonical_context（`worktree_path|cwd|prefix`）の window が存在する場合は `select-window` で再利用する（`--force-new` で新規作成を強制可能）。

### TOCTOU 対策

`cld-spawn` は `flock` により `~/.local/state/twl/window-create.lock` を排他ロックして new-window を実行し、並列 spawn での重複作成を防止する。

## Window Manifest（Phase 2 — 後追い）

window-manifest 書き出し（producer 責務）は #290 として追跡する。Phase 1（命名統一）の完了後に別 Issue で実装予定。

## 編集フロー（必須）

```
コンポーネント編集 → deps.yaml 更新 → twl check → twl update-readme
```

## 視覚化

`twl` CLI 必須（独自スクリプト禁止）。
