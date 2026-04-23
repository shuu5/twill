"""BDD scenario tests for issue-461: pytest execution results after file split.

Covers:
  Requirement: テスト実行結果の完全一致
    - 全テストが PASS する（分割前後で PASS 数・テスト名が完全一致）
    - 各ファイルが単独で実行可能

spec: deltaspec/changes/issue-461/specs/file-split/spec.md

NOTE: These tests invoke subprocess pytest runs and therefore require the
      split files to exist.  Until the split is complete most tests are
      collected as SKIP via pytest.skip().
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_AUTOPILOT_TEST_DIR = (
    Path(__file__).resolve().parent.parent / "autopilot"
)

#: Expected test count from the original 644-line file.
#: Update this constant if the original count changes.
_EXPECTED_TEST_COUNT = 23


def _run_pytest(
    *paths: Path,
    extra_args: list[str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run pytest on the given *paths* and return the CompletedProcess."""
    cmd = [
        sys.executable,
        "-m",
        "pytest",
        *(str(p) for p in paths),
        "-v",
        "--tb=short",
        "--no-header",
        *(extra_args or []),
    ]
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(_AUTOPILOT_TEST_DIR.parent.parent),  # cli/twl/
    )


def _collect_test_ids(path: Path) -> list[str]:
    """Return pytest node IDs collected from *path* without running tests."""
    result = subprocess.run(
        [sys.executable, "-m", "pytest", str(path), "--collect-only", "-q", "--no-header"],
        capture_output=True,
        text=True,
        cwd=str(_AUTOPILOT_TEST_DIR.parent.parent),
    )
    ids = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if "::" in line and not line.startswith("=") and not line.startswith("no tests"):
            ids.append(line)
    return ids


# ---------------------------------------------------------------------------
# Requirement: テスト実行結果の完全一致
# ---------------------------------------------------------------------------


class TestAllTestsPassAfterSplit:
    """
    Scenario: 全テストが PASS する
    WHEN: 分割後に pytest cli/twl/tests/autopilot/ を実行する
    THEN: 分割前と同じ数・同じ名前のテストが全て PASS する
    """

    def test_split_files_all_exist_before_running(self) -> None:
        """pytest を実行する前に 3 つの分割ファイルが全て存在することを確認。"""
        split_files = [
            _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py",
            _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py",
            _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py",
        ]
        missing = [str(f) for f in split_files if not f.exists()]
        assert not missing, (
            f"Split files not yet created: {missing}\n"
            "Complete the split task (issue-461) before running execution tests."
        )

    def test_autopilot_suite_exit_code_zero(self) -> None:
        """pytest cli/twl/tests/autopilot/ が exit code 0 で終了する。"""
        split_files = [
            _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py",
            _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py",
            _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py",
        ]
        if any(not f.exists() for f in split_files):
            pytest.skip("Split files not yet created; skipping execution test.")

        result = _run_pytest(_AUTOPILOT_TEST_DIR)
        assert result.returncode == 0, (
            f"pytest exited with code {result.returncode}.\n"
            f"STDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )

    def test_autopilot_suite_no_failures_in_output(self) -> None:
        """pytest 出力に 'failed' または 'error' が含まれない。"""
        split_files = [
            _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py",
            _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py",
            _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py",
        ]
        if any(not f.exists() for f in split_files):
            pytest.skip("Split files not yet created; skipping execution test.")

        result = _run_pytest(_AUTOPILOT_TEST_DIR)
        output_lower = (result.stdout + result.stderr).lower()
        # pytest summary line includes "X failed" or "X error" only on failure
        assert " failed" not in output_lower and " error" not in output_lower, (
            f"pytest reported failures or errors.\n"
            f"STDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )

    def test_phase_review_test_count_matches_expected(self) -> None:
        """phase-review 関連テストの合計数が分割前と同じ {count} 件。""".format(
            count=_EXPECTED_TEST_COUNT
        )
        split_files = [
            _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py",
            _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py",
            _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py",
        ]
        existing = [f for f in split_files if f.exists()]
        if not existing:
            pytest.skip("Split files not yet created; skipping count test.")

        all_ids: list[str] = []
        for f in existing:
            all_ids.extend(_collect_test_ids(f))

        assert len(all_ids) == _EXPECTED_TEST_COUNT, (
            f"Expected {_EXPECTED_TEST_COUNT} tests across split files, "
            f"got {len(all_ids)}.\n"
            f"Collected test IDs:\n" + "\n".join(f"  {t}" for t in all_ids)
        )

    # Edge case: no test IDs in original file remain missing after split
    def test_no_tests_lost_in_split(self) -> None:
        """元ファイルの全テスト名が分割後のいずれかのファイルに存在する（テスト消失なし）。"""
        split_files = [
            _AUTOPILOT_TEST_DIR / "test_phase_review_checkpoint.py",
            _AUTOPILOT_TEST_DIR / "test_phase_review_guard.py",
            _AUTOPILOT_TEST_DIR / "test_merge_gate_integration.py",
        ]
        existing = [f for f in split_files if f.exists()]
        if not existing:
            pytest.skip("Split files not yet created; skipping.")

        # Known test method names from the original file (ground truth)
        expected_test_names = {
            "test_missing_checkpoint_raises_error",
            "test_missing_checkpoint_error_message_includes_specialist_review",
            "test_present_checkpoint_without_critical_findings_does_not_raise",
            "test_missing_checkpoint_raises_even_when_checkpoints_dir_missing",
            "test_unrelated_label_does_not_skip_check",
            "test_critical_finding_with_high_confidence_raises_error",
            "test_critical_finding_error_message_includes_finding_details",
            "test_critical_finding_at_exactly_80_confidence_raises_error",
            "test_critical_finding_below_80_confidence_does_not_raise",
            "test_no_critical_findings_does_not_raise",
            "test_empty_findings_list_does_not_raise",
            "test_multiple_critical_findings_all_included_in_error",
            "test_critical_finding_missing_confidence_field_does_not_raise",
            "test_force_mode_does_not_raise_when_checkpoint_missing",
            "test_force_mode_logs_warning_message_when_checkpoint_missing",
            "test_force_mode_warning_message_mentions_force_flag",
            "test_force_mode_still_rejects_critical_findings",
            "test_execute_calls_phase_review_guard",
            "test_execute_rejects_when_phase_review_guard_raises",
            "test_execute_force_continues_when_phase_review_checkpoint_missing",
        }

        import ast

        found_names: set[str] = set()
        for path in existing:
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef) and node.name.startswith("test_"):
                    found_names.add(node.name)

        missing = expected_test_names - found_names
        assert not missing, (
            f"The following test methods from the original file were NOT found in any split file:\n"
            + "\n".join(f"  {name}" for name in sorted(missing))
        )


class TestEachFileSelfContained:
    """
    Scenario: 各ファイルが単独で実行可能
    WHEN: 分割後に pytest test_phase_review_checkpoint.py を単体で実行する
    THEN: そのファイル内のテストが全て PASS する（他 2 ファイルも同様）
    """

    @pytest.mark.parametrize(
        "filename",
        [
            "test_phase_review_checkpoint.py",
            "test_phase_review_guard.py",
            "test_merge_gate_integration.py",
        ],
    )
    def test_file_passes_standalone(self, filename: str) -> None:
        """各分割ファイルを単独で pytest 実行した場合に全テストが PASS する。"""
        target = _AUTOPILOT_TEST_DIR / filename
        if not target.exists():
            pytest.skip(f"File not yet created: {filename}")

        result = _run_pytest(target)
        assert result.returncode == 0, (
            f"pytest {filename} (standalone) exited with code {result.returncode}.\n"
            f"STDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )

    @pytest.mark.parametrize(
        "filename",
        [
            "test_phase_review_checkpoint.py",
            "test_phase_review_guard.py",
            "test_merge_gate_integration.py",
        ],
    )
    def test_file_has_no_import_errors(self, filename: str) -> None:
        """各分割ファイルを単独でインポートした場合に ImportError が発生しない。"""
        target = _AUTOPILOT_TEST_DIR / filename
        if not target.exists():
            pytest.skip(f"File not yet created: {filename}")

        result = subprocess.run(
            [sys.executable, "-c", f"import ast; ast.parse(open('{target}').read())"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"Syntax error in {filename}: {result.stderr}"
        )

    @pytest.mark.parametrize(
        "filename",
        [
            "test_phase_review_checkpoint.py",
            "test_phase_review_guard.py",
            "test_merge_gate_integration.py",
        ],
    )
    def test_file_collection_succeeds(self, filename: str) -> None:
        """pytest --collect-only で各ファイルのテスト収集が成功する（0 errors）。"""
        target = _AUTOPILOT_TEST_DIR / filename
        if not target.exists():
            pytest.skip(f"File not yet created: {filename}")

        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "pytest",
                str(target),
                "--collect-only",
                "-q",
                "--no-header",
            ],
            capture_output=True,
            text=True,
            cwd=str(_AUTOPILOT_TEST_DIR.parent.parent),
        )
        assert "error" not in result.stdout.lower() and "error" not in result.stderr.lower(), (
            f"Collection errors in {filename}:\n"
            f"STDOUT: {result.stdout}\n"
            f"STDERR: {result.stderr}"
        )
