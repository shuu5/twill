## ADDED Requirements

### Requirement: Phase 5 で soak run log を #493 に自動投稿する

CO_ISSUE_V2=1 かつ Phase 4 で 1 件以上の issue 作成が成功した場合、Phase 5 で以下のフォーマットで `gh issue comment 493` に run log を追記しなければならない（SHALL）。

```
v2 run YYYY-MM-DD_HHMMSS (session <sid>): total=<N> / done=<D> / warned=<W> / failed=<F> / circuit_broken=<C>
```

#### Scenario: 成功 run で #493 に run log が投稿される

- **WHEN** CO_ISSUE_V2=1 で 1 件以上の issue 作成が成功する
- **THEN** `gh issue comment 493 -R shuu5/twill` で上記フォーマットの 1 行が追記される

### Requirement: soak logging の失敗はユーザー session をブロックしない

`gh issue comment` が失敗した場合、warning のみ出力し、ユーザー session の成功判定を妨げてはならない（SHALL NOT）。

#### Scenario: comment 失敗時は warning のみで継続する

- **WHEN** `gh issue comment 493` コマンドが非ゼロで終了する
- **THEN** warning メッセージが出力されるが、Phase 5 は exit 0 で終了し co-issue の結果提示は正常に行われる

### Requirement: #493 が closed の場合は run log 投稿をスキップする

Phase 5 実行前に `gh issue view 493` で状態を確認し、closed の場合は run log 投稿をスキップしなければならない（SHALL）。

#### Scenario: #493 が closed なら投稿しない

- **WHEN** `gh issue view 493` が state=CLOSED を返す
- **THEN** `gh issue comment` は実行されずに Phase 5 が完了する

### Requirement: CO_ISSUE_V2=0 パスは Phase 5 を実行しない

旧パス（CO_ISSUE_V2=0）は Phase 5 を touch してはならない（MUST NOT）。

#### Scenario: flag==0 で Phase 5 が実行されない

- **WHEN** CO_ISSUE_V2=0 で co-issue を実行する
- **THEN** Phase 5 は実行されず、#493 への comment も行われない

### Requirement: co-issue-v2-smoke.test.sh を新規追加する

`tests/scenarios/co-issue-v2-smoke.test.sh` を新規作成し、CO_ISSUE_V2=1 で 2-issue 分解 → dispatch → collect → present の smoke テストを実施しなければならない（SHALL）。

#### Scenario: smoke テストが PASS する

- **WHEN** `CO_ISSUE_V2=1 bash tests/scenarios/co-issue-v2-smoke.test.sh` を実行する
- **THEN** テストが全項目 PASS して exit 0 で終了する
