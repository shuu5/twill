## MODIFIED Requirements

### Requirement: Phase 3b scope_files 依存の調査深度指示注入

co-issue の Phase 3b は specialist spawn 時のプロンプトに scope_files 数に応じた調査深度指示を含めなければならない（SHALL）。scope_files が 3 以上の場合、各ファイルは存在確認と直接参照のみとし、再帰追跡禁止の指示を注入しなければならない（SHALL）。

#### Scenario: scope_files が 3 以上の specialist spawn
- **WHEN** co-issue Phase 3b が scope_files: [A, B, C] を含む structured_issue で issue-critic を spawn する
- **THEN** spawn プロンプトに「各ファイルは存在確認と直接参照のみ。再帰追跡禁止。残りturns=3になったら出力生成を優先」という調査深度指示が含まれる

#### Scenario: scope_files が 2 以下の specialist spawn
- **WHEN** co-issue Phase 3b が scope_files: [A, B] を含む structured_issue で issue-critic を spawn する
- **THEN** spawn プロンプトに「各ファイルの呼び出し元まで追跡可」という指示が含まれる

### Requirement: Step 3c 出力なし完了の検知と WARNING 表示

co-issue の Step 3c は specialist の返却値に `status:` または `findings:` キーワードが含まれない場合を「出力なし完了」と判定しなければならない（SHALL）。出力なし完了の場合、findings テーブルに WARNING エントリを追加しなければならない（SHALL）。WARNING は Phase 4 をブロックしてはならない（SHALL NOT）。

#### Scenario: specialist が構造化出力なしで完了
- **WHEN** issue-critic の返却値に `status:` も `findings:` も含まれない
- **THEN** Step 3c の findings テーブルに「WARNING: issue-critic: 構造化出力なしで完了（調査が maxTurns に到達した可能性）」が表示され、Phase 4 は継続される

#### Scenario: specialist が正常に構造化出力を返す
- **WHEN** issue-critic の返却値に `status: ok` と `findings: [...]` が含まれる
- **THEN** Step 3c は通常通りパースし、WARNING は表示されない

### Requirement: Step 3c ガード順序の明記

co-issue の Step 3c は出力なし検知（上位ガード）と `ref-specialist-output-schema.md` のパース失敗フォールバック（下位ガード）の役割分担を明記しなければならない（SHALL）。

#### Scenario: 役割分担ドキュメント
- **WHEN** Step 3c の処理フローを参照する
- **THEN** 「出力なし検知 → パース失敗フォールバック」の順序と役割が明記されている
