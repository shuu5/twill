"""BDD scenario tests for issue-461: test_merge_gate_phase_review.py file split.

Covers:
  Requirement: テストファイル分割
    - test_phase_review_checkpoint.py が作成される
    - test_phase_review_guard.py が作成される
    - test_merge_gate_integration.py が作成される
    - 元ファイルが削除される

  Requirement: 共通 fixture の conftest.py 移動
    - fixture が conftest.py で定義される

  Requirement: CI 設定の更新
    - CI で特定ファイルが参照されている場合に更新される

spec: deltaspec/changes/issue-461/specs/file-split/spec.md
"""

from __future__ import annotations

import ast
import re
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_AUTOPILOT_TEST_DIR = (
    Path(__file__).resolve().parent.parent / "autopilot"
)
_CONFTEST = _AUTOPILOT_TEST_DIR / "conftest.py"
_ORIGINAL_FILE = _AUTOPILOT_TEST_DIR / "test_merge_gate_phase_review.py"


def _class_names_in_file(path: Path) -> list[str]:
    """Return top-level class names defined in *path* via AST parsing."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    return [node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)]


def _function_names_in_file(path: Path) -> list[str]:
    """Return top-level and method-level function names in *path*."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    return [node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]


def _fixture_names_in_conftest(path: Path) -> list[str]:
    """Return names of pytest fixtures defined in *path*."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    fixtures = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for deco in node.decorator_list:
                # match @pytest.fixture or @pytest.fixture(...)
                if isinstance(deco, ast.Attribute) and deco.attr == "fixture":
                    fixtures.append(node.name)
                elif isinstance(deco, ast.Call):
                    func = deco.func
                    if isinstance(func, ast.Attribute) and func.attr == "fixture":
                        fixtures.append(node.name)
    return fixtures


# ---------------------------------------------------------------------------
# Requirement: テストファイル分割
# ---------------------------------------------------------------------------


class TestFilesSplitCreated:
    """
    Scenario: test_phase_review_checkpoint.py が作成される
    WHEN: 分割作業が完了する
    THEN: test_phase_review_checkpoint.py が存在し、
          TestPhaseReviewCheckpointPresence を含む

    Scenario: test_phase_review_guard.py が作成される
    WHEN: 分割作業が完了する
    THEN: test_phase_review_guard.py が存在し、
          TestPhaseReviewCriticalFindings と TestPhaseReviewForceWarning を含む

    Scenario: test_merge_gate_integration.py が作成される
    WHEN: 分割作業が完了する
    THEN: test_merge_gate_integration.py が存在し、
          TestMergeGateExecuteIntegration を含む
    """

    def test_phase_review_checkpoint_file_exists(self) -> None:
        """test_phase_review_checkpoint.py が autopilot/ ディレクトリに存在する。"""
        target = _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py"
        assert target.exists(), (
            f"Expected split file not found: {target}\n"
            "Run the split task (issue-461) to create the file."
        )

    def test_phase_review_checkpoint_contains_presence_class(self) -> None:
        """test_phase_review_checkpoint.py に TestPhaseReviewCheckpointPresence が含まれる。"""
        target = _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py"
        if not target.exists():
            pytest.skip(f"File not yet created: {target.name}")

        classes = _class_names_in_file(target)
        assert "TestPhaseReviewCheckpointPresence" in classes, (
            f"Class TestPhaseReviewCheckpointPresence not found in {target.name}. "
            f"Found classes: {classes}"
        )

    def test_phase_review_checkpoint_under_500_lines(self) -> None:
        """分割ファイルは 500 行未満でなければならない（SHALL）。"""
        target = _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py"
        if not target.exists():
            pytest.skip(f"File not yet created: {target.name}")

        line_count = len(target.read_text(encoding="utf-8").splitlines())
        assert line_count < 500, (
            f"{target.name} has {line_count} lines; must be < 500 after split."
        )

    def test_phase_review_guard_file_exists(self) -> None:
        """test_phase_review_guard.py が autopilot/ ディレクトリに存在する。"""
        target = _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py"
        assert target.exists(), (
            f"Expected split file not found: {target}\n"
            "Run the split task (issue-461) to create the file."
        )

    def test_phase_review_guard_contains_critical_findings_class(self) -> None:
        """test_phase_review_guard.py に TestPhaseReviewCriticalFindings が含まれる。"""
        target = _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py"
        if not target.exists():
            pytest.skip(f"File not yet created: {target.name}")

        classes = _class_names_in_file(target)
        assert "TestPhaseReviewCriticalFindings" in classes, (
            f"Class TestPhaseReviewCriticalFindings not found in {target.name}. "
            f"Found classes: {classes}"
        )

    def test_phase_review_guard_contains_force_warning_class(self) -> None:
        """test_phase_review_guard.py に TestPhaseReviewForceWarning が含まれる。"""
        target = _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py"
        if not target.exists():
            pytest.skip(f"File not yet created: {target.name}")

        classes = _class_names_in_file(target)
        assert "TestPhaseReviewForceWarning" in classes, (
            f"Class TestPhaseReviewForceWarning not found in {target.name}. "
            f"Found classes: {classes}"
        )

    def test_phase_review_guard_under_500_lines(self) -> None:
        """分割ファイルは 500 行未満でなければならない（SHALL）。"""
        target = _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py"
        if not target.exists():
            pytest.skip(f"File not yet created: {target.name}")

        line_count = len(target.read_text(encoding="utf-8").splitlines())
        assert line_count < 500, (
            f"{target.name} has {line_count} lines; must be < 500 after split."
        )

    def test_merge_gate_integration_file_exists(self) -> None:
        """test_merge_gate_integration.py が autopilot/ ディレクトリに存在する。"""
        target = _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py"
        assert target.exists(), (
            f"Expected split file not found: {target}\n"
            "Run the split task (issue-461) to create the file."
        )

    def test_merge_gate_integration_contains_execute_integration_class(self) -> None:
        """test_merge_gate_integration.py に TestMergeGateExecuteIntegration が含まれる。"""
        target = _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py"
        if not target.exists():
            pytest.skip(f"File not yet created: {target.name}")

        classes = _class_names_in_file(target)
        assert "TestMergeGateExecuteIntegration" in classes, (
            f"Class TestMergeGateExecuteIntegration not found in {target.name}. "
            f"Found classes: {classes}"
        )

    def test_merge_gate_integration_under_500_lines(self) -> None:
        """分割ファイルは 500 行未満でなければならない（SHALL）。"""
        target = _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py"
        if not target.exists():
            pytest.skip(f"File not yet created: {target.name}")

        line_count = len(target.read_text(encoding="utf-8").splitlines())
        assert line_count < 500, (
            f"{target.name} has {line_count} lines; must be < 500 after split."
        )

    # Edge case: no class duplication across split files
    def test_no_duplicate_class_names_across_split_files(self) -> None:
        """各分割ファイルに同名クラスが重複して定義されていない。"""
        split_files = [
            _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py",
            _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py",
            _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py",
        ]
        existing = [f for f in split_files if f.exists()]
        if not existing:
            pytest.skip("No split files exist yet.")

        seen: dict[str, str] = {}
        for path in existing:
            for cls in _class_names_in_file(path):
                if cls in seen:
                    pytest.fail(
                        f"Class '{cls}' found in both {seen[cls]} and {path.name}. "
                        "Each class must appear in exactly one split file."
                    )
                seen[cls] = path.name


class TestOriginalFileDeleted:
    """
    Scenario: 元ファイルが削除される
    WHEN: 分割作業が完了する
    THEN: test_merge_gate_phase_review.py が存在しない
    """

    def test_original_file_does_not_exist(self) -> None:
        """分割完了後、test_merge_gate_phase_review.py は存在しない。"""
        assert not _ORIGINAL_FILE.exists(), (
            f"Original file still exists at: {_ORIGINAL_FILE}\n"
            "Delete it after all classes have been moved to the split files."
        )

    # Edge case: ensure no stale __pycache__ entry misleads the check
    def test_original_file_not_present_as_pyc(self) -> None:
        """コンパイル済み .pyc キャッシュが残っていても元の .py は存在しない。"""
        assert not _ORIGINAL_FILE.exists(), (
            f"Original .py file must be deleted: {_ORIGINAL_FILE}"
        )
        # The .pyc existence is acceptable but the source .py must be gone
        pyc_pattern = (
            _AUTOPILOT_TEST_DIR
            / "__pycache__"
            / "test_merge_gate_phase_review.cpython-*.pyc"
        )
        # Just confirm source is gone; .pyc cleanup is optional
        assert not _ORIGINAL_FILE.with_suffix(".py").exists()


# ---------------------------------------------------------------------------
# Requirement: 共通 fixture の conftest.py 移動
# ---------------------------------------------------------------------------


class TestFixturesInConftest:
    """
    Scenario: fixture が conftest.py で定義される
    WHEN: 分割後に pytest <any_split_file> を単体実行する
    THEN: fixture が解決され、テストが PASS する
    """

    _REQUIRED_FIXTURES = [
        "autopilot_dir",
        "scripts_root",
        "gate",
        "gate_force",
    ]
    _REQUIRED_HELPERS = [
        "_phase_review_json",
        "_write_phase_review",
    ]

    def test_conftest_exists_in_autopilot_dir(self) -> None:
        """autopilot/ ディレクトリに conftest.py が存在する。"""
        assert _CONFTEST.exists(), (
            f"conftest.py not found at: {_CONFTEST}\n"
            "Create conftest.py with shared fixtures in the autopilot test directory."
        )

    def test_autopilot_dir_fixture_in_conftest(self) -> None:
        """conftest.py に autopilot_dir fixture が定義されている。"""
        if not _CONFTEST.exists():
            pytest.skip("conftest.py not yet created.")

        fixtures = _fixture_names_in_conftest(_CONFTEST)
        assert "autopilot_dir" in fixtures, (
            f"Fixture 'autopilot_dir' not found in conftest.py. "
            f"Defined fixtures: {fixtures}"
        )

    def test_scripts_root_fixture_in_conftest(self) -> None:
        """conftest.py に scripts_root fixture が定義されている。"""
        if not _CONFTEST.exists():
            pytest.skip("conftest.py not yet created.")

        fixtures = _fixture_names_in_conftest(_CONFTEST)
        assert "scripts_root" in fixtures, (
            f"Fixture 'scripts_root' not found in conftest.py. "
            f"Defined fixtures: {fixtures}"
        )

    def test_gate_fixture_in_conftest(self) -> None:
        """conftest.py に gate fixture が定義されている。"""
        if not _CONFTEST.exists():
            pytest.skip("conftest.py not yet created.")

        fixtures = _fixture_names_in_conftest(_CONFTEST)
        assert "gate" in fixtures, (
            f"Fixture 'gate' not found in conftest.py. "
            f"Defined fixtures: {fixtures}"
        )

    def test_gate_force_fixture_in_conftest(self) -> None:
        """conftest.py に gate_force fixture が定義されている。"""
        if not _CONFTEST.exists():
            pytest.skip("conftest.py not yet created.")

        fixtures = _fixture_names_in_conftest(_CONFTEST)
        assert "gate_force" in fixtures, (
            f"Fixture 'gate_force' not found in conftest.py. "
            f"Defined fixtures: {fixtures}"
        )

    def test_helper_functions_in_conftest(self) -> None:
        """conftest.py にヘルパー関数 _phase_review_json と _write_phase_review が定義されている。"""
        if not _CONFTEST.exists():
            pytest.skip("conftest.py not yet created.")

        functions = _function_names_in_file(_CONFTEST)
        for helper in self._REQUIRED_HELPERS:
            assert helper in functions, (
                f"Helper function '{helper}' not found in conftest.py. "
                f"Defined functions: {functions}"
            )

    # Edge case: fixtures not duplicated in split test files
    def test_fixtures_not_redefined_in_split_files(self) -> None:
        """共通 fixture は分割ファイルに再定義されていない（conftest.py が唯一の定義元）。"""
        split_files = [
            _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py",
            _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py",
            _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py",
        ]
        existing = [f for f in split_files if f.exists()]
        if not existing:
            pytest.skip("No split files exist yet.")

        for path in existing:
            redefined = _fixture_names_in_conftest(path)
            duplicate = [f for f in redefined if f in self._REQUIRED_FIXTURES]
            assert not duplicate, (
                f"Fixtures {duplicate} are redefined in {path.name}. "
                "They should only be defined in conftest.py."
            )


# ---------------------------------------------------------------------------
# Requirement: CI 設定の更新
# ---------------------------------------------------------------------------


class TestCIConfigUpdated:
    """
    Scenario: CI で特定ファイルが参照されている場合に更新される
    WHEN: pyproject.toml または CI 設定ファイルが test_merge_gate_phase_review.py を参照している
    THEN: 参照が削除または適切に置換される
    """

    _PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
    _PYPROJECT = _PROJECT_ROOT / "pyproject.toml"
    _CI_DIRS = [
        _PROJECT_ROOT / ".github",
        _PROJECT_ROOT / "scripts",
    ]
    _OLD_FILENAME = "test_merge_gate_phase_review.py"

    def _find_references(self, path: Path) -> list[tuple[Path, int, str]]:
        """Return (file, line_number, line_text) for all references to the old filename."""
        refs = []
        if path.is_file():
            for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if self._OLD_FILENAME in line:
                    refs.append((path, i, line.strip()))
        elif path.is_dir():
            for child in path.rglob("*"):
                if child.is_file():
                    refs.extend(self._find_references(child))
        return refs

    def test_pyproject_toml_has_no_old_filename_reference(self) -> None:
        """pyproject.toml が test_merge_gate_phase_review.py を参照していない。"""
        if not self._PYPROJECT.exists():
            pytest.skip(f"pyproject.toml not found at: {self._PYPROJECT}")

        refs = self._find_references(self._PYPROJECT)
        assert not refs, (
            f"pyproject.toml still references {self._OLD_FILENAME}:\n"
            + "\n".join(f"  line {ln}: {text}" for _, ln, text in refs)
        )

    def test_ci_configs_have_no_old_filename_reference(self) -> None:
        """CI 設定ファイル（.github/, scripts/）が test_merge_gate_phase_review.py を参照していない。"""
        all_refs = []
        for ci_dir in self._CI_DIRS:
            if ci_dir.exists():
                all_refs.extend(self._find_references(ci_dir))

        assert not all_refs, (
            f"CI configuration files still reference {self._OLD_FILENAME}:\n"
            + "\n".join(
                f"  {path}:{ln}: {text}" for path, ln, text in all_refs
            )
        )

    # Edge case: ensure replacement is valid (not just blank line)
    def test_pyproject_toml_is_valid_toml_after_update(self) -> None:
        """pyproject.toml が TOML として正しく解析できる（更新後に壊れていない）。"""
        if not self._PYPROJECT.exists():
            pytest.skip(f"pyproject.toml not found at: {self._PYPROJECT}")

        try:
            import tomllib  # Python 3.11+
        except ImportError:
            try:
                import tomli as tomllib  # type: ignore[no-redef]
            except ImportError:
                pytest.skip("tomllib/tomli not available; skipping TOML parse check.")

        content = self._PYPROJECT.read_bytes()
        try:
            tomllib.loads(content.decode("utf-8"))
        except Exception as exc:
            pytest.fail(f"pyproject.toml is not valid TOML after update: {exc}")
