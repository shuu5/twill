## 1. ユーザースコープスキル削除

- [ ] 1.1 `~/.claude/skills/spawn/` ディレクトリを削除（ubuntu-note-system/claude/skills/spawn/）
- [ ] 1.2 `~/.claude/skills/observe/` ディレクトリを削除（ubuntu-note-system/claude/skills/observe/）
- [ ] 1.3 `~/.claude/skills/fork/` ディレクトリを削除（ubuntu-note-system/claude/skills/fork/）
- [ ] 1.4 `~/.claude/skills/fork-cd/` ディレクトリを削除（ubuntu-note-system/claude/skills/fork-cd/）

## 2. ubuntu-note-system スクリプト削除

- [ ] 2.1 `scripts/cld-spawn` を削除
- [ ] 2.2 `scripts/cld-observe` を削除
- [ ] 2.3 `scripts/cld-fork` を削除
- [ ] 2.4 `scripts/cld-fork-cd` を削除
- [ ] 2.5 `scripts/session-state.sh` を削除
- [ ] 2.6 `scripts/session-comm.sh` を削除

## 3. PATH 設定更新

- [ ] 3.1 PATH 設定ファイルから旧スクリプトパスを確認・除去
- [ ] 3.2 session plugin の scripts/ が PATH に含まれているか確認、未追加なら追加

## 4. 反映・検証

- [ ] 4.1 ubuntu-note-system で変更をコミット・push
- [ ] 4.2 `./scripts/deploy.sh --all` で symlink 更新を反映
- [ ] 4.3 `grep -r` で旧パス参照（cld-spawn, cld-observe, cld-fork, cld-fork-cd, session-state.sh, session-comm.sh）が残っていないことを検証
- [ ] 4.4 `/spawn`, `/observe`, `/fork` が session plugin 経由で解決されることを確認
