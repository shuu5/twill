#!/usr/bin/env python3
"""Tests for Issue #566: twl --validate 13件違反解消

Spec: deltaspec/changes/issue-566/specs/validate-violations/spec.md

Covers:
1. su-observer が controller を spawn する宣言の検証 → 違反なし
2. controller が controller を spawn する宣言の検証 → 違反なし
3. user が atomic を spawn する宣言の検証 → 違反なし
4. atomic が atomic を spawn する宣言の検証 → 違反なし
5. plugin キーを持つ calls エントリの検証 → v3-calls-key 違反が報告されない
6. chain-step-sync チェックでの一致確認 → board-status-update 名前不一致なし
7. 全修正後の validate 実行 → Violations: 0

これらのテストは「修正後の期待動作」を記述する。
types.yaml・validate.py・chain-steps.sh が修正された状態で全て PASS することを想定。
修正前は FAIL する（現行の型ルール違反が残っている状態）。
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Tuple, List

import yaml

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _load_deps(plugin_dir: Path) -> dict:
    return yaml.safe_load((plugin_dir / "deps.yaml").read_text())


def _create_component_files(plugin_dir: Path, deps: dict) -> None:
    """Create minimal markdown files for every component in deps."""
    for section in ("skills", "commands", "agents", "scripts"):
        for name, data in deps.get(section, {}).items():
            path_str = data.get("path", "")
            if not path_str:
                continue
            file_path = plugin_dir / path_str
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(
                f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
                encoding="utf-8",
            )


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl in the given plugin directory."""
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def _call_validate_types(deps: dict, plugin_root: Path) -> Tuple[int, List[str], List[str]]:
    """validate_types を直接呼び出す（ユニットテスト用）。"""
    # TWL_LOOM_ROOT を設定してテスト用 types.yaml がある場所を指す
    import os
    loom_root = Path(__file__).resolve().parent.parent.parent
    os.environ["TWL_LOOM_ROOT"] = str(loom_root)

    from twl.validation.validate import validate_types
    return validate_types(deps, {}, plugin_root)


def _call_validate_v3_schema(deps: dict) -> Tuple[int, List[str]]:
    """validate_v3_schema を直接呼び出す（ユニットテスト用）。"""
    from twl.validation.validate import validate_v3_schema
    return validate_v3_schema(deps)


# ---------------------------------------------------------------------------
# Shared base class
# ---------------------------------------------------------------------------

class _ValidateTestBase:
    """Shared setup/teardown for validate violation tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _make_plugin_dir(self, name: str) -> Path:
        plugin_dir = self.tmpdir / f"test-plugin-{name}"
        plugin_dir.mkdir()
        return plugin_dir


# ===========================================================================
# Requirement: controller 型の spawnable_by に su-observer を許可
# ===========================================================================

class TestSuObserverSpawnController(_ValidateTestBase):
    """Scenario: su-observer が controller を spawn する宣言の検証"""

    def _make_su_observer_spawns_controller_deps(self) -> dict:
        """su-observer が controller を spawn する構成。
        co-autopilot が spawnable_by: [user, su-observer] を宣言する。
        """
        return {
            "version": "3.0",
            "plugin": "test-566-su-observer",
            "chains": {},
            "skills": {
                "su-observer": {
                    "type": "supervisor",
                    "path": "skills/su-observer/SKILL.md",
                    "description": "Supervisor agent",
                    "calls": [
                        {"controller": "co-autopilot"},
                    ],
                },
                "co-autopilot": {
                    "type": "controller",
                    "path": "skills/co-autopilot/SKILL.md",
                    "description": "Autopilot controller",
                    "spawnable_by": ["user", "su-observer"],
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
            "scripts": {},
        }

    def test_su_observer_can_spawn_controller_no_violation(self):
        """Scenario: su-observer が controller を spawn する宣言の検証
        WHEN spawnable_by: [user, su-observer] を宣言する controller が検証される
        THEN [spawnable_by] 違反が報告されない（Violations: 0 相当）。

        修正前: types.yaml の controller.spawnable_by に supervisor が含まれないため
        [spawnable_by] 違反が発生する。
        修正後: controller.spawnable_by に supervisor が追加されるため違反なし。
        """
        plugin_dir = self._make_plugin_dir("su-obs-controller")
        deps = self._make_su_observer_spawns_controller_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        spawnable_by_violations = [
            v for v in violations if "[spawnable_by]" in v and "co-autopilot" in v
        ]
        assert len(spawnable_by_violations) == 0, (
            f"Expected no [spawnable_by] violations for co-autopilot with spawnable_by=[user, su-observer], "
            f"but got: {spawnable_by_violations}"
        )

    def test_su_observer_spawn_controller_edge_no_violation(self):
        """Scenario: su-observer -> controller calls エッジが型整合性チェックを通過する
        WHEN su-observer が controller を calls する
        THEN [edge] 違反が報告されない。

        修正前: types.yaml の supervisor.can_spawn に controller が含まれないため
        [edge] 違反が発生する。
        修正後: supervisor.can_spawn に controller が追加されるため違反なし。
        """
        plugin_dir = self._make_plugin_dir("su-obs-edge")
        deps = self._make_su_observer_spawns_controller_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        edge_violations = [
            v for v in violations if "[edge]" in v and "su-observer" in v
        ]
        assert len(edge_violations) == 0, (
            f"Expected no [edge] violations for su-observer -> co-autopilot, "
            f"but got: {edge_violations}"
        )

    def test_su_observer_not_in_spawnable_by_causes_violation(self):
        """Edge case: spawnable_by に su-observer が含まれない場合は違反となる
        （修正後の types.yaml で controller.spawnable_by から supervisor を外した場合の検証）。
        """
        plugin_dir = self._make_plugin_dir("su-obs-missing")
        # spawnable_by に su-observer を含まない（明示的に user のみ）
        deps = {
            "version": "3.0",
            "plugin": "test-566-no-su-observer",
            "chains": {},
            "skills": {
                "co-autopilot": {
                    "type": "controller",
                    "path": "skills/co-autopilot/SKILL.md",
                    "description": "Autopilot controller",
                    "spawnable_by": ["user"],  # su-observer なし
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)
        # spawnable_by: [user] のみの宣言は types.yaml の許可範囲内なので違反なし
        spawnable_by_violations = [
            v for v in violations if "[spawnable_by]" in v and "co-autopilot" in v
        ]
        assert len(spawnable_by_violations) == 0, (
            f"spawnable_by: [user] only should not be a violation, but got: {spawnable_by_violations}"
        )


# ===========================================================================
# Requirement: controller 型の can_spawn に controller を許可
# ===========================================================================

class TestControllerSpawnController(_ValidateTestBase):
    """Scenario: controller が controller を spawn する宣言の検証"""

    def _make_controller_spawns_controller_deps(self) -> dict:
        """controller が controller を can_spawn で宣言する構成。"""
        return {
            "version": "3.0",
            "plugin": "test-566-ctrl-ctrl",
            "chains": {},
            "skills": {
                "co-autopilot": {
                    "type": "controller",
                    "path": "skills/co-autopilot/SKILL.md",
                    "description": "Autopilot controller",
                    "can_spawn": ["composite", "atomic", "specialist", "controller"],
                    "spawnable_by": ["user"],
                    "calls": [
                        {"controller": "co-issue"},
                    ],
                },
                "co-issue": {
                    "type": "controller",
                    "path": "skills/co-issue/SKILL.md",
                    "description": "Issue controller",
                    "spawnable_by": ["user"],
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
            "scripts": {},
        }

    def test_controller_can_spawn_controller_no_violation(self):
        """Scenario: controller が controller を spawn する宣言の検証
        WHEN can_spawn: [..., controller] を宣言する controller が検証される
        THEN [can_spawn] 違反が報告されない（Violations: 0 相当）。

        修正前: types.yaml の controller.can_spawn に controller が含まれないため
        [can_spawn] 違反が発生する。
        修正後: controller.can_spawn に controller が追加されるため違反なし。
        """
        plugin_dir = self._make_plugin_dir("ctrl-ctrl")
        deps = self._make_controller_spawns_controller_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        can_spawn_violations = [
            v for v in violations if "[can_spawn]" in v and "co-autopilot" in v
        ]
        assert len(can_spawn_violations) == 0, (
            f"Expected no [can_spawn] violations for co-autopilot with can_spawn=[..., controller], "
            f"but got: {can_spawn_violations}"
        )

    def test_controller_spawn_controller_edge_no_violation(self):
        """Scenario: controller -> controller calls エッジが型整合性チェックを通過する
        WHEN controller が controller を calls する
        THEN [edge] 違反が報告されない。
        """
        plugin_dir = self._make_plugin_dir("ctrl-ctrl-edge")
        deps = self._make_controller_spawns_controller_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        edge_violations = [
            v for v in violations if "[edge]" in v and "co-autopilot" in v
        ]
        assert len(edge_violations) == 0, (
            f"Expected no [edge] violations for co-autopilot -> co-issue (controller -> controller), "
            f"but got: {edge_violations}"
        )

    def test_controller_spawning_unknown_type_causes_violation(self):
        """Edge case: can_spawn に不明な型を宣言した場合は違反となる。"""
        plugin_dir = self._make_plugin_dir("ctrl-unknown")
        deps = {
            "version": "3.0",
            "plugin": "test-566-ctrl-unknown",
            "chains": {},
            "skills": {
                "bad-controller": {
                    "type": "controller",
                    "path": "skills/bad-controller/SKILL.md",
                    "description": "Bad controller",
                    "can_spawn": ["nonexistent-type"],
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)
        # nonexistent-type は TYPE_RULES にないので [can_spawn] 違反
        can_spawn_violations = [
            v for v in violations if "[can_spawn]" in v and "bad-controller" in v
        ]
        assert len(can_spawn_violations) > 0, (
            f"Expected [can_spawn] violation for nonexistent-type, but none found. "
            f"violations={violations}"
        )


# ===========================================================================
# Requirement: atomic 型の spawnable_by に user を許可
# ===========================================================================

class TestUserSpawnAtomic(_ValidateTestBase):
    """Scenario: user が atomic を spawn する宣言の検証"""

    def _make_user_spawnable_atomic_deps(self) -> dict:
        """spawnable_by: [user] を宣言する atomic コンポーネントを含む構成。"""
        return {
            "version": "3.0",
            "plugin": "test-566-user-atomic",
            "chains": {},
            "skills": {},
            "commands": {
                "su-compact": {
                    "type": "atomic",
                    "path": "commands/su-compact.md",
                    "description": "Compaction atomic",
                    "spawnable_by": ["user"],
                    "calls": [],
                },
                "externalize-state": {
                    "type": "atomic",
                    "path": "commands/externalize-state.md",
                    "description": "Externalize state atomic",
                    "spawnable_by": ["user"],
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }

    def test_user_spawnable_atomic_no_violation(self):
        """Scenario: user が atomic を spawn する宣言の検証
        WHEN spawnable_by: [user] を宣言する atomic（su-compact, externalize-state）が検証される
        THEN [spawnable_by] 違反が報告されない（Violations: 0 相当）。

        修正前: types.yaml の atomic.spawnable_by に user が含まれないため違反が発生する。
        修正後: atomic.spawnable_by に user が追加されるため違反なし。
        """
        plugin_dir = self._make_plugin_dir("user-atomic")
        deps = self._make_user_spawnable_atomic_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        spawnable_by_violations = [
            v for v in violations
            if "[spawnable_by]" in v and ("su-compact" in v or "externalize-state" in v)
        ]
        assert len(spawnable_by_violations) == 0, (
            f"Expected no [spawnable_by] violations for atomic with spawnable_by=[user], "
            f"but got: {spawnable_by_violations}"
        )

    def test_user_spawnable_single_atomic_no_violation(self):
        """Edge case: spawnable_by: [user] のみ宣言する単一 atomic でも違反なし。"""
        plugin_dir = self._make_plugin_dir("user-atomic-single")
        deps = {
            "version": "3.0",
            "plugin": "test-566-user-atomic-single",
            "chains": {},
            "skills": {},
            "commands": {
                "my-atomic": {
                    "type": "atomic",
                    "path": "commands/my-atomic.md",
                    "description": "Direct user atomic",
                    "spawnable_by": ["user"],
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        spawnable_by_violations = [
            v for v in violations if "[spawnable_by]" in v and "my-atomic" in v
        ]
        assert len(spawnable_by_violations) == 0, (
            f"atomic with spawnable_by=[user] should not violate, but got: {spawnable_by_violations}"
        )

    def test_atomic_with_invalid_spawnable_by_causes_violation(self):
        """Edge case: atomic の spawnable_by に存在しない型を宣言した場合は違反となる。"""
        plugin_dir = self._make_plugin_dir("atomic-invalid-spawnby")
        deps = {
            "version": "3.0",
            "plugin": "test-566-invalid",
            "chains": {},
            "skills": {},
            "commands": {
                "bad-atomic": {
                    "type": "atomic",
                    "path": "commands/bad-atomic.md",
                    "description": "Bad atomic",
                    "spawnable_by": ["nonexistent-caller"],
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        spawnable_by_violations = [
            v for v in violations if "[spawnable_by]" in v and "bad-atomic" in v
        ]
        assert len(spawnable_by_violations) > 0, (
            f"Expected [spawnable_by] violation for nonexistent-caller, but none found. "
            f"violations={violations}"
        )


# ===========================================================================
# Requirement: atomic 型の can_spawn に atomic を許可
# ===========================================================================

class TestAtomicSpawnAtomic(_ValidateTestBase):
    """Scenario: atomic が atomic を spawn する宣言の検証"""

    def _make_atomic_spawns_atomic_deps(self) -> dict:
        """atomic が atomic を can_spawn する構成（edge チェック含む）。"""
        return {
            "version": "3.0",
            "plugin": "test-566-atomic-atomic",
            "chains": {},
            "skills": {},
            "commands": {
                "su-compact": {
                    "type": "atomic",
                    "path": "commands/su-compact.md",
                    "description": "Compaction atomic",
                    "spawnable_by": ["user"],
                    "calls": [
                        {"atomic": "externalize-state"},
                    ],
                },
                "externalize-state": {
                    "type": "atomic",
                    "path": "commands/externalize-state.md",
                    "description": "Externalize state atomic",
                    "spawnable_by": ["user", "atomic"],
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }

    def test_atomic_spawn_atomic_edge_no_violation(self):
        """Scenario: atomic が atomic を spawn する宣言の検証
        WHEN atomic が atomic を calls する（su-compact -> externalize-state）
        THEN [edge] 違反が報告されない（Violations: 0 相当）。

        修正前: types.yaml の atomic.can_spawn に atomic が含まれないため
        [edge] 違反が発生する。
        修正後: atomic.can_spawn に atomic が追加されるため違反なし。
        """
        plugin_dir = self._make_plugin_dir("atomic-atomic")
        deps = self._make_atomic_spawns_atomic_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        edge_violations = [
            v for v in violations if "[edge]" in v and "su-compact" in v
        ]
        assert len(edge_violations) == 0, (
            f"Expected no [edge] violations for atomic -> atomic (su-compact -> externalize-state), "
            f"but got: {edge_violations}"
        )

    def test_atomic_can_spawn_atomic_declaration_no_violation(self):
        """Edge case: can_spawn: [atomic] を宣言する atomic に [can_spawn] 違反なし。"""
        plugin_dir = self._make_plugin_dir("atomic-can-spawn")
        deps = {
            "version": "3.0",
            "plugin": "test-566-atomic-can-spawn",
            "chains": {},
            "skills": {},
            "commands": {
                "parent-atomic": {
                    "type": "atomic",
                    "path": "commands/parent-atomic.md",
                    "description": "Parent atomic",
                    "can_spawn": ["atomic", "reference"],
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        can_spawn_violations = [
            v for v in violations if "[can_spawn]" in v and "parent-atomic" in v
        ]
        assert len(can_spawn_violations) == 0, (
            f"atomic with can_spawn=[atomic, reference] should not violate, "
            f"but got: {can_spawn_violations}"
        )

    def test_atomic_spawns_workflow_causes_violation(self):
        """Edge case: atomic が workflow を spawn しようとすると違反になる（境界値テスト）。"""
        plugin_dir = self._make_plugin_dir("atomic-workflow-bad")
        deps = {
            "version": "3.0",
            "plugin": "test-566-atomic-workflow",
            "chains": {},
            "skills": {
                "target-workflow": {
                    "type": "workflow",
                    "path": "skills/target-workflow/SKILL.md",
                    "description": "A workflow",
                    "calls": [],
                },
            },
            "commands": {
                "bad-atomic": {
                    "type": "atomic",
                    "path": "commands/bad-atomic.md",
                    "description": "Bad atomic that calls workflow",
                    "calls": [
                        {"workflow": "target-workflow"},
                    ],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, _warnings = _call_validate_types(deps, plugin_dir)

        edge_violations = [
            v for v in violations if "[edge]" in v and "bad-atomic" in v
        ]
        assert len(edge_violations) > 0, (
            f"Expected [edge] violation for atomic -> workflow, but none found. "
            f"violations={violations}"
        )


# ===========================================================================
# Requirement: v3-calls-key チェックで plugin キーを許可
# ===========================================================================

class TestPluginKeyInCalls(_ValidateTestBase):
    """Scenario: plugin キーを持つ calls エントリの検証"""

    def _make_plugin_key_calls_deps(self) -> dict:
        """calls エントリに plugin キーが含まれる構成。"""
        return {
            "version": "3.0",
            "plugin": "test-566-plugin-key",
            "chains": {},
            "skills": {},
            "commands": {},
            "agents": {},
            "scripts": {
                "spec-review-orchestrator": {
                    "type": "script",
                    "path": "scripts/spec-review-orchestrator.sh",
                    "description": "Orchestrator script",
                    "calls": [
                        {"script": "cld-spawn", "plugin": "session"},
                        {"script": "session-comm.sh", "plugin": "session"},
                    ],
                },
                "issue-lifecycle-orchestrator": {
                    "type": "script",
                    "path": "scripts/issue-lifecycle-orchestrator.sh",
                    "description": "Issue lifecycle orchestrator",
                    "calls": [
                        {"script": "cld-spawn", "plugin": "session"},
                    ],
                },
            },
        }

    def test_plugin_key_in_calls_no_v3_calls_key_violation(self):
        """Scenario: plugin キーを持つ calls エントリの検証
        WHEN calls エントリに plugin: <name> キーが含まれるスクリプトが検証される
        THEN [v3-calls-key] 違反が報告されない。

        修正前: validate_v3_schema の v3_type_keys に plugin が含まれないため
        [v3-calls-key] 'unknown key plugin' 違反が発生する。
        修正後: plugin キーが許可リストに追加されるため違反なし。
        """
        deps = self._make_plugin_key_calls_deps()
        ok_count, violations = _call_validate_v3_schema(deps)

        plugin_key_violations = [
            v for v in violations
            if "[v3-calls-key]" in v and "plugin" in v and "unknown key" in v
        ]
        assert len(plugin_key_violations) == 0, (
            f"Expected no [v3-calls-key] violations for 'plugin' key, "
            f"but got: {plugin_key_violations}"
        )

    def test_plugin_key_with_spec_review_orchestrator_no_violation(self):
        """Edge case: spec-review-orchestrator の plugin キーが違反なし。"""
        deps = self._make_plugin_key_calls_deps()
        ok_count, violations = _call_validate_v3_schema(deps)

        violations_for_spec_review = [
            v for v in violations
            if "spec-review-orchestrator" in v and "[v3-calls-key]" in v
        ]
        assert len(violations_for_spec_review) == 0, (
            f"Expected no violations for spec-review-orchestrator, "
            f"but got: {violations_for_spec_review}"
        )

    def test_plugin_key_with_issue_lifecycle_orchestrator_no_violation(self):
        """Edge case: issue-lifecycle-orchestrator の plugin キーが違反なし。"""
        deps = self._make_plugin_key_calls_deps()
        ok_count, violations = _call_validate_v3_schema(deps)

        violations_for_lifecycle = [
            v for v in violations
            if "issue-lifecycle-orchestrator" in v and "[v3-calls-key]" in v
        ]
        assert len(violations_for_lifecycle) == 0, (
            f"Expected no violations for issue-lifecycle-orchestrator, "
            f"but got: {violations_for_lifecycle}"
        )

    def test_unknown_key_still_causes_violation(self):
        """Edge case: plugin 以外の不明キーは依然として [v3-calls-key] 違反になる。"""
        deps = {
            "version": "3.0",
            "plugin": "test-566-unknown-key",
            "chains": {},
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "skills/my-controller/SKILL.md",
                    "description": "Controller",
                    "calls": [
                        {"totally-unknown-key": "something"},
                    ],
                },
            },
            "commands": {},
            "agents": {},
            "scripts": {},
        }
        ok_count, violations = _call_validate_v3_schema(deps)

        unknown_key_violations = [
            v for v in violations
            if "[v3-calls-key]" in v and "totally-unknown-key" in v
        ]
        assert len(unknown_key_violations) > 0, (
            f"Expected [v3-calls-key] violation for 'totally-unknown-key', but none found. "
            f"violations={violations}"
        )

    def test_v2_section_key_still_causes_violation(self):
        """Edge case: v2.0 形式の section キー（command, skill, agent）は依然として違反。"""
        deps = {
            "version": "3.0",
            "plugin": "test-566-v2-key",
            "chains": {},
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "skills/my-controller/SKILL.md",
                    "description": "Controller",
                    "calls": [
                        {"command": "some-command"},
                    ],
                },
            },
            "commands": {
                "some-command": {
                    "type": "atomic",
                    "path": "commands/some-command.md",
                    "description": "Command",
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }
        ok_count, violations = _call_validate_v3_schema(deps)

        v2_key_violations = [
            v for v in violations
            if "[v3-calls-key]" in v and "'command'" in v
        ]
        assert len(v2_key_violations) > 0, (
            f"Expected [v3-calls-key] violation for v2 'command' key, but none found. "
            f"violations={violations}"
        )


# ===========================================================================
# Requirement: chain-step-sync チェックで board-status-update 不一致なし
# ===========================================================================

class TestChainStepSyncBoardStatusUpdate(_ValidateTestBase):
    """Scenario: chain-step-sync チェックでの board-status-update 名前不一致確認"""

    def _make_chain_step_sync_deps(self, step_name: str = "project-board-status-update") -> dict:
        """chain に指定されたステップ名を含む deps 構成を作成する。"""
        return {
            "version": "3.0",
            "plugin": "test-566-chain-sync",
            "chains": {
                "setup": {
                    "description": "Setup chain",
                    "type": "A",
                    "steps": [
                        "init",
                        step_name,
                    ],
                },
            },
            "skills": {
                "workflow-setup": {
                    "type": "workflow",
                    "path": "skills/workflow-setup/SKILL.md",
                    "description": "Setup workflow",
                    "chain": "setup",
                    "calls": [],
                },
            },
            "commands": {
                "init": {
                    "type": "atomic",
                    "path": "commands/init.md",
                    "description": "Init command",
                    "chain": "setup",
                    "calls": [],
                },
                step_name: {
                    "type": "atomic",
                    "path": f"commands/{step_name}.md",
                    "description": "Board status update command",
                    "chain": "setup",
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }

    def test_chain_steps_sh_uses_board_status_update_alias(self):
        """Scenario: chain-step-sync チェックでの一致確認
        chain-steps.sh の CHAIN_STEPS 配列が 'board-status-update' を含み、
        deps.yaml の chains が 'project-board-status-update' を含む場合、
        名前不一致 warning が報告される。

        修正後: chain-steps.sh が 'project-board-status-update' を使用するため
        [chain-step-sync] 名前不一致 warning は報告されなくなる。

        このテストは修正後の期待動作（不一致なし）を検証する。
        """
        from twl.chain.validate import chain_validate

        # プラグイン deps.yaml を 'project-board-status-update' で構成
        plugin_dir = self._make_plugin_dir("chain-step-sync")
        deps = self._make_chain_step_sync_deps(step_name="project-board-status-update")
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        # chain-steps.sh の代替として一時ファイルを作成
        # 修正後の chain-steps.sh には 'project-board-status-update' が含まれる
        scripts_dir = plugin_dir / "scripts"
        scripts_dir.mkdir(parents=True, exist_ok=True)
        (scripts_dir / "chain-steps.sh").write_text(
            "#!/usr/bin/env bash\n"
            "CHAIN_STEPS=(\n"
            "  init\n"
            "  project-board-status-update\n"
            ")\n"
            "declare -A CHAIN_STEP_DISPATCH=(\n"
            "  [init]=runner\n"
            "  [project-board-status-update]=runner\n"
            ")\n",
            encoding="utf-8",
        )

        criticals, warnings, infos = chain_validate(deps, plugin_dir)

        # 'board-status-update' 名前不一致 warning がないことを確認
        board_status_warnings = [
            w for w in warnings
            if "board-status-update" in w and "chain-step-sync" in w
            and "≈" in w  # 8c. similar-but-not-identical
        ]
        assert len(board_status_warnings) == 0, (
            f"Expected no [chain-step-sync] name mismatch warnings for board-status-update, "
            f"but got: {board_status_warnings}"
        )

    def test_chain_step_name_mismatch_causes_warning(self):
        """Edge case: chain-steps.sh と deps.yaml でステップ名が異なる場合は warning が出る。
        これは chain-step-sync チェックの基本動作を確認するテスト。
        """
        from twl.chain.validate import chain_validate

        plugin_dir = self._make_plugin_dir("chain-step-mismatch")
        # deps.yaml は 'project-board-status-update' を使用
        deps = self._make_chain_step_sync_deps(step_name="project-board-status-update")
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        # chain-steps.sh は旧名称 'board-status-update' を使用（修正前の状態）
        scripts_dir = plugin_dir / "scripts"
        scripts_dir.mkdir(parents=True, exist_ok=True)
        (scripts_dir / "chain-steps.sh").write_text(
            "#!/usr/bin/env bash\n"
            "CHAIN_STEPS=(\n"
            "  init\n"
            "  board-status-update\n"  # 旧名称（不一致）
            ")\n"
            "declare -A CHAIN_STEP_DISPATCH=(\n"
            "  [init]=runner\n"
            "  [board-status-update]=runner\n"
            ")\n",
            encoding="utf-8",
        )

        criticals, warnings, infos = chain_validate(deps, plugin_dir)

        # 名前不一致の warning（8c: similar-but-not-identical）が報告されるはず
        mismatch_warnings = [
            w for w in warnings
            if "[chain-step-sync]" in w and "board-status-update" in w
        ]
        assert len(mismatch_warnings) > 0, (
            f"Expected [chain-step-sync] warning for board-status-update vs project-board-status-update, "
            f"but none found. warnings={warnings}"
        )


# ===========================================================================
# Requirement: 全修正後の validate 実行 → Violations: 0
# ===========================================================================

class TestFullValidateZeroViolations(_ValidateTestBase):
    """Scenario: 全修正後の validate 実行 → Violations: 0"""

    def _make_comprehensive_valid_deps(self) -> dict:
        """Issue #566 の全修正が適用された後に違反なしとなる包括的な deps 構成。

        以下のパターンを全て含む:
        - controller が spawnable_by: [user, su-observer] を宣言
        - controller が can_spawn: [controller, ...] を宣言
        - atomic が spawnable_by: [user] を宣言
        - atomic が atomic を calls する edge
        - calls エントリに plugin: キーが含まれる
        """
        return {
            "version": "3.0",
            "plugin": "test-566-comprehensive",
            "chains": {},
            "skills": {
                "su-observer": {
                    "type": "supervisor",
                    "path": "skills/su-observer/SKILL.md",
                    "description": "Supervisor",
                    "calls": [
                        {"controller": "co-autopilot"},
                    ],
                },
                "co-autopilot": {
                    "type": "controller",
                    "path": "skills/co-autopilot/SKILL.md",
                    "description": "Autopilot controller",
                    "spawnable_by": ["user", "su-observer"],
                    "can_spawn": ["composite", "atomic", "specialist", "controller"],
                    "calls": [
                        {"atomic": "su-compact"},
                        {"controller": "co-issue"},
                    ],
                },
                "co-issue": {
                    "type": "controller",
                    "path": "skills/co-issue/SKILL.md",
                    "description": "Issue controller",
                    "spawnable_by": ["user"],
                    "calls": [],
                },
            },
            "commands": {
                "su-compact": {
                    "type": "atomic",
                    "path": "commands/su-compact.md",
                    "description": "Compaction atomic",
                    "spawnable_by": ["user", "atomic", "controller"],
                    "calls": [
                        {"atomic": "externalize-state"},
                    ],
                },
                "externalize-state": {
                    "type": "atomic",
                    "path": "commands/externalize-state.md",
                    "description": "Externalize state",
                    "spawnable_by": ["user", "atomic", "controller"],
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {
                "spec-review-orchestrator": {
                    "type": "script",
                    "path": "scripts/spec-review-orchestrator.sh",
                    "description": "Orchestrator",
                    "calls": [
                        {"script": "cld-spawn", "plugin": "session"},
                    ],
                },
            },
        }

    def test_all_patterns_no_type_violations(self):
        """Scenario: 全修正後の validate 実行 → Violations: 0（型チェック）
        WHEN types.yaml が全修正された状態で validate_types を呼ぶ
        THEN 違反リストが空（0 件）となる。
        """
        plugin_dir = self._make_plugin_dir("comprehensive")
        deps = self._make_comprehensive_valid_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, warnings = _call_validate_types(deps, plugin_dir)

        assert len(violations) == 0, (
            f"Expected 0 type violations after all fixes, but got {len(violations)}: "
            f"{violations}"
        )
        assert ok_count > 0, "ok_count should be positive when everything is valid"

    def test_all_patterns_no_v3_schema_violations(self):
        """Scenario: 全修正後の validate 実行 → Violations: 0（v3 スキーマチェック）
        WHEN validate.py が全修正された状態で validate_v3_schema を呼ぶ
        THEN 違反リストが空（0 件）となる。
        """
        deps = self._make_comprehensive_valid_deps()
        ok_count, violations = _call_validate_v3_schema(deps)

        assert len(violations) == 0, (
            f"Expected 0 v3 schema violations after all fixes, but got {len(violations)}: "
            f"{violations}"
        )

    def test_validate_command_exits_zero_on_valid_plugin(self):
        """Scenario: 修正後の validate コマンドが exit 0 で終了する
        WHEN 全修正が適用されたプラグインで --validate を実行
        THEN プロセスは exit code 0 で終了し、出力に Violations: 0 が含まれる。

        注: このテストはシンプルな既知の有効プラグインを使って
        --validate コマンド全体の動作を検証する。
        """
        plugin_dir = self._make_plugin_dir("validate-cmd")
        # シンプルかつ既知の有効な構成（types.yaml との整合性が確認済みの範囲）
        deps = {
            "version": "3.0",
            "plugin": "test-566-simple-valid",
            "chains": {},
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "skills/my-controller/SKILL.md",
                    "description": "Controller",
                    "calls": [
                        {"atomic": "my-action"},
                    ],
                },
            },
            "commands": {
                "my-action": {
                    "type": "atomic",
                    "path": "commands/my-action.md",
                    "description": "Atomic action",
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--validate")

        assert result.returncode == 0, (
            f"--validate on valid plugin should exit 0, got {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_no_violations_with_su_observer_and_controller_spawn(self):
        """Integration test: su-observer → controller → atomic の全チェーンが違反なし。

        修正後の types.yaml で以下が全て許可される:
        - supervisor.can_spawn: controller を追加
        - controller.spawnable_by: supervisor を追加
        - atomic.spawnable_by: user を追加
        - atomic.can_spawn: atomic を追加
        """
        plugin_dir = self._make_plugin_dir("full-chain")
        deps = {
            "version": "3.0",
            "plugin": "test-566-full-chain",
            "chains": {},
            "skills": {
                "su-observer": {
                    "type": "supervisor",
                    "path": "skills/su-observer/SKILL.md",
                    "description": "Supervisor",
                    "calls": [
                        {"controller": "co-autopilot"},
                    ],
                },
                "co-autopilot": {
                    "type": "controller",
                    "path": "skills/co-autopilot/SKILL.md",
                    "description": "Autopilot",
                    "spawnable_by": ["user", "su-observer"],
                    "can_spawn": ["atomic", "controller"],
                    "calls": [
                        {"atomic": "su-compact"},
                    ],
                },
            },
            "commands": {
                "su-compact": {
                    "type": "atomic",
                    "path": "commands/su-compact.md",
                    "description": "Compact",
                    "spawnable_by": ["user", "controller"],
                    "calls": [],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        ok_count, violations, warnings = _call_validate_types(deps, plugin_dir)

        assert len(violations) == 0, (
            f"Expected 0 violations for su-observer→controller→atomic chain, "
            f"but got {len(violations)}: {violations}"
        )


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestSuObserverSpawnController,
        TestControllerSpawnController,
        TestUserSpawnAtomic,
        TestAtomicSpawnAtomic,
        TestPluginKeyInCalls,
        TestChainStepSyncBoardStatusUpdate,
        TestFullValidateZeroViolations,
    ]
    passed = 0
    failed = 0
    errors = []

    for cls in classes:
        for method_name in sorted(dir(cls)):
            if not method_name.startswith("test_"):
                continue
            instance = cls()
            if hasattr(instance, "setup_method"):
                instance.setup_method()
            try:
                getattr(instance, method_name)()
                passed += 1
                print(f"  PASS: {cls.__name__}.{method_name}")
            except Exception as e:
                failed += 1
                errors.append((f"{cls.__name__}.{method_name}", e))
                print(f"  FAIL: {cls.__name__}.{method_name}: {e}")
                traceback.print_exc()
            finally:
                if hasattr(instance, "teardown_method"):
                    instance.teardown_method()

    print(f"\n{'=' * 60}")
    print(f"Results: {passed} passed, {failed} failed")
    if errors:
        print("\nFailures:")
        for name, err in errors:
            print(f"  {name}: {err}")
        sys.exit(1)
    else:
        print("All tests passed!")
