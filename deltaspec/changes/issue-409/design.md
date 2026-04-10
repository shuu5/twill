## Context

Issue #387 の PR で追加された `tests/scenarios/skillmd-pilot-fixes.test.sh` は SKILL.md の記述内容（ドキュメント）を検証するテストであり、実際の Pilot 起動フローをランタイムで検証しない。AC「Pilot が起動時にエラー0回で plan.yaml 生成 → session 初期化 → orchestrator 起動まで到達する」の証拠がない。

## Goals / Non-Goals

**Goals:**
- `autopilot-plan.sh` が plan.yaml を生成する動作を smoke test で検証する
- `python3 -m twl.autopilot.state` の基本的な read/write が動作することを確認する
- 既存のドキュメント検証テスト (`skillmd-pilot-fixes.test.sh`) は変更しない

**Non-Goals:**
- tmux セッションの起動・orchestrator のフル実行（CI 環境で tmux が使えない場合がある）
- GitHub API を呼び出す部分のフルテスト（外部依存を避ける）
- `autopilot-launch.sh` のエンドツーエンドテスト

## Decisions

### テスト対象: `autopilot-plan.sh --explicit` モードを一時ディレクトリで実行

`--explicit` モード (`autopilot-plan.sh --explicit "409" --project-dir TMPDIR --repo-mode single`) は GitHub API 呼び出しをほぼ必要とせず、plan.yaml を生成できる。テスト完了後は一時ディレクトリを削除する。

**ただし** `warn_deps_yaml_conflict_explicit` が内部で `issue_touches_deps_yaml` を呼ぶが、これは warning のみで exit しないため、plan.yaml は生成される。

### テスト対象: `python3 -m twl.autopilot.state` の基本動作

state write/read を一時ディレクトリで実行し、フィールドの書き込み・読み取りが正しく動作することを確認する。

### テスト構造

`plugins/twl/tests/scenarios/co-autopilot-smoke.test.sh` に以下を実装:
1. 一時ディレクトリのセットアップ・クリーンアップ
2. `autopilot-plan.sh --explicit` で plan.yaml が生成されることを確認
3. `twl.autopilot.state` write/read の基本動作確認
4. 各テストは `PASS/FAIL` 形式で出力（既存テストと同形式）

## Risks / Trade-offs

- `autopilot-plan.sh --explicit` が GitHub API を呼ぶ場合は SKIP する（CI 環境で `gh` が認証されていない場合）
- tmux を使う orchestrator の起動は smoke test 対象外とし、状態マシンの動作のみを検証
- テストは依存するファイルが存在しない場合は SKIP（graceful degradation）
