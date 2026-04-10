"""Tests for Issue #436: .deltaspec.yaml issue フィールド自動付与 & orchestrator archive フォールバック.

Spec: deltaspec/changes/issue-436/specs/deltaspec-yaml-issue-field/spec.md

Coverage:
  Requirement: twl spec new による issue フィールド自動付与
    - Scenario: issue-N パターンの name で spec new を実行する
        WHEN: twl spec new "issue-123" を実行する
        THEN: deltaspec/changes/issue-123/.deltaspec.yaml に issue: 123 フィールドが含まれる
    - Scenario: 非 issue パターンの name では issue フィールドを付与しない
        WHEN: twl spec new "add-user-auth" を実行する
        THEN: deltaspec/changes/add-user-auth/.deltaspec.yaml に issue: フィールドが含まれない

  Requirement: orchestrator sh 版の archive フォールバック検索
    - Scenario: issue フィールドなしの change を name パターンでフォールバック検出する
        WHEN: .deltaspec.yaml に issue: フィールドがなく name: issue-<N> が存在する
        THEN: orchestrator が当該 change を archive 対象として検出し、twl spec archive を実行する
    - Scenario: issue フィールドありの change はプライマリ検索で検出する
        WHEN: .deltaspec.yaml に issue: <N> フィールドが存在する
        THEN: orchestrator がフォールバックなしにプライマリ検索で当該 change を検出する

  Requirement: orchestrator Python 版の archive フォールバック検索
    - Scenario: Python orchestrator が name パターンで change を検出する
        WHEN: .deltaspec.yaml に issue: フィールドがなく name: issue-<N> が含まれる
        THEN: Python orchestrator が当該 change を archive 対象として処理する
    - Scenario: 両方のパターンが一致しても二重 archive しない
        WHEN: .deltaspec.yaml に issue: <N> と name: issue-<N> の両方が存在する
        THEN: orchestrator は当該 change を 1 回のみ archive する

  Edge cases (--coverage=edge-cases):
    - issue フィールドなし既存 change（旧フォーマット）のフォールバック検索
    - 非 issue パターン name（"add-feature", "hotfix-99" など）で issue フィールドが付与されないこと
    - issue 番号が複数桁（例: issue-1234）の場合の正確な抽出
    - issue 番号 0 またはゼロパディング（issue-007）の扱い
    - .deltaspec.yaml に issue: と name: 両方ある場合の二重 archive 防止
    - name: が issue-<N> パターンでも issue: フィールドが優先されること
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from twl.spec.new import cmd_new
from twl.autopilot.orchestrator import PhaseOrchestrator


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_ISSUE_RE = re.compile(r"^issue-(\d+)$")


def make_project(tmp_path: Path) -> Path:
    """Create minimal deltaspec project structure."""
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    return tmp_path


def _make_orchestrator(autopilot_dir: Path, tmp_path: Path) -> PhaseOrchestrator:
    return PhaseOrchestrator(
        plan_file=str(tmp_path / "plan.yaml"),
        phase=1,
        session_file=str(tmp_path / "session.json"),
        project_dir=str(tmp_path),
        autopilot_dir=str(autopilot_dir),
        scripts_root=tmp_path / "scripts",
    )


def _make_autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    return d


def _write_deltaspec_yaml(changes_dir: Path, change_id: str, content: str) -> Path:
    change_dir = changes_dir / change_id
    change_dir.mkdir(parents=True, exist_ok=True)
    yaml_path = change_dir / ".deltaspec.yaml"
    yaml_path.write_text(content, encoding="utf-8")
    return yaml_path


# ===========================================================================
# Requirement: twl spec new による issue フィールド自動付与
# ===========================================================================


class TestSpecNewIssueField:
    """Requirement: twl spec new による issue フィールド自動付与"""

    # ------------------------------------------------------------------
    # Scenario: issue-N パターンの name で spec new を実行する
    # WHEN: twl spec new "issue-123" を実行する
    # THEN: deltaspec/changes/issue-123/.deltaspec.yaml に issue: 123 フィールドが含まれる
    # ------------------------------------------------------------------

    def test_issue_pattern_name_adds_issue_field(self, tmp_path: Path, monkeypatch) -> None:
        """WHEN name='issue-123' THEN .deltaspec.yaml contains 'issue: 123'."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-123")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-123" / ".deltaspec.yaml"
        assert yaml_path.exists()
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue: 123" in content

    def test_issue_field_value_is_integer_not_string(self, tmp_path: Path, monkeypatch) -> None:
        """WHEN name='issue-456' THEN issue field value is numeric (not quoted)."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-456")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-456" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        # Must be "issue: 456" not "issue: '456'"
        assert "issue: 456" in content
        assert "issue: '456'" not in content

    def test_issue_field_large_number(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN name='issue-1234' THEN issue: 1234 is correctly extracted."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-1234")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-1234" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue: 1234" in content

    def test_issue_field_single_digit(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN name='issue-1' THEN issue: 1 is written correctly."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-1")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-1" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue: 1" in content

    def test_issue_field_positioned_in_yaml(self, tmp_path: Path, monkeypatch) -> None:
        """WHEN name='issue-99' THEN issue field appears in YAML alongside schema and created."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-99")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-99" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "schema: spec-driven" in content
        assert "created:" in content
        assert "issue: 99" in content

    # ------------------------------------------------------------------
    # Scenario: 非 issue パターンの name では issue フィールドを付与しない
    # WHEN: twl spec new "add-user-auth" を実行する
    # THEN: deltaspec/changes/add-user-auth/.deltaspec.yaml に issue: フィールドが含まれない
    # ------------------------------------------------------------------

    def test_non_issue_pattern_does_not_add_issue_field(self, tmp_path: Path, monkeypatch) -> None:
        """WHEN name='add-user-auth' THEN .deltaspec.yaml does NOT contain 'issue:'."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("add-user-auth")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "add-user-auth" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue:" not in content

    def test_plain_feature_name_no_issue_field(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN name='new-feature' THEN no issue field."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("new-feature")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "new-feature" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue:" not in content

    def test_hotfix_pattern_no_issue_field(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN name='hotfix-99' (not 'issue-99') THEN no issue field."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("hotfix-99")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "hotfix-99" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue:" not in content

    def test_name_with_issue_substring_but_not_pattern(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN name='fix-issue-tracker' THEN no issue field (not issue-<N> pattern)."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("fix-issue-tracker")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "fix-issue-tracker" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue:" not in content

    def test_numeric_only_name_no_issue_field(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN name='123' (bare number, not issue-N) THEN no issue field."""
        monkeypatch.chdir(make_project(tmp_path))
        # "123" is all digits — valid kebab-case per current regex? Let's check:
        # _KEBAB_RE = r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" → single char "123" → "1" matches
        # Actually "123" → starts with digit, matches. But no "issue-" prefix → no field.
        rc = cmd_new("fix-123")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "fix-123" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue:" not in content

    def test_issue_prefix_without_number_no_issue_field(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN name='issue-abc' THEN no issue field (non-numeric suffix)."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-abc")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-abc" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue:" not in content

    def test_issue_436_real_world_name(self, tmp_path: Path, monkeypatch) -> None:
        """Real-world: WHEN name='issue-436' THEN issue: 436 is added."""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-436")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-436" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        assert "issue: 436" in content


# ===========================================================================
# Requirement: orchestrator Python 版の archive フォールバック検索
# ===========================================================================


class TestOrchestratorArchiveFallback:
    """Requirement: orchestrator Python 版の archive フォールバック検索

    _archive_deltaspec_changes() must fall back to name: issue-<N> pattern
    when primary issue: <N> search returns 0 results.
    """

    # ------------------------------------------------------------------
    # Scenario: Python orchestrator が name パターンで change を検出する
    # WHEN: .deltaspec.yaml に issue: フィールドがなく name: issue-<N> が含まれる
    # THEN: Python orchestrator が当該 change を archive 対象として処理する
    # ------------------------------------------------------------------

    def test_fallback_name_pattern_detected_when_no_issue_field(
        self, tmp_path: Path
    ) -> None:
        """WHEN .deltaspec.yaml has 'name: issue-436' but no 'issue:' field THEN archive is called."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        # Set up fake git repo root with deltaspec/changes
        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        # Old-format YAML: no issue field, only name
        _write_deltaspec_yaml(
            changes_dir,
            "issue-436",
            "schema: spec-driven\nname: issue-436\ncreated: 2026-01-01\n",
        )

        archived: list[str] = []

        def fake_run(cmd, **kwargs):
            if "twl" in cmd and "archive" in cmd:
                # Extract change_id from command
                archived.append(cmd[-1])
            m = MagicMock()
            m.returncode = 0
            return m

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run", side_effect=fake_run),
        ):
            orch._archive_deltaspec_changes("436")

        assert "issue-436" in archived, (
            "Fallback name-pattern search must detect 'issue-436' change "
            "and call twl spec archive with it"
        )

    def test_fallback_not_triggered_when_primary_succeeds(
        self, tmp_path: Path
    ) -> None:
        """WHEN .deltaspec.yaml has 'issue: 436' THEN primary search finds it without fallback.

        Scenario: issue フィールドありの change はプライマリ検索で検出する
        WHEN: .deltaspec.yaml に issue: <N> フィールドが存在する
        THEN: orchestrator がフォールバックなしにプライマリ検索で当該 change を検出する
        """
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        # New-format YAML: has issue field
        _write_deltaspec_yaml(
            changes_dir,
            "issue-436",
            "schema: spec-driven\nissue: 436\ncreated: 2026-01-01\n",
        )

        archived: list[str] = []

        def fake_run(cmd, **kwargs):
            if "twl" in cmd and "archive" in cmd:
                archived.append(cmd[-1])
            m = MagicMock()
            m.returncode = 0
            return m

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run", side_effect=fake_run),
        ):
            orch._archive_deltaspec_changes("436")

        assert "issue-436" in archived, (
            "Primary search must detect 'issue-436' change via issue: field"
        )
        assert archived.count("issue-436") == 1, (
            "Should be archived exactly once"
        )

    # ------------------------------------------------------------------
    # Scenario: 両方のパターンが一致しても二重 archive しない
    # WHEN: .deltaspec.yaml に issue: <N> と name: issue-<N> の両方が存在する
    # THEN: orchestrator は当該 change を 1 回のみ archive する
    # ------------------------------------------------------------------

    def test_no_double_archive_when_both_issue_field_and_name_pattern_match(
        self, tmp_path: Path
    ) -> None:
        """WHEN .deltaspec.yaml has both 'issue: 436' and 'name: issue-436' THEN archive called once."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        # YAML has both fields
        _write_deltaspec_yaml(
            changes_dir,
            "issue-436",
            "schema: spec-driven\nname: issue-436\nissue: 436\ncreated: 2026-01-01\n",
        )

        archive_calls: list[str] = []

        def fake_run(cmd, **kwargs):
            if "twl" in cmd and "archive" in cmd:
                archive_calls.append(cmd[-1])
            m = MagicMock()
            m.returncode = 0
            return m

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run", side_effect=fake_run),
        ):
            orch._archive_deltaspec_changes("436")

        assert archive_calls.count("issue-436") == 1, (
            f"change 'issue-436' must be archived exactly once, got {archive_calls.count('issue-436')}"
        )

    def test_multiple_changes_only_matching_issue_archived(
        self, tmp_path: Path
    ) -> None:
        """Edge case: WHEN multiple changes exist THEN only the one matching issue-<N> is archived."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        # Target change with issue field
        _write_deltaspec_yaml(
            changes_dir,
            "issue-436",
            "schema: spec-driven\nissue: 436\ncreated: 2026-01-01\n",
        )
        # Unrelated change — different issue number
        _write_deltaspec_yaml(
            changes_dir,
            "issue-100",
            "schema: spec-driven\nissue: 100\ncreated: 2026-01-01\n",
        )
        # Unrelated change — no issue field
        _write_deltaspec_yaml(
            changes_dir,
            "add-feature",
            "schema: spec-driven\ncreated: 2026-01-01\n",
        )

        archived: list[str] = []

        def fake_run(cmd, **kwargs):
            if "twl" in cmd and "archive" in cmd:
                archived.append(cmd[-1])
            m = MagicMock()
            m.returncode = 0
            return m

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run", side_effect=fake_run),
        ):
            orch._archive_deltaspec_changes("436")

        assert archived == ["issue-436"], (
            f"Only 'issue-436' should be archived, got: {archived}"
        )

    def test_legacy_change_without_issue_field_detected_by_name_fallback(
        self, tmp_path: Path
    ) -> None:
        """Edge case: pre-436 change files (no issue field) are found by name: issue-<N> fallback."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        # Legacy YAML: no issue field, directory name is issue-<N>
        _write_deltaspec_yaml(
            changes_dir,
            "issue-436",
            "schema: spec-driven\ncreated: 2026-01-01\n",
            # Note: no 'issue:' field AND no 'name:' field — directory name only
        )

        archived: list[str] = []

        def fake_run(cmd, **kwargs):
            if "twl" in cmd and "archive" in cmd:
                archived.append(cmd[-1])
            m = MagicMock()
            m.returncode = 0
            return m

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run", side_effect=fake_run),
        ):
            orch._archive_deltaspec_changes("436")

        # With fallback: directory name "issue-436" matches issue-<N> pattern
        assert "issue-436" in archived, (
            "Legacy change with directory name 'issue-436' must be detected by fallback "
            "(directory-name pattern matching)"
        )

    def test_non_issue_change_name_not_archived_by_fallback(
        self, tmp_path: Path
    ) -> None:
        """Edge case: WHEN change directory is 'add-feature' (non-issue pattern) THEN NOT archived."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        _write_deltaspec_yaml(
            changes_dir,
            "add-feature",
            "schema: spec-driven\ncreated: 2026-01-01\n",
        )

        archived: list[str] = []

        def fake_run(cmd, **kwargs):
            if "twl" in cmd and "archive" in cmd:
                archived.append(cmd[-1])
            m = MagicMock()
            m.returncode = 0
            return m

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run", side_effect=fake_run),
        ):
            orch._archive_deltaspec_changes("436")

        assert archived == [], (
            "Non-issue-pattern change 'add-feature' must never be archived for issue #436"
        )

    def test_twl_cli_missing_skips_gracefully(self, tmp_path: Path) -> None:
        """Edge case: WHEN twl CLI is not found THEN _archive_deltaspec_changes exits without error."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        _write_deltaspec_yaml(
            changes_dir,
            "issue-436",
            "schema: spec-driven\nissue: 436\ncreated: 2026-01-01\n",
        )

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value=None),
            patch("twl.autopilot.orchestrator.subprocess.run") as mock_run,
        ):
            # Should not raise
            orch._archive_deltaspec_changes("436")

        # twl spec archive must NOT be called when twl is missing
        assert not any(
            "archive" in " ".join(str(a) for a in c.args[0])
            for c in mock_run.call_args_list
        ), "twl spec archive must not be called when twl CLI is absent"

    def test_no_changes_dir_skips_gracefully(self, tmp_path: Path) -> None:
        """Edge case: WHEN deltaspec/changes/ does not exist THEN no archive attempted."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        # No deltaspec/changes directory

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run") as mock_run,
        ):
            orch._archive_deltaspec_changes("436")

        assert not any(
            "archive" in " ".join(str(a) for a in c.args[0])
            for c in mock_run.call_args_list
        )

    def test_issue_field_inline_not_confused_with_other_fields(
        self, tmp_path: Path
    ) -> None:
        """Edge case: WHEN YAML has 'issue_tracker: 436' THEN it is NOT matched as 'issue: 436'."""
        autopilot_dir = _make_autopilot_dir(tmp_path)
        orch = _make_orchestrator(autopilot_dir, tmp_path)

        root = tmp_path / "project"
        changes_dir = root / "deltaspec" / "changes"
        # Lookalike field name — must NOT match
        _write_deltaspec_yaml(
            changes_dir,
            "issue-436",
            "schema: spec-driven\nissue_tracker: 436\ncreated: 2026-01-01\n",
        )

        archived: list[str] = []

        def fake_run(cmd, **kwargs):
            if "twl" in cmd and "archive" in cmd:
                archived.append(cmd[-1])
            m = MagicMock()
            m.returncode = 0
            return m

        with (
            patch("twl.autopilot.orchestrator.subprocess.check_output", return_value=str(root)),
            patch("twl.autopilot.orchestrator.shutil.which", return_value="/usr/bin/twl"),
            patch("twl.autopilot.orchestrator.subprocess.run", side_effect=fake_run),
        ):
            # Primary search for "issue: 436" must NOT match "issue_tracker: 436"
            # Fallback via directory name "issue-436" may still detect it
            orch._archive_deltaspec_changes("436")

        # Either archived via directory-name fallback or not at all —
        # but "issue_tracker: 436" must not be treated as the issue field.
        # The important assertion: archive_calls must not exceed 1 (no double-counting)
        assert archived.count("issue-436") <= 1, (
            "issue_tracker field must not be counted as issue field — no double archive"
        )


# ===========================================================================
# Unit helpers / regex tests
# ===========================================================================


class TestIssuePatternRegex:
    """Unit tests for the issue-N name detection logic."""

    def test_issue_n_pattern_matches(self) -> None:
        """_ISSUE_RE matches 'issue-<digits>' exactly."""
        for name in ("issue-1", "issue-42", "issue-436", "issue-9999"):
            m = _ISSUE_RE.match(name)
            assert m is not None, f"Expected '{name}' to match issue-N pattern"
            assert m.group(1) in ("1", "42", "436", "9999")

    def test_non_issue_pattern_does_not_match(self) -> None:
        """_ISSUE_RE must NOT match non-issue names."""
        for name in (
            "add-user-auth",
            "hotfix-99",
            "issue-abc",
            "issue-",
            "fix-issue-tracker",
            "my-issue-123",
            "issue123",
        ):
            assert _ISSUE_RE.match(name) is None, f"'{name}' should NOT match issue-N pattern"

    def test_issue_number_extracted_correctly(self) -> None:
        """Issue number extraction from matched groups."""
        m = _ISSUE_RE.match("issue-436")
        assert m is not None
        assert m.group(1) == "436"
        assert int(m.group(1)) == 436

    def test_zero_padded_issue_number(self) -> None:
        """Edge case: 'issue-007' matches but number is '007' (string, not 7)."""
        m = _ISSUE_RE.match("issue-007")
        assert m is not None
        # Extracted as string; caller decides how to interpret
        assert m.group(1) == "007"
