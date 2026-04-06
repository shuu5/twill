## MODIFIED Requirements

### Requirement: entry_points リストの自動更新

`rename_component()` は、`deps.yaml` の `entry_points` リスト内で old_name を含むパスを new_name に置換しなければならない（SHALL）。置換はパスコンポーネント境界でのみ行い、部分文字列への波及を防がなければならない（MUST）。

#### Scenario: entry_points 内のパス更新
- **WHEN** `twl rename controller-project co-project` を実行し、entry_points に `skills/controller-project/SKILL.md` が含まれる
- **THEN** entry_points の該当エントリが `skills/co-project/SKILL.md` に更新される

#### Scenario: entry_points が未定義
- **WHEN** `twl rename some-cmd new-cmd` を実行し、deps.yaml に entry_points キーが存在しない
- **THEN** エラーなく正常に完了する（entry_points 更新はスキップされる）

#### Scenario: dry-run での entry_points 変更表示
- **WHEN** `twl rename controller-project co-project --dry-run` を実行し、entry_points に該当パスが含まれる
- **THEN** entry_points の変更が `entry_points: skills/controller-project/SKILL.md → skills/co-project/SKILL.md` 形式でプレビュー表示される
