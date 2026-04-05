#!/usr/bin/env python3
"""Tests for deep_validate() section A/B/C _is_within_root() guard.

Spec: openspec/changes/add-is-within-root-check/specs/is-within-root-guard.md

Coverage: edge-cases

Requirements tested:
- Section A (controller-bloat): _is_within_root() guard before _count_body_lines()
- Section B (ref-placement): _is_within_root() guard before ds_path.exists() / read_text()
- Section C (tools-mismatch): _is_within_root() guard before _parse_frontmatter_tools() / _scan_body_for_mcp_tools()
- Section E regression: existing _is_within_root() check at L2924 must not change
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "twl-engine.py"

# ---------------------------------------------------------------------------
# Base fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(TWL_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


class _BaseTest:
    """Shared setup/teardown for all section guard tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Section A fixtures
# ---------------------------------------------------------------------------

def _make_section_a_fixture(
    tmpdir: Path,
    *,
    controller_path: str,
    create_file: bool = True,
    body_lines_count: int = 5,
) -> Path:
    """Minimal plugin for section A (controller-bloat) tests.

    Args:
        controller_path: The path value in deps.yaml for the controller skill.
        create_file: Whether to physically create the controller file.
        body_lines_count: Number of body lines to write when create_file=True.
    """
    plugin_dir = tmpdir / "plugin-section-a"
    plugin_dir.mkdir(exist_ok=True)

    deps = {
        "version": "3.0",
        "plugin": "test-section-a",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": controller_path,
                "description": "Test controller",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)

    if create_file:
        file_path = plugin_dir / controller_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        body = "\n".join([f"Line {i} of controller body." for i in range(body_lines_count)])
        file_path.write_text(
            f"---\nname: my-controller\ndescription: Test\n---\n\n{body}\n",
            encoding="utf-8",
        )

    return plugin_dir


# ---------------------------------------------------------------------------
# Section B fixtures
# ---------------------------------------------------------------------------

def _make_section_b_fixture(
    tmpdir: Path,
    *,
    downstream_path: str,
    create_downstream_file: bool = True,
    ref_name: str = "my-ref",
    downstream_body_contains_ref: bool = True,
) -> Path:
    """Plugin for section B (ref-placement) tests.

    Sets up: controller -> (atomic downstream, reference ref)
    The downstream's path is under test; body may or may not mention the ref.
    """
    plugin_dir = tmpdir / "plugin-section-b"
    plugin_dir.mkdir(exist_ok=True)

    # reference type must live in skills (TYPE_RULES constraint)
    deps = {
        "version": "3.0",
        "plugin": "test-section-b",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Controller",
                "calls": [
                    {"atomic": "my-action"},
                    {"reference": ref_name},
                ],
            },
            ref_name: {
                "type": "reference",
                "path": f"skills/{ref_name}/SKILL.md",
                "description": "A reference doc",
                "calls": [],
            },
        },
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": downstream_path,
                "description": "Downstream atomic",
                "calls": [],
                # Intentionally omit the reference from calls to provoke ref-placement warning
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)

    # Always create the controller file
    ctrl_dir = plugin_dir / "skills" / "my-controller"
    ctrl_dir.mkdir(parents=True, exist_ok=True)
    (ctrl_dir / "SKILL.md").write_text(
        "---\nname: my-controller\ndescription: Controller\n---\n\n## Step 0\nRoute.\n",
        encoding="utf-8",
    )

    # Create the reference file (in skills/)
    ref_skill_dir = plugin_dir / "skills" / ref_name
    ref_skill_dir.mkdir(parents=True, exist_ok=True)
    (ref_skill_dir / "SKILL.md").write_text(
        f"---\nname: {ref_name}\ndescription: Reference\n---\n\nRef content.\n",
        encoding="utf-8",
    )

    if create_downstream_file:
        # The body mentions the ref name to provoke ref-placement warning (no guard scenario)
        body_content = f"Uses {ref_name} in the body.\n" if downstream_body_contains_ref else "No ref here.\n"
        file_path = plugin_dir / downstream_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(
            f"---\nname: my-action\ndescription: Action\n---\n\n{body_content}",
            encoding="utf-8",
        )

    return plugin_dir


# ---------------------------------------------------------------------------
# Section C fixtures
# ---------------------------------------------------------------------------

def _make_section_c_fixture(
    tmpdir: Path,
    *,
    command_path: str,
    create_file: bool = True,
    include_mcp_tool_in_body: bool = True,
    declare_tool_in_frontmatter: bool = False,
) -> Path:
    """Plugin for section C (tools-mismatch) tests.

    Sets up a single atomic command whose path is under test.
    Body may contain mcp__* tool usage; frontmatter may or may not declare it.
    """
    plugin_dir = tmpdir / "plugin-section-c"
    plugin_dir.mkdir(exist_ok=True)

    deps = {
        "version": "3.0",
        "plugin": "test-section-c",
        "skills": {},
        "commands": {
            "my-cmd": {
                "type": "atomic",
                "path": command_path,
                "description": "Test command",
                "calls": [],
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)

    if create_file:
        tools_line = "allowed-tools: mcp__myserver__mytool\n" if declare_tool_in_frontmatter else ""
        body = "Use mcp__myserver__mytool here.\n" if include_mcp_tool_in_body else "No mcp tool here.\n"
        file_path = plugin_dir / command_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(
            f"---\nname: my-cmd\ndescription: Test\n{tools_line}---\n\n{body}",
            encoding="utf-8",
        )

    return plugin_dir


# ===========================================================================
# Requirement: deep_validate section A ルート外パスガード
# ===========================================================================

class TestSectionAIsWithinRootGuard(_BaseTest):
    """Section A (controller-bloat) must apply _is_within_root() before _count_body_lines()."""

    # --- Scenario: section A でルート外パスをスキップ ---

    def test_section_a_traversal_path_is_silently_skipped(self):
        """WHEN deps.yaml の skills にパストラバーサルを含むパス ('../../etc/passwd') が存在する
        THEN _is_within_root() が False を返し、_count_body_lines() が呼ばれずに continue する
        (controller-bloat WARNING/CRITICAL が出ない; エンジンはエラー終了しない)"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="../../etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" not in result.stdout, (
            f"Expected no controller-bloat for traversal path, got:\n{result.stdout}"
        )
        assert result.returncode == 0, (
            f"Expected returncode 0, got {result.returncode}.\nstderr: {result.stderr}"
        )

    def test_section_a_parent_dir_traversal_is_silently_skipped(self):
        """WHEN deps.yaml の skills に '../outside/SKILL.md' のルート外パスが存在する
        THEN _is_within_root() が False を返し、_count_body_lines() は呼ばれない"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="../outside/SKILL.md",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" not in result.stdout, (
            f"Expected no controller-bloat for parent dir traversal, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_a_absolute_path_is_silently_skipped(self):
        """Edge case: controller path が絶対パス (/tmp/evil.md 等) の場合
        THEN _is_within_root() が False を返し、サイレントスキップされる"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="/tmp/evil.md",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" not in result.stdout, (
            f"Expected no controller-bloat for absolute path, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_a_mid_path_traversal_is_silently_skipped(self):
        """Edge case: 'skills/../../etc/passwd' のような中間ディレクトリ経由のトラバーサル
        THEN _is_within_root() が False を返し、サイレントスキップされる"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="skills/../../etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" not in result.stdout, (
            f"Expected no controller-bloat for mid-path traversal, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    # --- Scenario: section A で正常パスは従来通り処理 ---

    def test_section_a_valid_path_normal_controller_no_bloat_warning(self):
        """WHEN deps.yaml の skills に plugin_root 配下の正常パスがあり行数が少ない
        THEN _is_within_root() が True を返し、従来通り行数チェックが実行され警告は出ない"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="skills/my-controller/SKILL.md",
            create_file=True,
            body_lines_count=10,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" not in result.stdout, (
            f"Expected no bloat warning for short controller, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_a_valid_path_bloated_controller_warns(self):
        """WHEN deps.yaml の skills に plugin_root 配下の正常パスがあり行数が >120 行
        THEN _is_within_root() が True を返し、従来通り [controller-bloat] WARNING が報告される"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="skills/my-controller/SKILL.md",
            create_file=True,
            body_lines_count=150,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" in result.stdout, (
            f"Expected controller-bloat warning for bloated controller, got:\n{result.stdout}"
        )

    def test_section_a_valid_path_critical_bloat_fires(self):
        """Edge case: 正常パスで >200 行のコントローラーは CRITICAL になる"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="skills/my-controller/SKILL.md",
            create_file=True,
            body_lines_count=210,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" in result.stdout, (
            f"Expected CRITICAL controller-bloat for 210-line controller, got:\n{result.stdout}"
        )
        # CRITICAL should cause non-zero exit
        assert result.returncode != 0, (
            f"Expected non-zero exit for CRITICAL controller-bloat, got {result.returncode}"
        )


# ===========================================================================
# Requirement: deep_validate section B ルート外パスガード
# ===========================================================================

class TestSectionBIsWithinRootGuard(_BaseTest):
    """Section B (ref-placement) must apply _is_within_root() before ds_path.exists() / read_text()."""

    def _make_outside_file(self, ref_name: str) -> Path:
        """Create a file outside the plugin root that contains ref_name in its body."""
        outside_dir = self.tmpdir / "outside"
        outside_dir.mkdir(exist_ok=True)
        outside_file = outside_dir / "my-action.md"
        outside_file.write_text(
            f"---\nname: my-action\ndescription: Action\n---\n\nUses {ref_name} in the body.\n",
            encoding="utf-8",
        )
        return outside_file

    # --- Scenario: section B でルート外パスをスキップ ---

    def test_section_b_traversal_path_skips_ref_placement_check(self):
        """WHEN downstream コンポーネントのパスが plugin_root 外を指す (e.g. '../../etc/passwd')
        THEN _is_within_root() が False を返し、ds_path.exists() や read_text() が呼ばれずに continue する
        ([ref-placement] WARNING が出ない; エンジンはエラー終了しない)"""
        plugin_dir = _make_section_b_fixture(
            self.tmpdir,
            downstream_path="../../etc/passwd",
            create_downstream_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[ref-placement]" not in result.stdout, (
            f"Expected no ref-placement for traversal path downstream, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_b_outside_file_traversal_skips_check(self):
        """Edge case: downstream path が '../outside/my-action.md' で実際にルート外ファイルが存在する場合
        THEN _is_within_root() がファイルアクセス前に拒否し、ref-placement チェックはスキップされる"""
        ref_name = "my-ref"
        outside_file = self._make_outside_file(ref_name)
        # Compute relative traversal path from inside plugin_dir to the outside file
        # plugin-section-b is inside tmpdir; outside/ is also inside tmpdir
        # relative: ../outside/my-action.md
        plugin_dir = _make_section_b_fixture(
            self.tmpdir,
            downstream_path="../outside/my-action.md",
            create_downstream_file=False,  # file is already created by _make_outside_file
            ref_name=ref_name,
        )

        result = run_engine(plugin_dir, "--deep-validate")

        assert "[ref-placement]" not in result.stdout, (
            f"Expected no ref-placement when downstream path is outside root (real file exists), got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_b_absolute_path_downstream_is_skipped(self):
        """Edge case: downstream path が絶対パスを指す場合もスキップされる"""
        plugin_dir = _make_section_b_fixture(
            self.tmpdir,
            downstream_path="/tmp/my-action.md",
            create_downstream_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[ref-placement]" not in result.stdout, (
            f"Expected no ref-placement for absolute path downstream, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_b_mid_path_traversal_downstream_is_skipped(self):
        """Edge case: 'commands/../../outside.md' のような中間経由のトラバーサルもスキップされる"""
        plugin_dir = _make_section_b_fixture(
            self.tmpdir,
            downstream_path="commands/../../outside.md",
            create_downstream_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[ref-placement]" not in result.stdout, (
            f"Expected no ref-placement for mid-path traversal downstream, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    # --- Scenario: section B で正常パスは従来通り処理 ---

    def test_section_b_valid_path_no_ref_in_body_no_warning(self):
        """WHEN downstream コンポーネントのパスが plugin_root 配下にあり、body が ref を参照しない
        THEN 従来通り Reference 配置監査が実行され、ref-placement WARNING は出ない"""
        plugin_dir = _make_section_b_fixture(
            self.tmpdir,
            downstream_path="commands/my-action.md",
            create_downstream_file=True,
            downstream_body_contains_ref=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[ref-placement]" not in result.stdout, (
            f"Expected no ref-placement when body does not reference the ref, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_b_valid_path_ref_in_body_warns(self):
        """WHEN downstream コンポーネントのパスが plugin_root 配下にあり、body が ref を参照するが calls に未宣言
        THEN 従来通り [ref-placement] WARNING が発生する (ガードを通過して検証ロジックに到達した証明)"""
        plugin_dir = _make_section_b_fixture(
            self.tmpdir,
            downstream_path="commands/my-action.md",
            create_downstream_file=True,
            downstream_body_contains_ref=True,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[ref-placement]" in result.stdout, (
            f"Expected ref-placement warning when in-root downstream body uses undeclared ref, got:\n{result.stdout}"
        )


# ===========================================================================
# Requirement: deep_validate section C ルート外パスガード
# ===========================================================================

class TestSectionCIsWithinRootGuard(_BaseTest):
    """Section C (tools-mismatch) must apply _is_within_root() before _parse_frontmatter_tools() / _scan_body_for_mcp_tools()."""

    def _make_outside_mcp_file(self) -> Path:
        """Create a file outside the plugin root that has an undeclared mcp tool in body."""
        outside_dir = self.tmpdir / "outside-c"
        outside_dir.mkdir(exist_ok=True)
        outside_file = outside_dir / "my-cmd.md"
        outside_file.write_text(
            "---\nname: my-cmd\ndescription: Test\n---\n\nUse mcp__myserver__mytool here.\n",
            encoding="utf-8",
        )
        return outside_file

    # --- Scenario: section C でルート外パスをスキップ ---

    def test_section_c_traversal_path_skips_tools_check(self):
        """WHEN commands/agents のパスが plugin_root 外を指す ('../../etc/passwd')
        THEN _is_within_root() が False を返し、_parse_frontmatter_tools() や _scan_body_for_mcp_tools() が呼ばれずに continue する
        ([tools-mismatch] WARNING が出ない; エンジンはエラー終了しない)"""
        plugin_dir = _make_section_c_fixture(
            self.tmpdir,
            command_path="../../etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[tools-mismatch]" not in result.stdout, (
            f"Expected no tools-mismatch for traversal path command, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_c_outside_file_traversal_skips_check(self):
        """Edge case: command path が '../outside-c/my-cmd.md' で実際にルート外ファイルが存在する場合
        THEN _is_within_root() がファイルアクセス前に拒否し、tools-mismatch チェックはスキップされる"""
        outside_file = self._make_outside_mcp_file()
        plugin_dir = _make_section_c_fixture(
            self.tmpdir,
            command_path="../outside-c/my-cmd.md",
            create_file=False,  # file is already created by _make_outside_mcp_file
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[tools-mismatch]" not in result.stdout, (
            f"Expected no tools-mismatch when command path is outside root (real file exists), got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_c_absolute_path_command_is_skipped(self):
        """Edge case: command path が絶対パスを指す場合もスキップされる"""
        plugin_dir = _make_section_c_fixture(
            self.tmpdir,
            command_path="/tmp/my-cmd.md",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[tools-mismatch]" not in result.stdout, (
            f"Expected no tools-mismatch for absolute path command, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_c_mid_path_traversal_command_is_skipped(self):
        """Edge case: 'commands/../../outside.md' のような中間経由のトラバーサルもスキップされる"""
        plugin_dir = _make_section_c_fixture(
            self.tmpdir,
            command_path="commands/../../outside.md",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[tools-mismatch]" not in result.stdout, (
            f"Expected no tools-mismatch for mid-path traversal command, got:\n{result.stdout}"
        )
        assert result.returncode == 0

    # --- Scenario: section C で正常パスは従来通り処理 ---

    def test_section_c_valid_path_mcp_tool_not_declared_warns(self):
        """WHEN commands/agents のパスが plugin_root 配下にあり、body が mcp ツールを使うが frontmatter に未宣言
        THEN 従来通り [tools-mismatch] WARNING が発生する (ガードを通過して検証ロジックに到達した証明)"""
        plugin_dir = _make_section_c_fixture(
            self.tmpdir,
            command_path="commands/my-cmd.md",
            create_file=True,
            include_mcp_tool_in_body=True,
            declare_tool_in_frontmatter=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[tools-mismatch]" in result.stdout, (
            f"Expected tools-mismatch warning for in-root command with undeclared mcp tool, got:\n{result.stdout}"
        )

    def test_section_c_valid_path_mcp_tool_declared_no_mismatch(self):
        """WHEN commands/agents のパスが plugin_root 配下にあり、body の mcp ツールが frontmatter に宣言済み
        THEN _is_within_root() が True を返し、tools-mismatch は発生しない"""
        plugin_dir = _make_section_c_fixture(
            self.tmpdir,
            command_path="commands/my-cmd.md",
            create_file=True,
            include_mcp_tool_in_body=True,
            declare_tool_in_frontmatter=True,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[tools-mismatch]" not in result.stdout, (
            f"Expected no tools-mismatch when mcp tool is declared, got:\n{result.stdout}"
        )

    def test_section_c_agent_traversal_path_skips_tools_check(self):
        """Edge case: agents セクションのパスがルート外を指す場合もスキップされる
        (section C は commands と agents の両方をイテレートする)"""
        plugin_dir = self.tmpdir / "plugin-section-c-agent"
        plugin_dir.mkdir(exist_ok=True)

        deps = {
            "version": "3.0",
            "plugin": "test-section-c-agent",
            "skills": {},
            "commands": {},
            "agents": {
                "my-agent": {
                    "type": "specialist",
                    "path": "../../etc/passwd",
                    "description": "Traversal agent",
                    "calls": [],
                    "model": "sonnet",
                    "output_schema": "custom",
                },
            },
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "--deep-validate")

        assert "[tools-mismatch]" not in result.stdout, (
            f"Expected no tools-mismatch for traversal agent path, got:\n{result.stdout}"
        )
        assert result.returncode == 0


# ===========================================================================
# Requirement: section E 回帰なし
# ===========================================================================

class TestSectionERegressionGuard(_BaseTest):
    """Section E's existing _is_within_root() check must not be removed or changed."""

    def _make_section_e_fixture(
        self,
        *,
        specialist_path: str,
        create_file: bool = True,
    ) -> Path:
        plugin_dir = self.tmpdir / "plugin-section-e-regression"
        plugin_dir.mkdir(exist_ok=True)

        agent_spec: dict = {
            "type": "specialist",
            "path": specialist_path,
            "description": "Test specialist",
            "calls": [],
            "model": "sonnet",
        }

        deps = {
            "version": "3.0",
            "plugin": "test-section-e-regression",
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "skills/my-controller/SKILL.md",
                    "description": "Main controller",
                    "calls": [{"specialist": "my-specialist"}],
                },
            },
            "commands": {},
            "agents": {
                "my-specialist": agent_spec,
            },
        }
        _write_deps(plugin_dir, deps)

        ctrl_dir = plugin_dir / "skills" / "my-controller"
        ctrl_dir.mkdir(parents=True, exist_ok=True)
        (ctrl_dir / "SKILL.md").write_text(
            "---\nname: my-controller\ndescription: Controller\n---\n\n## Step 0\nRoute.\n",
            encoding="utf-8",
        )

        if create_file:
            file_path = plugin_dir / specialist_path
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(
                "---\nname: my-specialist\ndescription: Specialist\n---\n\n"
                "## Purpose\nAnalyze code.\n\n"
                "## Output\nReturn PASS or FAIL.\n\n"
                "## Constraint\nMUST NOT skip.\n\n"
                "Report findings with severity and confidence.\n",
                encoding="utf-8",
            )

        return plugin_dir

    # --- Scenario: section E のチェックが維持される ---

    def test_section_e_traversal_specialist_is_silently_skipped(self):
        """WHEN specialist path が '../../etc/passwd' のルート外を指す
        THEN section E の _is_within_root() チェックが発動し、[specialist-output-schema] は出ない"""
        plugin_dir = self._make_section_e_fixture(
            specialist_path="../../etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no schema warning for traversal specialist path (section E regression), got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_section_e_valid_specialist_schema_check_runs(self):
        """WHEN specialist path が plugin_root 配下の正常なパスを指す
        THEN section E の _is_within_root() チェックを通過し、スキーマ検証が実行される
        (キーワードが揃っているため WARNING は出ない)"""
        plugin_dir = self._make_section_e_fixture(
            specialist_path="agents/my-specialist/AGENT.md",
            create_file=True,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no schema warning for valid in-root specialist, got:\n{result.stdout}"
        )

    def test_section_e_check_does_not_break_with_new_guards(self):
        """Edge case: section A/B/C のガード追加後も section E の動作が壊れていないことを確認
        WHEN plugin 全体が正常な構成 (traversal なし、全ファイル存在)
        THEN deep-validate は正常終了し、セクション E を含む全チェックが通る"""
        plugin_dir = self.tmpdir / "plugin-regression-full"
        plugin_dir.mkdir(exist_ok=True)

        deps = {
            "version": "3.0",
            "plugin": "test-regression-full",
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "skills/my-controller/SKILL.md",
                    "description": "Controller",
                    "calls": [{"specialist": "my-specialist"}],
                },
            },
            "commands": {},
            "agents": {
                "my-specialist": {
                    "type": "specialist",
                    "path": "agents/my-specialist/AGENT.md",
                    "description": "Specialist",
                    "calls": [],
                    "model": "sonnet",
                },
            },
        }
        _write_deps(plugin_dir, deps)

        # Controller
        ctrl_dir = plugin_dir / "skills" / "my-controller"
        ctrl_dir.mkdir(parents=True, exist_ok=True)
        (ctrl_dir / "SKILL.md").write_text(
            "---\nname: my-controller\ndescription: Controller\n---\n\n## Step 0\nRoute.\n",
            encoding="utf-8",
        )

        # Specialist with all schema keywords
        spec_dir = plugin_dir / "agents" / "my-specialist"
        spec_dir.mkdir(parents=True, exist_ok=True)
        (spec_dir / "AGENT.md").write_text(
            "---\nname: my-specialist\ndescription: Specialist\n---\n\n"
            "## Purpose\nAnalyze code quality.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "## Constraint\nMUST NOT skip.\n\n"
            "Report findings with severity and confidence scores.\n",
            encoding="utf-8",
        )

        result = run_engine(plugin_dir, "--deep-validate")

        # No schema warning (section E), no bloat (section A), no mismatch (section C)
        assert "[specialist-output-schema]" not in result.stdout, (
            f"Section E regression: unexpected schema warning, got:\n{result.stdout}"
        )
        assert "[controller-bloat]" not in result.stdout, (
            f"Section A regression: unexpected bloat warning, got:\n{result.stdout}"
        )
        assert "[tools-mismatch]" not in result.stdout, (
            f"Section C regression: unexpected tools-mismatch, got:\n{result.stdout}"
        )
        assert result.returncode == 0


# ===========================================================================
# Cross-section edge cases
# ===========================================================================

class TestCrossSectionEdgeCases(_BaseTest):
    """Edge cases spanning multiple sections: multiple traversal paths, empty path, etc."""

    def test_multiple_traversal_paths_all_sections_no_errors(self):
        """Edge case: sections A, B, C の全てにトラバーサルパスが存在する場合
        THEN 全てがサイレントスキップされ、エンジンはエラー終了しない"""
        plugin_dir = self.tmpdir / "plugin-multi-traversal"
        plugin_dir.mkdir(exist_ok=True)

        # reference type must live in skills (TYPE_RULES constraint)
        deps = {
            "version": "3.0",
            "plugin": "test-multi-traversal",
            "skills": {
                "evil-controller": {
                    "type": "controller",
                    "path": "../../etc/passwd",           # Section A traversal
                    "description": "Traversal controller",
                    "calls": [{"atomic": "evil-cmd"}, {"reference": "evil-ref"}],
                },
                "evil-ref": {
                    "type": "reference",
                    "path": "skills/evil-ref/SKILL.md",
                    "description": "Reference",
                    "calls": [],
                },
            },
            "commands": {
                "evil-cmd": {
                    "type": "atomic",
                    "path": "../outside/cmd.md",          # Section B downstream traversal
                    "description": "Traversal command",
                    "calls": [],
                },
                "evil-cmd-c": {
                    "type": "atomic",
                    "path": "../../etc/shadow",           # Section C traversal
                    "description": "Traversal C command",
                    "calls": [],
                },
            },
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        # Create only the reference file (everything else is outside root)
        ref_skill_dir = plugin_dir / "skills" / "evil-ref"
        ref_skill_dir.mkdir(parents=True, exist_ok=True)
        (ref_skill_dir / "SKILL.md").write_text(
            "---\nname: evil-ref\ndescription: Ref\n---\n\nRef content.\n",
            encoding="utf-8",
        )

        result = run_engine(plugin_dir, "--deep-validate")

        assert "[controller-bloat]" not in result.stdout
        assert "[ref-placement]" not in result.stdout
        assert "[tools-mismatch]" not in result.stdout
        assert result.returncode == 0, (
            f"Expected returncode 0 for multi-traversal scenario, got {result.returncode}.\nstderr: {result.stderr}"
        )

    def test_empty_path_does_not_crash(self):
        """Edge case: path が空文字列の場合、plugin_root / '' はルート自体になり
        _is_within_root() の挙動を確認する。クラッシュしないこと。"""
        plugin_dir = self.tmpdir / "plugin-empty-path"
        plugin_dir.mkdir(exist_ok=True)

        deps = {
            "version": "3.0",
            "plugin": "test-empty-path",
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "",  # empty path
                    "description": "Controller with empty path",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "--deep-validate")

        # Should not crash
        assert result.returncode == 0 or result.returncode == 1, (
            f"Unexpected returncode {result.returncode} for empty path. stderr: {result.stderr}"
        )
        # Should not raise unhandled exception
        assert "Traceback" not in result.stderr, (
            f"Unexpected traceback for empty path:\n{result.stderr}"
        )
        # Empty path should be skipped, not processed as controller-bloat
        assert "[controller-bloat]" not in result.stdout, (
            f"Empty path should not trigger controller-bloat check:\n{result.stdout}"
        )

    def test_traversal_path_does_not_emit_security_error_message(self):
        """Edge case: トラバーサルパス検出時に 'traversal', 'outside', 'security' 等の
        エラーメッセージを出力しないこと（サイレントスキップ）"""
        plugin_dir = _make_section_a_fixture(
            self.tmpdir,
            controller_path="../../etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        for keyword in ("traversal", "outside root", "path escape", "security"):
            assert keyword not in result.stdout.lower(), (
                f"Expected no '{keyword}' in output but found it:\n{result.stdout}"
            )


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestSectionAIsWithinRootGuard,
        TestSectionBIsWithinRootGuard,
        TestSectionCIsWithinRootGuard,
        TestSectionERegressionGuard,
        TestCrossSectionEdgeCases,
    ]
    passed = 0
    failed = 0
    errors = []

    for cls in classes:
        for method_name in sorted(dir(cls)):
            if not method_name.startswith("test_"):
                continue
            instance = cls()
            try:
                instance.setup_method()
                getattr(instance, method_name)()
                passed += 1
                print(f"  PASS: {cls.__name__}.{method_name}")
            except Exception as e:
                failed += 1
                errors.append((f"{cls.__name__}.{method_name}", e))
                print(f"  FAIL: {cls.__name__}.{method_name}: {e}")
                traceback.print_exc()
            finally:
                instance.teardown_method()

    print(f"\n{'=' * 40}")
    print(f"Results: {passed} passed, {failed} failed")
    if errors:
        print("\nFailures:")
        for name, err in errors:
            print(f"  {name}: {err}")
        sys.exit(1)
    else:
        print("All tests passed!")
