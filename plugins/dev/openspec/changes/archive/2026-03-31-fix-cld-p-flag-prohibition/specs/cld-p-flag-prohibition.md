## ADDED Requirements

### Requirement: cld -p / --print フラグ使用禁止の明記

`autopilot-launch.md` の禁止事項セクションに `cld -p` / `cld --print` の使用禁止を明記しなければならない（SHALL）。Pilot Claude が Worker 起動コマンド構築時にこれらのフラグを使用することを防止する。

#### Scenario: 禁止事項セクションに cld -p 禁止が記載されている
- **WHEN** `commands/autopilot-launch.md` の禁止事項セクションを確認する
- **THEN** `cld -p` / `cld --print` の使用禁止が記載されていること
- **THEN** 禁止理由として「非対話 print モードで起動し Worker が即終了する」旨が記載されていること

#### Scenario: Pilot Claude が Worker 起動コマンドを構築する
- **WHEN** Pilot Claude が `autopilot-launch.md` に従い Worker 起動コマンドを構築する
- **THEN** 禁止事項により `-p` / `--print` フラグの使用が排除されること

### Requirement: Step 5 コード例への注意コメント追加

Step 5 の tmux 起動コード例に、`-p` / `--print` フラグを使わない旨のインラインコメントを追加しなければならない（MUST）。

#### Scenario: Step 5 のコード例にコメントが存在する
- **WHEN** `commands/autopilot-launch.md` の Step 5 コード例を確認する
- **THEN** positional arg でプロンプトを渡す方式であることを示すコメントが存在すること
- **THEN** `-p` / `--print` を使用してはならない旨のコメントが存在すること
