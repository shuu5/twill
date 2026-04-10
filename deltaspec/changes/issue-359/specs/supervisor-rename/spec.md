## MODIFIED Requirements

### Requirement: intervention-catalog Supervisor 呼称統一

intervention-catalog.md の介入判断主体呼称を Observer から Supervisor に更新しなければならない（SHALL）。
ただし、Live Observation コンテキストの "Observer" は置換対象外とする。

#### Scenario: 介入判断主体の呼称確認

- **WHEN** `plugins/twl/refs/intervention-catalog.md` を参照する
- **THEN** 介入判断・実行主体の呼称として "Supervisor" が使用され、旧称 "Observer" がメタ認知文脈で残存していない

### Requirement: intervene-auto Supervisor 呼称統一

`plugins/twl/commands/intervene-auto.md` の description 行の Observer 参照を Supervisor に更新しなければならない（SHALL）。

#### Scenario: intervene-auto description 確認

- **WHEN** `plugins/twl/commands/intervene-auto.md` の description を確認する
- **THEN** "Supervisor が自動実行する Layer 0 介入" と記載されている

### Requirement: intervene-confirm Supervisor 呼称統一

`plugins/twl/commands/intervene-confirm.md` の description 行および本文の Observer 参照を Supervisor に更新しなければならない（SHALL）。

#### Scenario: intervene-confirm 参照確認

- **WHEN** `plugins/twl/commands/intervene-confirm.md` を確認する
- **THEN** "Supervisor がユーザーの確認を得てから実行する" と記載されている

### Requirement: intervene-escalate Supervisor 呼称統一

`plugins/twl/commands/intervene-escalate.md` の description 行および本文の Observer 参照を Supervisor に更新しなければならない（SHALL）。

#### Scenario: intervene-escalate 参照確認

- **WHEN** `plugins/twl/commands/intervene-escalate.md` を確認する
- **THEN** "Supervisor が自分では実行せずにユーザーへ委譲する" と記載されている

### Requirement: twl check PASS

変更後に `twl check` が PASS しなければならない（SHALL）。

#### Scenario: 変更後の整合性確認

- **WHEN** 全ファイルの更新が完了した後に `twl check` を実行する
- **THEN** エラーなく PASS する
