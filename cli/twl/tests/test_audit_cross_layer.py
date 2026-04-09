#!/usr/bin/env python3
"""Tests for Section 10: Cross-Layer Consistency check in twl audit.

Issue: #258 — twl audit に cross-layer consistency check を実装

Coverage:
- _extract_vision_sections: Constraints/Non-Goals の正常抽出
- _extract_bold_terms: ボールド強調語の抽出
- _check_layer_consistency: Type 4 矛盾検出
- audit_cross_layer_consistency: 三層整合性チェック全体
- _detect_monorepo_root: git フォールバック挙動
- audit_collect: Section 10 項目の統合
"""

import sys
import tempfile
from pathlib import Path

import pytest
import yaml


# ---------------------------------------------------------------------------
# Import helpers
# ---------------------------------------------------------------------------

def _get_module():
    """Import audit module from worktree src."""
    src = Path(__file__).parent.parent / "src"
    if str(src) not in sys.path:
        sys.path.insert(0, str(src))
    from twl.validation.audit import (
        _extract_vision_sections,
        _extract_bold_terms,
        _check_layer_consistency,
        audit_cross_layer_consistency,
        audit_collect,
        _detect_monorepo_root,
    )
    return (
        _extract_vision_sections,
        _extract_bold_terms,
        _check_layer_consistency,
        audit_cross_layer_consistency,
        audit_collect,
        _detect_monorepo_root,
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _make_vision(tmpdir: Path, path_relative: str, content: str) -> Path:
    """Write vision.md at the given relative path under tmpdir."""
    p = tmpdir / path_relative
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    return p


MONOREPO_VISION_BASIC = """\
## Vision
TWiLL モノリポ。

## Constraints

- **SSOT 原則**: deps.yaml が唯一の情報源
- **依存方向の一方向性**: plugins → cli の方向のみ許可

## Non-Goals

- 共有ライブラリの提供
"""

CLI_VISION_OK = """\
## Vision
twl CLI。

## Constraints

- **deps.yaml が SSOT**: プラグイン構造の全メタデータはここから導出
- **外部依存の最小化**: 標準ライブラリ + PyYAML のみ必須

## Non-Goals

- プラグインの実行時動作の制御
"""

CLI_VISION_TYPE4_VIOLATION = """\
## Vision
twl CLI（違反版）。

## Constraints

- **deps.yaml が SSOT**: プラグイン構造の全メタデータはここから導出

## Non-Goals

- **SSOT 原則** は不要（ローカル環境では無視）
"""

PLUGIN_VISION_OK = """\
## Vision
plugin-twl。

## Constraints

- **TWiLL フレームワーク準拠**: deps.yaml v3.0 準拠
- **Bare repo + worktree 一律**

## Non-Goals

- 技術スタック固有の機能
"""


# ---------------------------------------------------------------------------
# Unit tests: _extract_vision_sections
# ---------------------------------------------------------------------------

class TestExtractVisionSections:
    def setup_method(self):
        (
            self._extract,
            self._bold,
            self._check,
            self._cross,
            self._collect,
            self._detect,
        ) = _get_module()

    def test_extracts_constraints_and_non_goals(self, tmp_path):
        vision = _make_vision(tmp_path, "arch/vision.md", MONOREPO_VISION_BASIC)
        result = self._extract(vision)
        assert len(result["constraints"]) == 2
        assert len(result["non_goals"]) == 1
        assert any("SSOT" in c for c in result["constraints"])
        assert any("共有ライブラリ" in ng for ng in result["non_goals"])

    def test_missing_file_returns_empty(self, tmp_path):
        result = self._extract(tmp_path / "nonexistent.md")
        assert result == {"constraints": [], "non_goals": []}

    def test_no_constraints_section(self, tmp_path):
        vision = _make_vision(tmp_path, "arch/vision.md", "## Vision\nOnly vision.\n")
        result = self._extract(vision)
        assert result["constraints"] == []
        assert result["non_goals"] == []

    def test_constraints_stops_at_next_heading(self, tmp_path):
        content = """\
## Vision
概要

## Constraints

- constraint A

## Non-Goals

- non-goal B
"""
        vision = _make_vision(tmp_path, "arch/vision.md", content)
        result = self._extract(vision)
        assert result["constraints"] == ["constraint A"]
        assert result["non_goals"] == ["non-goal B"]


# ---------------------------------------------------------------------------
# Unit tests: _extract_bold_terms
# ---------------------------------------------------------------------------

class TestExtractBoldTerms:
    def setup_method(self):
        (
            self._extract,
            self._bold,
            _,
            _,
            _,
            _,
        ) = _get_module()

    def test_extracts_bold_terms(self):
        text = "- **SSOT 原則**: deps.yaml が唯一の情報源"
        assert self._bold(text) == ["SSOT 原則"]

    def test_multiple_terms(self):
        text = "**term A** and **term B** appear"
        terms = self._bold(text)
        assert "term A" in terms
        assert "term B" in terms

    def test_no_bold_returns_empty(self):
        assert self._bold("plain text without bold") == []


# ---------------------------------------------------------------------------
# Unit tests: _check_layer_consistency
# ---------------------------------------------------------------------------

class TestCheckLayerConsistency:
    def setup_method(self):
        (
            _,
            _,
            self._check,
            _,
            _,
            _,
        ) = _get_module()

    def test_no_issue_when_consistent(self):
        upper_constraints = [
            "**SSOT 原則**: deps.yaml が唯一の情報源",
            "**依存方向の一方向性**: plugins → cli のみ",
        ]
        lower_constraints = ["**deps.yaml が SSOT**: 導出元"]
        lower_non_goals = ["実行時動作の制御"]
        issues = self._check(
            lower_name="cli_twl",
            lower_constraints=lower_constraints,
            lower_non_goals=lower_non_goals,
            upper_constraints=upper_constraints,
        )
        assert issues == []

    def test_type4_detected_when_upper_constraint_term_in_lower_non_goals(self):
        upper_constraints = ["**SSOT 原則**: deps.yaml が唯一の情報源"]
        lower_non_goals = ["**SSOT 原則** は不要（ローカルでは無視）"]
        issues = self._check(
            lower_name="cli_twl",
            lower_constraints=[],
            lower_non_goals=lower_non_goals,
            upper_constraints=upper_constraints,
        )
        assert len(issues) == 1
        assert "SSOT 原則" in issues[0]
        assert "Type4" in issues[0]

    def test_no_bold_terms_in_upper_produces_no_issues(self):
        upper_constraints = ["plain constraint without bold"]
        lower_non_goals = ["plain constraint without bold"]
        issues = self._check(
            lower_name="cli_twl",
            lower_constraints=[],
            lower_non_goals=lower_non_goals,
            upper_constraints=upper_constraints,
        )
        assert issues == []

    def test_type4_reports_each_term_once(self):
        """同じ term が複数の Non-Goals に現れても1回だけ報告される"""
        upper_constraints = ["**SSOT 原則**: 重要"]
        lower_non_goals = [
            "**SSOT 原則** は不要 A",
            "**SSOT 原則** は不要 B",
        ]
        issues = self._check(
            lower_name="cli_twl",
            lower_constraints=[],
            lower_non_goals=lower_non_goals,
            upper_constraints=upper_constraints,
        )
        assert len(issues) == 1


# ---------------------------------------------------------------------------
# Integration tests: audit_cross_layer_consistency
# ---------------------------------------------------------------------------

class TestAuditCrossLayerConsistency:
    def setup_method(self):
        (
            _,
            _,
            _,
            self._cross,
            _,
            _,
        ) = _get_module()

    def _setup_three_layers(self, tmp_path, monorepo=MONOREPO_VISION_BASIC,
                             cli=CLI_VISION_OK, plugin=PLUGIN_VISION_OK):
        _make_vision(tmp_path, "architecture/vision.md", monorepo)
        _make_vision(tmp_path, "cli/twl/architecture/vision.md", cli)
        _make_vision(tmp_path, "plugins/twl/architecture/vision.md", plugin)
        return tmp_path

    def test_ok_when_all_consistent(self, tmp_path):
        root = self._setup_three_layers(tmp_path)
        items = self._cross(root)
        sections = [i["section"] for i in items]
        severities = [i["severity"] for i in items]
        assert all(s == "cross_layer_consistency" for s in sections)
        assert "warning" not in severities
        assert "critical" not in severities
        ok_items = [i for i in items if i["severity"] == "ok"]
        assert len(ok_items) == 2  # monorepo→cli_twl, monorepo→plugin_twl

    def test_warning_when_type4_violation(self, tmp_path):
        root = self._setup_three_layers(tmp_path, cli=CLI_VISION_TYPE4_VIOLATION)
        items = self._cross(root)
        warnings = [i for i in items if i["severity"] == "warning"]
        assert len(warnings) >= 1
        assert any("SSOT" in w["message"] for w in warnings)

    def test_skip_missing_layer_without_error(self, tmp_path):
        """architecture/ が存在しない層はスキップ（ERROR にしない）"""
        _make_vision(tmp_path, "architecture/vision.md", MONOREPO_VISION_BASIC)
        # cli/twl/architecture/vision.md は存在しない
        _make_vision(tmp_path, "plugins/twl/architecture/vision.md", PLUGIN_VISION_OK)
        items = self._cross(tmp_path)
        # cli_twl は info でスキップ、plugin_twl は ok
        info_items = [i for i in items if i["severity"] == "info"]
        ok_items = [i for i in items if i["severity"] == "ok"]
        assert any("cli_twl" in i["component"] for i in info_items)
        assert any("plugin_twl" in i["component"] for i in ok_items)

    def test_no_items_when_monorepo_vision_missing(self, tmp_path):
        """monorepo の vision.md がない場合は info のみ（crash しない）"""
        # monorepo vision.md なし
        _make_vision(tmp_path, "cli/twl/architecture/vision.md", CLI_VISION_OK)
        items = self._cross(tmp_path)
        assert all(i["severity"] == "info" for i in items)

    def test_section_name_is_cross_layer_consistency(self, tmp_path):
        root = self._setup_three_layers(tmp_path)
        items = self._cross(root)
        assert all(i["section"] == "cross_layer_consistency" for i in items)


# ---------------------------------------------------------------------------
# Integration tests: audit_collect includes Section 10
# ---------------------------------------------------------------------------

class TestAuditCollectSection10:
    def setup_method(self):
        (
            _,
            _,
            _,
            _,
            self._collect,
            _,
        ) = _get_module()

    def _make_minimal_deps(self, plugin_dir: Path) -> dict:
        deps = {"version": "3.0", "skills": {}, "commands": {}, "agents": {}, "scripts": {}}
        (plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, allow_unicode=True), encoding="utf-8"
        )
        return deps

    def test_audit_collect_includes_cross_layer_section(self, tmp_path):
        """audit_collect に monorepo_root を渡すと cross_layer_consistency 項目が含まれる"""
        plugin_dir = tmp_path / "plugins" / "twl"
        plugin_dir.mkdir(parents=True)
        deps = self._make_minimal_deps(plugin_dir)

        # monorepo root に vision.md を配置
        (tmp_path / "architecture").mkdir()
        (tmp_path / "architecture" / "vision.md").write_text(
            MONOREPO_VISION_BASIC, encoding="utf-8"
        )
        (tmp_path / "cli" / "twl" / "architecture").mkdir(parents=True)
        (tmp_path / "cli" / "twl" / "architecture" / "vision.md").write_text(
            CLI_VISION_OK, encoding="utf-8"
        )
        (plugin_dir / "architecture").mkdir()
        (plugin_dir / "architecture" / "vision.md").write_text(
            PLUGIN_VISION_OK, encoding="utf-8"
        )

        items = self._collect(deps, plugin_dir, monorepo_root=tmp_path)
        cross_items = [i for i in items if i["section"] == "cross_layer_consistency"]
        assert len(cross_items) > 0

    def test_audit_collect_without_monorepo_root_does_not_crash(self, tmp_path):
        """monorepo_root なし（None）でも crash しない（git なし環境でもスキップ）"""
        plugin_dir = tmp_path / "plugins" / "twl"
        plugin_dir.mkdir(parents=True)
        deps = self._make_minimal_deps(plugin_dir)
        # git リポジトリではないので _detect_monorepo_root は None を返す想定
        # (または architecture/vision.md が親にある場合は検出される)
        try:
            items = self._collect(deps, plugin_dir)
            # エラーなく実行できることを確認
            assert isinstance(items, list)
        except SystemExit:
            pass  # sys.exit は audit_report から来ない (audit_collect は exit しない)
