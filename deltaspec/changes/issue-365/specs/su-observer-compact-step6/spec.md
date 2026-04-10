## MODIFIED Requirements

### Requirement: su-observer Step 6 compact モード詳細化

Step 6 は su-compact コマンドへの委譲フロー・SU-5/SU-6 制約・呼出シグネチャを明記した詳細内容に更新しなければならない（SHALL）。
プレースホルダー NOTE は削除されなければならない（SHALL）。

#### Scenario: compact モードへの委譲
- **WHEN** ユーザーが `compact` / 外部化 / 記憶固定 / 整理 を指示する
- **THEN** Step 6 の記述に従い `Skill(twl:su-compact)` が呼び出される

#### Scenario: wave オプション付き compact
- **WHEN** ユーザーが `compact --wave` を指示する
- **THEN** su-compact が `--wave` モード（Wave 完了サマリ外部化 + compaction）で実行される

#### Scenario: task オプション付き compact
- **WHEN** ユーザーが `compact --task` を指示する
- **THEN** su-compact が `--task` モード（タスク状態保存 + compaction）で実行される

#### Scenario: full オプション付き compact
- **WHEN** ユーザーが `compact --full` を指示する
- **THEN** su-compact が `--full` モード（全知識外部化 + compaction）で実行される

### Requirement: SU-5 制約の記述（context 50% 閾値自動監視）

su-observer SKILL.md は context 消費量が 50% に到達した場合に自動的に Step 6 を提案することを記述しなければならない（SHALL）。

#### Scenario: context 50% 到達時
- **WHEN** context 消費量が 50% に到達する
- **THEN** su-observer は自動的に Step 6（compact モード）を提案する（SU-5 制約）

### Requirement: SU-6 制約の記述（Wave 完了時 compaction）

su-observer SKILL.md は Wave 完了時に su-compact を実行することを記述しなければならない（SHALL）。

#### Scenario: Wave 完了時の自動 compaction
- **WHEN** Wave が完了する（co-autopilot の全 Issue が Done になる）
- **THEN** su-observer は結果収集後に su-compact（Step 6）を実行する（SU-6 制約）

## ADDED Requirements

### Requirement: 禁止事項への SU-5/SU-6 制約追加

SKILL.md の禁止事項（MUST NOT）セクションに SU-5・SU-6 関連の禁止事項を追記しなければならない（SHALL）。

#### Scenario: context 50% 無視の禁止
- **WHEN** context 消費量が 50% を超過している
- **THEN** compact モードへの誘導なしに処理を継続してはならない（SU-5 制約）

#### Scenario: Wave 完了後 compact 省略の禁止
- **WHEN** Wave が完了した直後
- **THEN** su-compact を実行せずに次 Wave を開始してはならない（SU-6 制約）
