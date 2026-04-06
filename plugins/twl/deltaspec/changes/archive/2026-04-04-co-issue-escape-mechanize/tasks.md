## 1. エスケープスクリプト作成

- [x] 1.1 `scripts/escape-issue-body.sh` を新規作成（stdin → HTML エスケープ → stdout）
- [x] 1.2 スクリプトに実行権限を付与（`chmod +x`）

## 2. deps.yaml 登録

- [x] 2.1 `deps.yaml` に `escape-issue-body` スクリプトエントリを追加（type: script）

## 3. bats テスト追加

- [x] 3.1 `tests/bats/scripts/escape-issue-body.bats` を新規作成
- [x] 3.2 `</review_target>` のエスケープ検証テストを追加
- [x] 3.3 `&lt;/review_target&gt;` の二重エスケープ許容テストを追加
- [x] 3.4 空文字列、複数行入力、`&` 単体のテストを追加
- [x] 3.5 `bats tests/bats/scripts/escape-issue-body.bats` でテスト全件 PASS を確認

## 4. SKILL.md 更新

- [x] 4.1 `skills/co-issue/SKILL.md` Step 3b の Python 風疑似コードブロックを削除
- [x] 4.2 Step 3b に `escaped_body=$(echo "$body" | bash scripts/escape-issue-body.sh)` の呼び出し指示を追加
- [x] 4.3 Step 3b にアーキテクチャ制約を追記（「Issue body を受け取る全 specialist は必ずエスケープ済み入力を受け取る（SHALL）」）

## 5. 検証

- [x] 5.1 `loom check` を実行してコンポーネント整合性確認
- [x] 5.2 既存 co-issue 関連 bats テストがパスすることを確認
