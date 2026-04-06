## 1. リポジトリ作成

- [ ] 1.1 `gh repo create shuu5/loom-plugin-session --public` でリポジトリ作成
- [ ] 1.2 bare repo 構成でクローン（`.bare/` + `main/` worktree）
- [ ] 1.3 CLAUDE.md 作成（bare repo ルール、編集フロー、loom CLI 必須）
- [ ] 1.4 `.gitignore` 作成

## 2. deps.yaml 構築

- [ ] 2.1 deps.yaml v3 スケルトン作成（plugin メタデータ）
- [ ] 2.2 scripts 6 件を deps.yaml に登録（session-state.sh, session-comm.sh, cld, cld-spawn, cld-observe, cld-fork）
- [ ] 2.3 skills 3 件を deps.yaml に登録（spawn, observe, fork）

## 3. スクリプト移植

- [ ] 3.1 `scripts/` ディレクトリ作成
- [ ] 3.2 session-state.sh 移植（271L）+ パス参照 plugin-relative 化
- [ ] 3.3 session-comm.sh 移植（315L）+ パス参照 plugin-relative 化
- [ ] 3.4 cld 移植（28L）+ パス参照 plugin-relative 化
- [ ] 3.5 cld-spawn 移植（54L）+ パス参照 plugin-relative 化
- [ ] 3.6 cld-observe 移植（104L）+ パス参照 plugin-relative 化
- [ ] 3.7 cld-fork 移植（26L）+ パス参照 plugin-relative 化
- [ ] 3.8 全スクリプトに実行権限付与（chmod +x）

## 4. スキル移植

- [ ] 4.1 `skills/spawn/SKILL.md` 移植 + パス参照 plugin-relative 化
- [ ] 4.2 `skills/observe/SKILL.md` 移植 + パス参照 plugin-relative 化
- [ ] 4.3 `skills/fork/SKILL.md` 移植 + パス参照 plugin-relative 化

## 5. 検証

- [ ] 5.1 全スクリプトで `~/ubuntu-note-system` `~/.claude/skills/` の grep → 0 件確認
- [ ] 5.2 `loom check` → Missing 0 / Extra 0
- [ ] 5.3 `loom validate` → Violations 0
- [ ] 5.4 session-state.sh query/wait/list スモークテスト（tmux 環境）
- [ ] 5.5 cld-spawn スモークテスト（tmux 環境）

## 6. Project Board

- [ ] 6.1 loom-plugin-dev Project Board (#3) にリポジトリを追加
