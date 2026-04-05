## ADDED Requirements

### Requirement: co-autopilot に autopilot-plan calls 宣言を追加

co-autopilot の deps.yaml calls セクションに `- script: autopilot-plan` を追加しなければならない（SHALL）。SKILL.md L57 の `bash $SCRIPTS_ROOT/autopilot-plan.sh` 呼び出しと一致させる。

#### Scenario: autopilot-plan が co-autopilot の calls に含まれる
- **WHEN** deps.yaml の co-autopilot エントリを確認する
- **THEN** calls セクションに `- script: autopilot-plan` が含まれている

#### Scenario: loom orphans で autopilot-plan が Isolated でなくなる
- **WHEN** `loom orphans` を実行する
- **THEN** `script:autopilot-plan` が Isolated リストに含まれない

## MODIFIED Requirements

### Requirement: dead code スクリプトの deps.yaml エントリ整理

実際に呼び出されていないスクリプトの deps.yaml エントリを削除しなければならない（MUST）。対象は実コード確認で呼び出し元が存在しないもの。

#### Scenario: merge-gate 関連スクリプトの判定
- **WHEN** merge-gate-execute, merge-gate-init, merge-gate-issues のスクリプトについて `git log --follow` と全 .md ファイルの grep で呼び出し元を確認する
- **THEN** 呼び出し元がなければ deps.yaml エントリを削除する。スクリプトファイル自体は保持する

#### Scenario: fix-phase 関連スクリプトの判定
- **WHEN** classify-failure, codex-review, create-harness-issue のスクリプトについて呼び出し元を確認する
- **THEN** 呼び出し元がなければ deps.yaml エントリを削除する。スクリプトファイル自体は保持する

#### Scenario: switchover, branch-create, check-db-migration の判定
- **WHEN** 各スクリプトの使用状況を確認する
- **THEN** switchover はスイッチオーバー完了済みのため削除。branch-create は worktree-create 統合済みなら削除。check-db-migration は webapp 固有なら削除。いずれもスクリプトファイル自体は保持する

### Requirement: 意図的孤立コンポーネントの明示

standalone ユーティリティとして意図的に孤立しているコンポーネントは、deps.yaml 内で YAML コメント `# standalone: <理由>` を付与しなければならない（SHALL）。

#### Scenario: ユーザー直接起動コマンドにコメント付与
- **WHEN** check, propose, apply, archive, explore, self-improve-review, worktree-list の各エントリを確認する
- **THEN** `# standalone: ユーザー直接起動` コメントが付与されている

#### Scenario: プロジェクト固有コマンドにコメント付与
- **WHEN** loom-validate, services, schema-update の各エントリを確認する
- **THEN** `# standalone: プロジェクト固有ユーティリティ` コメントが付与されている

#### Scenario: 低頻度ユーティリティにコメント付与
- **WHEN** ui-capture, spec-diagnose, e2e-plan, opsx-archive の各エントリを確認する
- **THEN** `# standalone: 低頻度ユーティリティ` コメントが付与されている

### Requirement: SVG グラフの再生成

calls 修正後に SVG グラフを再生成しなければならない（MUST）。新しいエッジが正しく描画されることを確認する。

#### Scenario: autopilot-plan エッジが SVG に描画される
- **WHEN** `loom --graphviz` で DOT を生成し SVG に変換する
- **THEN** co-autopilot → autopilot-plan のエッジが描画されている

#### Scenario: loom check が PASS する
- **WHEN** `loom check` を実行する
- **THEN** すべてのチェックが PASS する

#### Scenario: loom validate が PASS する
- **WHEN** `loom validate` を実行する
- **THEN** violations が 0 件である
