## 1. autopilot-lifecycle.md 修正

- [x] 1.1 `openspec/specs/autopilot-lifecycle.md` L9 の worktree 作成主体を「Worker」→「Pilot」に修正

## 2. cross-repo-autopilot 配下の修正

- [x] 2.1 `openspec/changes/cross-repo-autopilot/specs/worker-launch/spec.md` L5 の Worker 起動場所を worktree ディレクトリに修正
- [x] 2.2 `openspec/changes/cross-repo-autopilot/design.md` L20, L83, L86, L127 の main worktree 前提記述を修正
- [x] 2.3 `openspec/changes/cross-repo-autopilot/01.5-ac-checklist.md` L5 の Worker 起動場所を修正
- [x] 2.4 `openspec/changes/cross-repo-autopilot/proposal.md` L11 の旧スタイル記述を修正

## 3. b-3 test-mapping.yaml 修正

- [x] 3.1 `openspec/changes/b-3-autopilot-state-management/test-mapping.yaml` L523 の requirement を ADR-008 準拠に修正
- [x] 3.2 verified_by との整合を確認

## 4. b-2 hooks-and-rules.md 修正

- [x] 4.1 `openspec/changes/b-2-bare-repo-depsyaml-v30-co-naming/specs/hooks-and-rules.md` L38-40 のシナリオを Pilot/Worker 区別記述に修正

## 5. 検証

- [x] 5.1 `rg "Worker.*worktree を作成" openspec/` が 0 件であることを確認
- [x] 5.2 `rg "main worktree で.*起動" openspec/` が 0 件であることを確認
