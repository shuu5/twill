## Context

session plugin (#97) が `loom-plugin-session` リポジトリに構築され、spawn/observe/fork スキルが移植済み。dev plugin は #98 で cross-plugin 参照（`session:session-state`）に切り替え済み。

ユーザースコープに残っている旧スキル・スクリプトを削除し、session plugin の scripts/ を PATH に追加することで統一する。

対象ファイルの所在:
- `~/.claude/skills/spawn`, `observe`, `fork`, `fork-cd` → symlink で `~/ubuntu-note-system/claude/skills/` を参照
- `~/ubuntu-note-system/scripts/` 配下の 6 スクリプト

## Goals / Non-Goals

**Goals:**

- ユーザースコープのスキル 4 件を削除
- `ubuntu-note-system/scripts/` の対象スクリプト 6 件を削除
- PATH から旧パスを除去し、session plugin scripts/ を追加
- 削除後に参照エラーが発生しないことを検証

**Non-Goals:**

- cld-ch（Discord plugin スコープ、別 Issue）
- session plugin 自体の修正
- dev plugin の deps.yaml 修正（#98 で完了済み）

## Decisions

1. **削除順序**: スキル削除 → スクリプト削除 → PATH 更新の順。スキル削除時点で旧パスへの参照が切れるため、先にスキルを削除する
2. **PATH 管理**: `ubuntu-note-system` の PATH 設定ファイル（`path.conf` or シェル設定）から旧エントリを除去し、`~/.claude/plugins/session/scripts/` を追加（未追加の場合のみ）
3. **検証方法**: `grep -r` で全プロジェクト・設定から旧パス参照を検索し、残存がないことを確認
4. **ubuntu-note-system への反映**: `ubuntu-note-system` リポジトリで削除 → commit → `./scripts/deploy.sh --all` で symlink 更新

## Risks / Trade-offs

- **リスク**: 他プロジェクトの CLAUDE.md で旧スキル名をハードコードしている場合に参照エラー → grep 検証で事前検出
- **リスク**: PATH 変更で session plugin のスクリプトが見つからない場合 → `which` コマンドで動作確認
- **トレードオフ**: fork-cd は deprecated 済みだが、移行期間なしで即削除する → `/spawn --cd --context` への案内は SKILL.md に記載済み
