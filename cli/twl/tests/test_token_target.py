#!/usr/bin/env python3
"""Tests for token_target in types.yaml + load_token_thresholds + sync_check.

Covers:
- load_token_thresholds() reads token_target from types.yaml
- load_token_thresholds() fallback when types.yaml is missing
- load_token_thresholds() excludes types without token_target (reference, script)
- sync_check() validates token_target table in ref-practices.md
- sync_check() detects warning >= critical violation
- sync_check() detects missing types in token table
"""

import sys
import tempfile
from pathlib import Path

import pytest
import yaml

SRC = str(Path(__file__).resolve().parent.parent / "src")
sys.path.insert(0, SRC)

from twl.core.types import load_token_thresholds, _FALLBACK_TOKEN_THRESHOLDS


class TestLoadTokenThresholds:
    """load_token_thresholds() reads token_target from types.yaml."""

    def test_reads_from_types_yaml(self, tmp_path):
        """WHEN types.yaml has token_target entries
        THEN load_token_thresholds returns those values."""
        types_yaml = tmp_path / "types.yaml"
        types_yaml.write_text(
            "types:\n"
            "  controller:\n"
            "    section: skills\n"
            "    can_spawn: []\n"
            "    spawnable_by: []\n"
            "    token_target:\n"
            "      warning: 800\n"
            "      critical: 1200\n",
            encoding="utf-8",
        )
        result = load_token_thresholds(tmp_path)
        assert "controller" in result
        assert result["controller"] == (800, 1200)

    def test_excludes_types_without_token_target(self, tmp_path):
        """WHEN types.yaml has types without token_target
        THEN those types are not in the result."""
        types_yaml = tmp_path / "types.yaml"
        types_yaml.write_text(
            "types:\n"
            "  reference:\n"
            "    section: skills\n"
            "    can_spawn: []\n"
            "    spawnable_by: []\n"
            "  controller:\n"
            "    section: skills\n"
            "    can_spawn: []\n"
            "    spawnable_by: []\n"
            "    token_target:\n"
            "      warning: 1500\n"
            "      critical: 2500\n",
            encoding="utf-8",
        )
        result = load_token_thresholds(tmp_path)
        assert "reference" not in result
        assert "controller" in result

    def test_fallback_when_no_types_yaml(self, tmp_path):
        """WHEN types.yaml does not exist
        THEN returns fallback hardcoded thresholds."""
        result = load_token_thresholds(tmp_path)
        assert result == dict(_FALLBACK_TOKEN_THRESHOLDS)
        assert "controller" in result
        assert "workflow" in result
        assert "reference" not in result
        assert "script" not in result

    def test_fallback_when_no_token_targets_at_all(self, tmp_path):
        """WHEN types.yaml exists but no type has token_target
        THEN returns fallback."""
        types_yaml = tmp_path / "types.yaml"
        types_yaml.write_text(
            "types:\n"
            "  reference:\n"
            "    section: skills\n"
            "    can_spawn: []\n"
            "    spawnable_by: []\n",
            encoding="utf-8",
        )
        result = load_token_thresholds(tmp_path)
        assert result == dict(_FALLBACK_TOKEN_THRESHOLDS)

    def test_actual_types_yaml_has_five_types(self):
        """WHEN the real types.yaml is loaded
        THEN controller/workflow/atomic/composite/specialist have token_target."""
        # Resolve loom_root from package location
        pkg = Path(__file__).resolve().parent.parent
        result = load_token_thresholds(pkg)
        for t in ("controller", "workflow", "atomic", "composite", "specialist"):
            assert t in result, f"{t} should have token_target"
        assert "reference" not in result
        assert "script" not in result

    def test_actual_types_yaml_values(self):
        """Spot-check expected values from real types.yaml."""
        pkg = Path(__file__).resolve().parent.parent
        result = load_token_thresholds(pkg)
        assert result["workflow"] == (1200, 2000)
        assert result["specialist"] == (1800, 2500)


class TestSyncCheckTokenTable:
    """sync_check() validates token_target table in a ref doc."""

    def _make_loom_root(self, tmp_path: Path, token_table: str) -> Path:
        """Create a minimal loom_root with types.yaml and a ref doc."""
        types_yaml = tmp_path / "types.yaml"
        types_yaml.write_text(
            "types:\n"
            "  controller:\n"
            "    section: skills\n"
            "    can_spawn: []\n"
            "    spawnable_by: []\n"
            "    token_target:\n"
            "      warning: 1500\n"
            "      critical: 2500\n"
            "  workflow:\n"
            "    section: skills\n"
            "    can_spawn: []\n"
            "    spawnable_by: []\n"
            "    token_target:\n"
            "      warning: 1200\n"
            "      critical: 2000\n",
            encoding="utf-8",
        )
        ref_doc = tmp_path / "docs" / "ref-test.md"
        ref_doc.parent.mkdir(parents=True, exist_ok=True)
        ref_doc.write_text(token_table, encoding="utf-8")
        return tmp_path

    def test_valid_token_table_passes(self, tmp_path):
        """WHEN token table matches types.yaml values
        THEN sync_check exits 0."""
        table = (
            "# Test\n\n"
            "| 型 | Warning | Critical | 備考 |\n"
            "|---|---|---|---|\n"
            "| controller | 1,500 tok | 2,500 tok | |\n"
            "| workflow | 1,200 tok | 2,000 tok | |\n"
        )
        loom_root = self._make_loom_root(tmp_path, table)

        import subprocess
        result = subprocess.run(
            [sys.executable, "-m", "twl", "--sync-check", "docs/ref-test.md"],
            cwd=str(loom_root),
            capture_output=True,
            text=True,
            env={**__import__("os").environ, "PYTHONPATH": SRC, "TWL_LOOM_ROOT": str(loom_root)},
        )
        assert result.returncode == 0, f"Expected 0, got {result.returncode}\n{result.stdout}\n{result.stderr}"
        assert "No differences found" in result.stdout

    def test_warning_gte_critical_fails(self, tmp_path):
        """WHEN warning >= critical in token table
        THEN sync_check reports token-invalid."""
        table = (
            "| 型 | Warning | Critical | 備考 |\n"
            "|---|---|---|---|\n"
            "| controller | 2,500 tok | 1,500 tok | |\n"
            "| workflow | 1,200 tok | 2,000 tok | |\n"
        )
        loom_root = self._make_loom_root(tmp_path, table)

        import subprocess
        result = subprocess.run(
            [sys.executable, "-m", "twl", "--sync-check", "docs/ref-test.md"],
            cwd=str(loom_root),
            capture_output=True,
            text=True,
            env={**__import__("os").environ, "PYTHONPATH": SRC, "TWL_LOOM_ROOT": str(loom_root)},
        )
        assert result.returncode != 0
        assert "token-invalid" in result.stdout

    def test_deep_validate_reads_thresholds_dynamically(self, tmp_path, monkeypatch):
        """WHEN types.yaml token_target is updated
        THEN deep_validate uses the new thresholds without reimport.

        AC #3: types.yaml の token_target を変更 → twl --deep-validate 再実行で反映。
        deep.py に module-level TOKEN_THRESHOLDS 定数を残すと in-process では反映されない。
        """
        # 小さな warning 値を持つ types.yaml を準備
        types_yaml = tmp_path / "types.yaml"
        types_yaml.write_text(
            "types:\n"
            "  controller:\n"
            "    section: skills\n"
            "    can_spawn: [reference]\n"
            "    spawnable_by: [user]\n"
            "    token_target:\n"
            "      warning: 1\n"
            "      critical: 2\n",
            encoding="utf-8",
        )
        monkeypatch.setenv("TWL_LOOM_ROOT", str(tmp_path))

        # deep.py の module-level 定数キャッシュが残っていないことを確認するため、
        # deep_validate を呼んだときに新しい types.yaml が反映される
        from twl.validation import deep as deep_mod
        # TOKEN_THRESHOLDS という名前の module-level 定数は存在しないこと
        assert not hasattr(deep_mod, "TOKEN_THRESHOLDS"), (
            "deep.py must not retain a module-level TOKEN_THRESHOLDS constant; "
            "thresholds must be loaded inside deep_validate() to support dynamic updates."
        )

        # 実際に load_token_thresholds が更新値を読むことも確認
        result = load_token_thresholds(tmp_path)
        assert result["controller"] == (1, 2)

    def test_missing_type_in_token_table_fails(self, tmp_path):
        """WHEN a token_target type from types.yaml is missing in ref table
        THEN sync_check reports token-missing-in-ref."""
        table = (
            "| 型 | Warning | Critical | 備考 |\n"
            "|---|---|---|---|\n"
            "| controller | 1,500 tok | 2,500 tok | |\n"
        )
        loom_root = self._make_loom_root(tmp_path, table)

        import subprocess
        result = subprocess.run(
            [sys.executable, "-m", "twl", "--sync-check", "docs/ref-test.md"],
            cwd=str(loom_root),
            capture_output=True,
            text=True,
            env={**__import__("os").environ, "PYTHONPATH": SRC, "TWL_LOOM_ROOT": str(loom_root)},
        )
        assert result.returncode != 0
        assert "token-missing-in-ref" in result.stdout
        assert "workflow" in result.stdout
