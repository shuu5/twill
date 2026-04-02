## Why

session plugin (#97) への移植完了と dev plugin の cross-plugin 参照切り替え (#98) により、ユーザースコープ (`~/.claude/skills/`) と `ubuntu-note-system/scripts/` に同一機能が重複している。重複を廃止し plugin ブロック構成に統一する。

## What Changes

- `~/.claude/skills/spawn`, `observe`, `fork`, `fork-cd` を削除
- `ubuntu-note-system/scripts/` の対象スクリプト 6 件を廃止: `cld-spawn`, `cld-observe`, `cld-fork`, `cld-fork-cd`, `session-state.sh`, `session-comm.sh`
- PATH 整理（session plugin の `scripts/` を参照するよう更新、旧パス除去）
- 他プロジェクトからの参照がないことを grep で検証

## Capabilities

### New Capabilities

なし（機能追加はない）

### Modified Capabilities

- `/spawn`, `/observe`, `/fork` は session plugin 経由で動作するよう統一（既に #98 で dev plugin 側は切り替え済み）
- `fork-cd` は `/spawn --cd --context` に統合済み（deprecated スキル削除）

## Impact

- **ファイル削除**: `~/.claude/skills/` 配下 4 ディレクトリ、`ubuntu-note-system/scripts/` 配下 6 ファイル
- **PATH 変更**: `ubuntu-note-system/` の PATH 設定から旧スクリプトパスを除去、session plugin scripts/ を追加
- **依存**: #97 (session plugin 新設) ✓ CLOSED、#98 (dev plugin 参照切り替え) ✓ CLOSED
- **影響範囲**: 全プロジェクトの `~/.claude/CLAUDE.md` でスキル参照が session plugin 経由に変わるが、スキル名自体は変わらないためユーザー影響なし
