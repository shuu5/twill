## Context

`autopilot-phase-execute.md` の `resolve_issue_repo_context()` は Issue ごとにリポジトリ情報を解決する。クロスリポジトリ時は `PILOT_AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"` と設定されるが、単一リポジトリ（`_default`）時は空文字列が設定される。

autopilot-launch は `PILOT_AUTOPILOT_DIR` が空でないとき Worker の `AUTOPILOT_DIR` に設定するため、単一リポジトリ時は Worker が AUTOPILOT_DIR を受け取れない。

## Goals / Non-Goals

**Goals:**

- 単一リポジトリ時に `PILOT_AUTOPILOT_DIR` が Pilot の `$AUTOPILOT_DIR` をデフォルト値として保持する

**Non-Goals:**

- クロスリポジトリロジックの変更
- autopilot-launch 側のバリデーションロジック変更

## Decisions

1. `else` ブランチで `PILOT_AUTOPILOT_DIR="$AUTOPILOT_DIR"` を設定する
   - 理由: 単一リポジトリでは Pilot と Worker が同じ `.autopilot/` を参照するため、Pilot の AUTOPILOT_DIR をそのまま使う

## Risks / Trade-offs

- リスク: 低。既存の `$AUTOPILOT_DIR` 変数は `resolve_issue_repo_context()` 呼び出し前に必ず設定済み
- 互換性: autopilot-launch の既存バリデーション（絶対パス必須 + パストラバーサル禁止）を通過する正常なパスが渡される
