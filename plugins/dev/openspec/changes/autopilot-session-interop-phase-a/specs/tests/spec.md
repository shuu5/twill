## MODIFIED Requirements

### Requirement: crash-detect テスト更新

tests/bats/scripts/crash-detect.bats の既存 8 テストケースを新インターフェース（session-state.sh 統合）に対応させなければならない（SHALL）。session-state.sh の stub と tmux list-panes フォールバックの両パスをテストしなければならない（MUST）。

#### Scenario: session-state.sh 利用時の exited 検知テスト
- **WHEN** session-state.sh が存在し、`state` コマンドが `exited` を返すよう stub 設定
- **THEN** crash-detect.sh は exit code 2 を返し、issue JSON の status が `failed`、failure.detected_state が `exited` になる

#### Scenario: session-state.sh 利用時の error 検知テスト
- **WHEN** session-state.sh が存在し、`state` コマンドが `error` を返すよう stub 設定
- **THEN** crash-detect.sh は exit code 2 を返し、failure.detected_state が `error` になる

#### Scenario: session-state.sh 利用時の processing 正常テスト
- **WHEN** session-state.sh が存在し、`state` コマンドが `processing` を返すよう stub 設定
- **THEN** crash-detect.sh は exit code 0 を返す

#### Scenario: session-state.sh 非存在時のフォールバックテスト
- **WHEN** SESSION_STATE_CMD が存在しないパスを指す
- **THEN** tmux list-panes フォールバックで従来通りの動作をする（ペイン消失→exit 2、ペイン存在→exit 0）

#### Scenario: 既存テストの互換性維持
- **WHEN** 非 running 状態（done/failed/merge-ready）の Issue に対して crash-detect.sh を実行
- **THEN** 従来通り exit code 0 で正常終了する

#### Scenario: 引数バリデーションテストの維持
- **WHEN** --issue または --window が欠落した状態で crash-detect.sh を実行
- **THEN** 従来通り exit code 1 でエラー終了する
