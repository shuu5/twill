#!/usr/bin/env python3
"""Tests for audit_report Section 8: Prompt Compliance.

Covers:
- refined_by 未設定コンポーネント → INFO 行
- refined_by 設定済み + hash 一致 → OK 行
- refined_by 設定済み + hash 不一致（stale）→ WARNING 行
- Section 8 ヘッダーフォーマット
- ref-prompt-guide.md 変更時に stale 検出
"""

import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

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


def _create_component_file(plugin_dir: Path, path_str: str, name: str) -> None:
    file_path = plugin_dir / path_str
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text(
        f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
        encoding="utf-8",
    )


def _write_ref_prompt_guide(plugin_dir: Path, content: str = "ref-prompt-guide content") -> str:
    """Write a ref-prompt-guide.md and return its SHA-1[:8]."""
    refs_dir = plugin_dir / "refs"
    refs_dir.mkdir(parents=True, exist_ok=True)
    ref_path = refs_dir / "ref-prompt-guide.md"
    ref_path.write_bytes(content.encode("utf-8"))
    return hashlib.sha1(content.encode("utf-8")).hexdigest()[:8]


def make_fixture(tmpdir: Path, components: dict | None = None) -> Path:
    """Create a minimal plugin fixture.

    Args:
        components: dict of name -> {"path": str, "type": str, "refined_by": str|None}
    """
    plugin_dir = tmpdir / "test-plugin-compliance"
    plugin_dir.mkdir()

    if components is None:
        components = {"my-specialist": {"path": "agents/my-specialist.md", "type": "specialist"}}

    agents = {}
    calls = []
    for name, cfg in components.items():
        agent_data: dict = {
            "type": cfg.get("type", "specialist"),
            "path": cfg["path"],
            "description": f"Component {name}",
            "calls": [],
        }
        if "refined_by" in cfg:
            agent_data["refined_by"] = cfg["refined_by"]
        if "refined_at" in cfg:
            agent_data["refined_at"] = cfg["refined_at"]
        agents[name] = agent_data
        calls.append({"specialist": name})

    deps = {
        "version": "3.0",
        "plugin": "test-compliance",
        "chains": {},
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": calls,
            },
        },
        "commands": {},
        "agents": agents,
    }
    _write_deps(plugin_dir, deps)

    # Create component files
    _create_component_file(plugin_dir, "skills/my-controller/SKILL.md", "my-controller")
    for name, cfg in components.items():
        _create_component_file(plugin_dir, cfg["path"], name)

    return plugin_dir


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Test base
# ---------------------------------------------------------------------------

class _ComplianceTestBase:
    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run_audit(self) -> str:
        result = run_engine(self.plugin_dir, "--audit")
        return result.stdout

    def _get_section8_lines(self) -> list[str]:
        output = self._run_audit()
        lines = output.splitlines()
        in_section = False
        section_lines = []
        for line in lines:
            if "## 8. Prompt Compliance" in line:
                in_section = True
                section_lines.append(line)
                continue
            if in_section:
                if line.startswith("## ") and "8." not in line:
                    break
                section_lines.append(line)
        return section_lines


# ===========================================================================
# Section 8 header format
# ===========================================================================

class TestSection8Header(_ComplianceTestBase):
    """Section 8 has correct header and table format."""

    def test_section_header_present(self):
        """audit output contains '## 8. Prompt Compliance'."""
        output = self._run_audit()
        assert "## 8. Prompt Compliance" in output

    def test_table_header_format(self):
        """Table header is '| Component | Status | Severity |'."""
        lines = self._get_section8_lines()
        found = False
        for line in lines:
            if "Component" in line and "Status" in line and "Severity" in line:
                assert line.strip().startswith("|"), f"Expected table format: {line}"
                assert line.strip().endswith("|"), f"Expected table format: {line}"
                found = True
                break
        assert found, f"Section 8 table header not found. Lines: {lines}"


# ===========================================================================
# refined_by 未設定 → INFO
# ===========================================================================

class TestUnreviewed(_ComplianceTestBase):
    """refined_by 未設定コンポーネントは INFO."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_fixture(
            self.tmpdir,
            components={"my-specialist": {"path": "agents/my-specialist.md", "type": "specialist"}},
        )

    def test_unreviewed_shows_info(self):
        """WHEN refined_by not set THEN row shows INFO severity."""
        lines = self._get_section8_lines()
        for line in lines:
            if "my-specialist" in line:
                assert "INFO" in line, f"Expected INFO for unreviewed: {line}"
                return
        assert False, f"my-specialist not found in section 8: {lines}"


# ===========================================================================
# refined_by 設定済み + hash 一致 → OK
# ===========================================================================

class TestReviewedUpToDate(_ComplianceTestBase):
    """refined_by 設定済みかつ hash 一致は OK."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_fixture(self.tmpdir)
        # Write ref-prompt-guide and get its hash
        self.current_hash = _write_ref_prompt_guide(self.plugin_dir)
        # Set refined_by to matching hash
        deps = _load_deps(self.plugin_dir)
        deps["agents"]["my-specialist"]["refined_by"] = f"ref-prompt-guide@{self.current_hash}"
        _write_deps(self.plugin_dir, deps)

    def test_up_to_date_shows_ok(self):
        """WHEN refined_by matches current hash THEN row shows OK severity."""
        lines = self._get_section8_lines()
        for line in lines:
            if "my-specialist" in line:
                assert "OK" in line, f"Expected OK for up-to-date: {line}"
                return
        assert False, f"my-specialist not found in section 8: {lines}"


# ===========================================================================
# refined_by 設定済み + hash 不一致 → WARNING (stale)
# ===========================================================================

class TestStaleDetection(_ComplianceTestBase):
    """ref-prompt-guide.md が変更されると stale が検出される。"""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_fixture(self.tmpdir)
        # Write ref-prompt-guide with OLD content, record hash
        old_hash = _write_ref_prompt_guide(self.plugin_dir, content="old content")
        # Set refined_by to old hash
        deps = _load_deps(self.plugin_dir)
        deps["agents"]["my-specialist"]["refined_by"] = f"ref-prompt-guide@{old_hash}"
        _write_deps(self.plugin_dir, deps)
        # Now overwrite ref-prompt-guide with NEW content
        _write_ref_prompt_guide(self.plugin_dir, content="new content that changed")

    def test_stale_shows_warning(self):
        """WHEN ref-prompt-guide has changed THEN row shows WARNING (stale)."""
        lines = self._get_section8_lines()
        for line in lines:
            if "my-specialist" in line:
                assert "WARNING" in line, f"Expected WARNING for stale: {line}"
                return
        assert False, f"my-specialist not found in section 8: {lines}"

    def test_stale_message_contains_stale(self):
        """Stale row message contains 'stale'."""
        lines = self._get_section8_lines()
        for line in lines:
            if "my-specialist" in line and "WARNING" in line:
                assert "stale" in line.lower(), f"Expected 'stale' in message: {line}"
                return
        assert False, f"Stale row not found in section 8: {lines}"


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestSection8Header,
        TestUnreviewed,
        TestReviewedUpToDate,
        TestStaleDetection,
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

    print(f"\n{'=' * 40}")
    print(f"Results: {passed} passed, {failed} failed")
    if errors:
        print("\nFailures:")
        for name, err in errors:
            print(f"  {name}: {err}")
        sys.exit(1)
    else:
        print("All tests passed!")
