## MODIFIED Requirements

### Requirement: issue-structure arch-ref タグ自動生成

issue-structure の Step 2.5 は、`ctx/<name>` ラベルを提案するとき、対応する `architecture/domain/contexts/<name>.md` のパスを `<!-- arch-ref-start -->` / `<!-- arch-ref-end -->` タグで囲んで Issue body に出力しなければならない（SHALL）。

マッチ数別の動作：
- 単一マッチ：対応パスを出力する（SHALL）
- 複数マッチ：主要 context のパスのみ出力する（SHALL）
- 該当なし：タグセクション自体を出力しない（SHALL NOT）

#### Scenario: 単一 ctx ラベルマッチ
- **WHEN** issue-structure が `ctx/pr-cycle` ラベルを提案する
- **THEN** Issue body に `<!-- arch-ref-start -->\narchitecture/domain/contexts/pr-cycle.md\n<!-- arch-ref-end -->` が追記される

#### Scenario: 複数 ctx ラベルマッチ
- **WHEN** issue-structure が `ctx/pr-cycle` と `ctx/autopilot` の両方を提案する
- **THEN** 主要 context（比重が高い方）のパスのみが arch-ref タグ内に出力される

#### Scenario: ctx ラベル該当なし
- **WHEN** issue-structure が ctx/* に該当するラベルを提案しない
- **THEN** `<!-- arch-ref-start -->` タグは Issue body に出力されない
