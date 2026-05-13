#!/usr/bin/env python3
"""Tests for audit_vocabulary (Section 11: Vocabulary Check).

Coverage:
- Forbidden word detected as WARNING
- No forbidden word -> no finding
- False positive exclusion: backtick内引用、「旧」「廃止予定」line、compound canonical entity
- registry.yaml が plugin_root に存在しない場合の skip
"""

import json
import subprocess
import sys
from pathlib import Path

import yaml


def _write_registry(plugin_dir: Path, registry: dict) -> None:
    (plugin_dir / "registry.yaml").write_text(
        yaml.dump(registry, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _write_deps_minimal(plugin_dir: Path) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump({
            "version": "3.0",
            "plugin": "test-vocab",
            "chains": {},
            "skills": {},
            "commands": {},
            "agents": {},
            "scripts": {},
        }, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _create_md(plugin_dir: Path, rel_path: str, body: str) -> None:
    fp = plugin_dir / rel_path
    fp.parent.mkdir(parents=True, exist_ok=True)
    fp.write_text(body, encoding="utf-8")


def _make_plugin(tmpdir: Path, *, glossary=None, md_files=None, skip_registry=False):
    plugin_dir = tmpdir / "test-vocab-plugin"
    plugin_dir.mkdir()

    _write_deps_minimal(plugin_dir)

    if not skip_registry:
        registry = {
            "version": "4.0",
            "plugin": "test-vocab",
            "glossary": glossary or {},
            "components": [],
            "chains": {},
            "hooks-monitors": {"hooks": [], "monitors": []},
            "integrity_rules": [
                {
                    "id": "vocabulary_forbidden_use",
                    "description": "forbidden 単語の使用",
                    "severity": "warning",
                    "audit_section": 11,
                },
            ],
        }
        _write_registry(plugin_dir, registry)

    for rel_path, body in (md_files or {}).items():
        _create_md(plugin_dir, rel_path, body)

    return plugin_dir


def _run(plugin_dir: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def _audit_json(plugin_dir: Path, *extra) -> list[dict]:
    proc = _run(plugin_dir, "--audit", "--format", "json", *extra)
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        raise AssertionError(
            f"audit JSON parse failed (exit={proc.returncode}): {e}\n"
            f"stdout={proc.stdout!r}\nstderr={proc.stderr!r}"
        )
    return payload.get("data", payload).get("items", [])


def _vocab_items(items: list[dict]) -> list[dict]:
    return [i for i in items if i['section'] == 'vocabulary_check']


def test_forbidden_word_detected_as_warning(tmp_path):
    glossary = {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": ["orchestrator"],
            "context": "L0 role",
            "description": "test entity",
            "examples": [],
        },
    }
    plugin = _make_plugin(
        tmp_path,
        glossary=glossary,
        md_files={
            "skills/some-skill/SKILL.md": (
                "---\nname: some-skill\n---\n\n"
                "The orchestrator handles requests.\n"
            ),
        },
    )
    items = _vocab_items(_audit_json(plugin))
    warnings = [i for i in items if i['severity'] == 'warning']
    assert any('orchestrator' in i['message'] for i in warnings), (
        f"expected warning for 'orchestrator', got items: {items}"
    )


def test_no_forbidden_word_no_finding(tmp_path):
    glossary = {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": ["orchestrator"],
            "context": "L0 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin = _make_plugin(
        tmp_path,
        glossary=glossary,
        md_files={
            "skills/some-skill/SKILL.md": (
                "---\nname: some-skill\n---\n\nNo forbidden words here.\n"
            ),
        },
    )
    items = _vocab_items(_audit_json(plugin))
    warnings = [i for i in items if i['severity'] == 'warning']
    assert not warnings, f"expected no warning, got: {warnings}"


def test_backtick_excluded(tmp_path):
    glossary = {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": ["orchestrator"],
            "context": "L0 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin = _make_plugin(
        tmp_path,
        glossary=glossary,
        md_files={
            "skills/some-skill/SKILL.md": (
                "---\nname: some-skill\n---\n\n"
                "Use `orchestrator` as the canonical name in spec.\n"
            ),
        },
    )
    items = _vocab_items(_audit_json(plugin))
    warnings = [i for i in items if i['severity'] == 'warning']
    assert not warnings, f"backtick should exclude, got: {warnings}"


def test_old_annotation_excluded(tmp_path):
    glossary = {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": ["orchestrator"],
            "context": "L0 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin = _make_plugin(
        tmp_path,
        glossary=glossary,
        md_files={
            "skills/some-skill/SKILL.md": (
                "---\nname: some-skill\n---\n\n"
                "旧 orchestrator は廃止予定です。\n"
            ),
        },
    )
    items = _vocab_items(_audit_json(plugin))
    warnings = [i for i in items if i['severity'] == 'warning']
    assert not warnings, f"'旧' line should be excluded, got: {warnings}"


def test_migration_stage_backtick_excluded(tmp_path):
    glossary = {
        "phaser": {
            "canonical": "phaser",
            "aliases": [],
            "forbidden": ["phase"],
            "context": "L1 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin = _make_plugin(
        tmp_path,
        glossary=glossary,
        md_files={
            "skills/some-skill/SKILL.md": (
                "---\nname: some-skill\n---\n\n"
                "Migration is in `Phase 1 PoC` stage.\n"
            ),
        },
    )
    items = _vocab_items(_audit_json(plugin))
    warnings = [i for i in items if i['severity'] == 'warning']
    assert not warnings, f"backtick `Phase 1 PoC` should exclude, got: {warnings}"


def test_compound_canonical_entity_excluded(tmp_path):
    glossary = {
        "phaser": {
            "canonical": "phaser",
            "aliases": [],
            "forbidden": ["pilot"],
            "context": "L1 role",
            "description": "test",
            "examples": [],
        },
        "co-autopilot": {
            "canonical": "co-autopilot",
            "aliases": [],
            "forbidden": [],
            "context": "compound entity",
            "description": "old controller naming maintained as canonical for deprecation",
            "examples": [],
        },
    }
    plugin = _make_plugin(
        tmp_path,
        glossary=glossary,
        md_files={
            "skills/some-skill/SKILL.md": (
                "---\nname: some-skill\n---\n\n"
                "Launch co-autopilot to handle the issue.\n"
            ),
        },
    )
    items = _vocab_items(_audit_json(plugin))
    warnings = [i for i in items if i['severity'] == 'warning' and 'pilot' in i['message']]
    assert not warnings, (
        f"co-autopilot compound entity should exclude 'pilot', got: {warnings}"
    )


def test_no_registry_skips_section_11(tmp_path):
    """registry.yaml が plugin_root 配下に不在の場合、audit_collect は Section 11/12 を
    skip する (auto-detect が false)。vocabulary_check section の items は 0 件になる。
    """
    plugin = _make_plugin(tmp_path, skip_registry=True)
    items = _vocab_items(_audit_json(plugin))
    assert items == [], f"Section 11 should be skipped when registry.yaml absent, got: {items}"


# =========================================================================
# --scan-spec 拡張テスト (Phase A、Section 11 が spec/+ADR/ も scan 対象に)
# =========================================================================

def _make_plugin_with_spec(
    tmpdir: Path,
    *,
    glossary,
    spec_files=None,
    adr_files=None,
):
    """monorepo_root + plugin_root を tmp に構築する (subprocess 経由で twl 実行用)。

    Structure:
      tmpdir/
        plugins/test-spec-vocab/
          registry.yaml + deps.yaml
        architecture/
          spec/twill-plugin-rebuild/*.md
          decisions/ADR-*.md

    twl は subprocess の cwd=plugin_dir で起動、_detect_monorepo_root が git rev-parse
    で monorepo を解決するため tmpdir に git init する。
    """
    monorepo_dir = tmpdir / "monorepo"
    monorepo_dir.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=str(monorepo_dir), check=True)

    plugin_dir = monorepo_dir / "plugins" / "test-spec-vocab"
    plugin_dir.mkdir(parents=True)

    spec_dir = monorepo_dir / "architecture" / "spec" / "twill-plugin-rebuild"
    spec_dir.mkdir(parents=True)
    for rel, body in (spec_files or {}).items():
        (spec_dir / rel).write_text(body, encoding="utf-8")

    adr_dir = monorepo_dir / "architecture" / "decisions"
    adr_dir.mkdir(parents=True)
    for rel, body in (adr_files or {}).items():
        (adr_dir / rel).write_text(body, encoding="utf-8")

    registry = {
        "version": "4.0",
        "plugin": "test-spec-vocab",
        "glossary": glossary,
        "components": [],
        "chains": {},
        "hooks-monitors": {"hooks": [], "monitors": []},
        "integrity_rules": [],
    }
    _write_registry(plugin_dir, registry)
    _write_deps_minimal(plugin_dir)

    return plugin_dir, monorepo_dir


def test_scan_spec_detects_forbidden_in_spec_md(tmp_path):
    """scan_spec=True 時、spec/ の .md ファイルで forbidden 語を検出する。"""
    glossary = {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": ["orchestrator"],
            "context": "L0 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin, _ = _make_plugin_with_spec(
        tmp_path,
        glossary=glossary,
        spec_files={
            "overview.md": "The orchestrator manages all phases.\n",
        },
    )
    items = _vocab_items(_audit_json(plugin, "--scan-spec"))
    warnings = [i for i in items if i['severity'] == 'warning' and 'spec' in i['component']]
    assert warnings, f"expected vocabulary:spec:* warning, got items: {items}"
    assert any('orchestrator' in i['message'] for i in warnings), (
        f"expected 'orchestrator' in spec .md, got: {warnings}"
    )


def test_scan_spec_detects_forbidden_in_adr(tmp_path):
    """scan_spec=True 時、ADR-*.md で forbidden 語を検出する。"""
    glossary = {
        "phaser": {
            "canonical": "phaser",
            "aliases": [],
            "forbidden": ["pilot"],
            "context": "L1 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin, _ = _make_plugin_with_spec(
        tmp_path,
        glossary=glossary,
        adr_files={
            "ADR-0099-test.md": "## Decision\n\nThe pilot drives the exploration phase.\n",
        },
    )
    items = _vocab_items(_audit_json(plugin, "--scan-spec"))
    warnings = [i for i in items if i['severity'] == 'warning' and 'spec' in i['component']]
    assert any('pilot' in i['message'] for i in warnings), (
        f"expected 'pilot' detected in ADR, got: {warnings}"
    )


def test_scan_spec_off_does_not_scan_spec(tmp_path):
    """scan_spec=False (default) 時、spec/ の forbidden 語は検出されない。"""
    glossary = {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": ["orchestrator"],
            "context": "L0 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin, _ = _make_plugin_with_spec(
        tmp_path,
        glossary=glossary,
        spec_files={
            "overview.md": "The orchestrator is described here.\n",
        },
    )
    # --scan-spec なしで実行 (default False)
    items = _vocab_items(_audit_json(plugin))
    spec_warnings = [
        i for i in items
        if i['severity'] == 'warning' and 'spec' in i['component']
    ]
    assert not spec_warnings, (
        f"scan_spec=False should not emit vocabulary:spec:* warnings, got: {spec_warnings}"
    )


def test_scan_spec_false_positive_backtick_in_spec(tmp_path):
    """spec .md の backtick 内 forbidden 語は false positive として除外される。"""
    glossary = {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": ["orchestrator"],
            "context": "L0 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin, _ = _make_plugin_with_spec(
        tmp_path,
        glossary=glossary,
        spec_files={
            "overview.md": "The `orchestrator` was the old name.\n",
        },
    )
    items = _vocab_items(_audit_json(plugin, "--scan-spec"))
    spec_warnings = [
        i for i in items
        if i['severity'] == 'warning' and 'spec' in i['component']
        and 'orchestrator' in i['message']
    ]
    assert not spec_warnings, (
        f"backtick in spec .md should be excluded, got: {spec_warnings}"
    )


def test_scan_spec_false_positive_old_annotation(tmp_path):
    """spec .md の「旧」行の forbidden 語は false positive として除外される。"""
    glossary = {
        "phaser": {
            "canonical": "phaser",
            "aliases": [],
            "forbidden": ["pilot"],
            "context": "L1 role",
            "description": "test",
            "examples": [],
        },
    }
    plugin, _ = _make_plugin_with_spec(
        tmp_path,
        glossary=glossary,
        spec_files={
            "ADR-migrated.md": "旧 pilot は廃止予定。\n",
        },
    )
    items = _vocab_items(_audit_json(plugin, "--scan-spec"))
    spec_warnings = [
        i for i in items
        if i['severity'] == 'warning' and 'spec' in i['component']
        and 'pilot' in i['message']
    ]
    assert not spec_warnings, (
        f"'旧' annotation should exclude in spec .md, got: {spec_warnings}"
    )
