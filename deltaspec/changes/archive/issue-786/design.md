# Design: DeltaSpec pending 4件の spec 統合

## Context

`deltaspec/changes/` に 4 件の未アーカイブ change が存在する:
- issue-725: isComplete=true（全 4 artifacts 完成）
- issue-729: isComplete=false（design.md のみ、proposal/specs/tasks 未作成）
- issue-732: isComplete=true（全 4 artifacts 完成）
- issue-740: isComplete=true（全 4 artifacts 完成）

これら 4 件は対応 PR がすでに merged 済みだが、`twl spec archive` による spec 統合が未実行のため `deltaspec/specs/` への要件反映が遅延している。

## Goals

- issue-729 の不足 artifacts（proposal/specs/tasks）を design.md から補完して完成させる
- issue-725/729/732/740 の 4 件を `twl spec archive -y` で `deltaspec/specs/` に統合する
- 統合後に `twl spec validate "issue-<N>"` でエラーがないことを確認する
- 各元 Issue にコメントを追加してクロスリファレンスを記録する

## Non-Goals

- 4 件の実装コード変更（各 Issue の PR で already merged）
- 新規 spec 要件の追加（issue-786 自体は手順的タスク）
- `twl spec apply` コマンドの実装（現 CLI の `twl spec archive` で代替可能）

## Decisions

| 決定 | 理由 |
|------|------|
| issue-729 を先に完成させてから全件 archive | 完成していない change を archive するとスキップされる恐れがある |
| `twl spec archive -y` で非対話実行 | CI/スクリプト環境での自動化のため |
| issue-786 自体は `--skip-specs` で archive | 手順的タスクにつき新規 spec 統合なし |
| archive 順序: 725 → 729 → 732 → 740 → 786 | Issue 番号順（依存関係なし） |

## Risks / Trade-offs

- issue-729 の proposal/specs は design.md の内容から推論して作成する必要がある。内容が design と乖離しないよう注意
- `twl spec archive` の spec 統合が失敗（既存要件の重複等）する場合は手動修正が必要
