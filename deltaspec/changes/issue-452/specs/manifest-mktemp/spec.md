## MODIFIED Requirements

### Requirement: issue-spec-review manifest ファイルを mktemp で作成する

`issue-spec-review.md` の CONTEXT_ID 生成を `date +%s%N | tail -c8` から `mktemp` ベースに変更しなければならない（SHALL）。生成ファイルには `chmod 600` を適用しなければならない（MUST）。

#### Scenario: manifest ファイル生成
- **WHEN** `issue-spec-review.md` の Step 4 を実行する
- **THEN** `mktemp /tmp/.specialist-manifest-XXXXXXXX.txt` でファイルが作成され、パーミッションが 600 に設定され、`MANIFEST_FILE` にそのパスが格納される

#### Scenario: CONTEXT_ID 導出
- **WHEN** MANIFEST_FILE が `/tmp/.specialist-manifest-AbCd1234.txt` の場合
- **THEN** `CONTEXT_ID` は `AbCd1234` として導出される（basename からプレフィックス除去）

### Requirement: クリーンアップを MANIFEST_FILE パスで実行する

クリーンアップロジックは `MANIFEST_FILE` 変数を使って manifest を直接削除しなければならない（SHALL）。spawned ファイルも `CONTEXT_ID` ベースで削除しなければならない（MUST）。

#### Scenario: 正常クリーンアップ（CONTEXT_ID あり）
- **WHEN** Step 5 完了時に `MANIFEST_FILE` と `CONTEXT_ID` が設定されている
- **THEN** `$MANIFEST_FILE` と `/tmp/.specialist-spawned-${CONTEXT_ID}.txt` が削除される

#### Scenario: フォールバッククリーンアップ（MANIFEST_FILE 未設定）
- **WHEN** `MANIFEST_FILE` が未設定の場合
- **THEN** glob パターン `/tmp/.specialist-manifest-*.txt` と `/tmp/.specialist-spawned-*.txt` で一括削除する

## ADDED Requirements

### Requirement: hook との命名規則互換性を維持する

`check-specialist-completeness.sh` が `/tmp/.specialist-manifest-*.txt` の glob で manifest を検出できるよう、ファイル名にドット付きプレフィックス `.specialist-manifest-` を維持しなければならない（SHALL）。

#### Scenario: hook による manifest 検出
- **WHEN** `issue-spec-review` が manifest ファイルを作成した後、Agent tool を呼び出す
- **THEN** hook が `/tmp/.specialist-manifest-*.txt` glob でファイルを検出し、CONTEXT を正常に抽出できる

#### Scenario: CONTEXT 文字列検証通過
- **WHEN** mktemp のランダムサフィックス（英数字 8 文字）を CONTEXT として使用する
- **THEN** hook の `[a-zA-Z0-9_-]+` 検証をパスする

### Requirement: 並列起動時の衝突が発生しないこと

同一秒内に複数の `issue-spec-review` が並列起動された場合でも CONTEXT_ID が衝突してはならない（SHALL）。

#### Scenario: 同一秒内 3 回並列起動
- **WHEN** 3 つの issue-spec-review プロセスが同時に manifest 生成を実行する
- **THEN** 各プロセスが異なる MANIFEST_FILE パスを持ち、互いのファイルを上書きしない
