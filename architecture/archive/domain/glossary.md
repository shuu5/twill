## Glossary

vision.md の Constraints セクションから導出した MUST 用語。

| 用語 | 定義 | Context |
|------|------|---------|
| SSoT (Single Source of Truth) | 特定ドメインにおける唯一の情報源。twill では deps.yaml と types.yaml がそれぞれの領域の SSoT | monorepo |
| deps.yaml | プラグイン構造（スキル/コマンド/エージェント/チェーン）のメタデータを管理する唯一の情報源。v3.0 が現行形式 | monorepo, cli/twl |
| types.yaml | プラグイン型ルール（can_spawn/spawnable_by 等の制約）を管理する唯一の情報源 | monorepo, cli/twl |
| bare repo | `.bare/` ディレクトリに格納された Git ベアリポジトリ。twill の単一長期ブランチ（main）の実体 | monorepo |
| worktree | Git worktree コマンドで作成する作業ツリー。feature ブランチは `worktrees/<branch>/` として管理 | monorepo |
| 依存方向の一方向性 | plugins → cli の方向のみ許可する依存制約。cli はプラグインを知らない | monorepo |
| コンポーネント自律性 | 各コンポーネント（cli/twl, plugins/twl, plugins/session）が独立した関心事を持ち、自身の CLAUDE.md で開発ルールを定義する原則 | monorepo |
| Open Host Service | plugins/twl が cli/twl を呼び出す統合パターン。twl validate/check/chain コマンドが公開インタフェース | plugins/twl, cli/twl |
