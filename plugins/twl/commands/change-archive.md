---
type: atomic
tools: [AskUserQuestion, Bash, Read, Skill]
effort: low
maxTurns: 10
---
# DeltaSpec アーカイブ（change-archive）

完了済み change を archive/ に移動し、delta specs を main specs に統合する。

## 引数

- `change-id`: DeltaSpec change ID（省略時は自動検出）

## フロー制御（MUST）

### Step 1: change-id 解決

change 名が指定されていない場合、選択を促す。
`twl spec list` で利用可能な change を取得する。**AskUserQuestion tool** でユーザーに選択させる。
アクティブな change のみ表示する（アーカイブ済みは除外）。

**重要**: change を推測または自動選択してはならない。必ずユーザーに選ばせる。

### Step 2: artifact 完了確認

`twl spec status --change "<name>" --json` で artifact の完了状態を確認する。

JSON をパースして以下を把握:
- `schemaName`: 使用中のワークフロー
- `artifacts`: 各 artifact とそのステータス（`done` またはそれ以外）

**`done` でない artifact がある場合:**
- 未完了の artifact を一覧表示して警告する
- **AskUserQuestion tool** で続行の確認を取る
- ユーザーが確認したら続行

### Step 3: タスク完了確認

タスクファイル（通常 `tasks.md`）を読み込み、未完了タスクを確認する。
`- [ ]`（未完了）と `- [x]`（完了）の数を集計する。

**未完了タスクがある場合:**
- 未完了タスク数を表示して警告する
- **AskUserQuestion tool** で続行の確認を取る
- ユーザーが確認したら続行

**タスクファイルが存在しない場合:** タスク関連の警告なしで続行。

### Step 4: delta spec sync 判定

`deltaspec/changes/<name>/specs/` に delta spec があるか確認する。存在しない場合は sync プロンプトなしで続行。

**delta spec が存在する場合:**
- 各 delta spec を `deltaspec/specs/<capability>/spec.md` の対応する main spec と比較する
- 適用される変更内容を判定する（追加、変更、削除、リネーム）
- プロンプト前に統合サマリーを表示する

**プロンプトの選択肢:**
- 変更が必要な場合: 「今すぐ sync（推奨）」、「sync せずにアーカイブ」
- 既に sync 済みの場合: 「アーカイブ実行」、「再度 sync」、「キャンセル」

ユーザーが sync を選択した場合、delta spec を main spec に手動で適用する（delta を読み込み、main spec にマージ）。

### Step 5: CLI でアーカイブ実行

```bash
twl spec archive "<change-id>" --yes --skip-specs
```

### Step 6: チェックポイント出力

```
>>> アーカイブ完了: <change-id>

次のステップ:
  /twl:worktree-delete で開発ブランチをクリーンアップ
```

## 禁止事項（MUST NOT）

- worktree-delete を自動実行してはならない（ユーザー確認が必要）
- 警告でアーカイブをブロックしない — 情報提示と確認のみ
- アーカイブ移動時に .deltaspec.yaml を保持する（ディレクトリごと移動される）
