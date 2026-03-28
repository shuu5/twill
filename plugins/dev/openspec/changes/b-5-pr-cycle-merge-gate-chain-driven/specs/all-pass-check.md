## MODIFIED Requirements

### Requirement: all-pass-check autopilot-first 簡素化

all-pass-check を autopilot-first 前提で簡素化しなければならない（SHALL）。--auto-merge 分岐と DEV_AUTOPILOT_SESSION チェックを廃止し、統一状態ファイルで状態を管理する。

#### Scenario: 全ステップ PASS
- **WHEN** pr-cycle の全ステップ（verify, review, test, visual）が PASS
- **THEN** issue-{N}.json の status を `merge-ready` に遷移する（state-write.sh 経由）（SHALL）
- **AND** Pilot が merge-gate を実行する

#### Scenario: いずれかのステップ FAIL
- **WHEN** pr-cycle のいずれかのステップが FAIL
- **THEN** issue-{N}.json の status を `failed` に遷移する（MUST）
- **AND** 失敗ステップと理由が issue-{N}.json の結果フィールドに記録される

## REMOVED Requirements

### Requirement: --auto-merge 分岐コード廃止

--auto-merge フラグに関連する全てのコードを廃止する（SHALL）。

#### Scenario: --auto-merge コードの不在
- **WHEN** all-pass-check / auto-merge の実装を検査する
- **THEN** `--auto-merge` フラグの解析、`AUTO_MERGE` 変数、`.merge-ready` マーカーファイルの読み書き、`DEV_AUTOPILOT_SESSION` チェックが存在しない

### Requirement: マーカーファイル廃止

.done / .fail / .merge-ready 等の状態マーカーファイルを廃止する（SHALL）。状態管理は統一状態ファイル（issue-{N}.json）に一元化する。

#### Scenario: マーカーファイルの不在
- **WHEN** pr-cycle / merge-gate の実装を検査する
- **THEN** `.done`, `.fail`, `.merge-ready` 等のマーカーファイルの作成・読み取りコードが存在しない
- **AND** 状態遷移は全て state-write.sh 経由で issue-{N}.json に記録される
