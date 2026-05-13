#!/usr/bin/env python3
"""Tests for audit_registry (Section 12: Registry Integrity).

Coverage:
- 5 section 全存在 -> no critical
- integrity_rules section 欠落 -> CRITICAL
- prefix_role_match: phaser-impl + role phaser -> OK / role workflow -> CRITICAL
- no_duplicate_concern: unique -> OK / duplicate -> CRITICAL
- ssot_authority_unique: ssot_excludes と他 concern overlap -> CRITICAL
- seed component file missing -> INFO (skip frontmatter check)
- Stub warning emitted for derived_drift_check / description_required_consistency
"""

import json
import subprocess
import sys
from pathlib import Path

import yaml


def _write_deps_minimal(plugin_dir: Path) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump({
            "version": "3.0",
            "plugin": "test-registry",
            "chains": {},
            "skills": {},
            "commands": {},
            "agents": {},
            "scripts": {},
        }, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _write_registry(plugin_dir: Path, registry: dict) -> None:
    (plugin_dir / "registry.yaml").write_text(
        yaml.dump(registry, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _default_glossary() -> dict:
    return {
        "administrator": {
            "canonical": "administrator",
            "aliases": [],
            "forbidden": [],
            "context": "L0",
            "description": "test",
            "examples": [],
        },
        "phaser": {
            "canonical": "phaser",
            "aliases": [],
            "forbidden": [],
            "context": "L1",
            "description": "test",
            "examples": [],
        },
    }


def _default_integrity_rules() -> list[dict]:
    return [
        {"id": "no_duplicate_concern", "description": "test", "severity": "critical", "audit_section": 12},
        {"id": "ssot_authority_unique", "description": "test", "severity": "critical", "audit_section": 12},
        {"id": "prefix_role_match", "description": "test", "severity": "critical", "audit_section": 12},
        {"id": "derived_drift_check", "description": "test", "severity": "warning", "audit_section": 12},
        {"id": "description_required_consistency", "description": "test", "severity": "warning", "audit_section": 12},
        {"id": "vocabulary_forbidden_use", "description": "test", "severity": "warning", "audit_section": 11},
        {"id": "official_name_collision", "description": "test", "severity": "warning", "audit_section": 11},
    ]


def _make_plugin(
    tmpdir: Path,
    *,
    components=None,
    omit_section: str = None,
    glossary=None,
    integrity_rules=None,
):
    plugin_dir = tmpdir / "test-registry-plugin"
    plugin_dir.mkdir()

    _write_deps_minimal(plugin_dir)

    registry = {
        "version": "4.0",
        "plugin": "test-registry",
        "glossary": glossary if glossary is not None else _default_glossary(),
        "components": components or [],
        "chains": {},
        "hooks-monitors": {"hooks": [], "monitors": []},
        "integrity_rules": integrity_rules if integrity_rules is not None else _default_integrity_rules(),
    }
    if omit_section:
        registry.pop(omit_section, None)

    _write_registry(plugin_dir, registry)
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


def _reg_items(items: list[dict]) -> list[dict]:
    return [i for i in items if i['section'] == 'registry_integrity']


def _critical_only(items: list[dict]) -> list[dict]:
    return [i for i in items if i['severity'] == 'critical']


def test_all_sections_present_emits_no_section_critical(tmp_path):
    plugin = _make_plugin(tmp_path)
    items = _reg_items(_audit_json(plugin))
    section_criticals = [
        i for i in items
        if i['severity'] == 'critical' and i['component'].startswith('registry:section:')
    ]
    assert not section_criticals, f"all sections present should have no section critical, got: {section_criticals}"


def test_missing_integrity_rules_emits_critical(tmp_path):
    plugin = _make_plugin(tmp_path, omit_section='integrity_rules')
    items = _reg_items(_audit_json(plugin))
    target = [
        i for i in items
        if i['severity'] == 'critical' and i['component'] == 'registry:section:integrity_rules'
    ]
    assert target, f"missing integrity_rules should emit critical, got items: {items}"


def test_prefix_role_match_correct_emits_no_critical(tmp_path):
    components = [
        {
            "name": "phaser-impl",
            "role": "phaser",
            "file": "skills/phaser-impl/SKILL.md",
            "concern": "implementation phase",
            "depends_on_status": "Refined",
            "next_status": "Implemented",
            "can_spawn": [],
            "description_required": True,
        },
    ]
    plugin = _make_plugin(tmp_path, components=components)
    items = _reg_items(_audit_json(plugin))
    prefix_criticals = [
        i for i in _critical_only(items)
        if 'prefix_role_match' in i['message']
    ]
    assert not prefix_criticals, f"phaser-impl + role phaser should be OK, got: {prefix_criticals}"


def test_prefix_role_match_wrong_emits_critical(tmp_path):
    components = [
        {
            "name": "phaser-impl",
            "role": "workflow",
            "file": "skills/phaser-impl/SKILL.md",
            "concern": "implementation phase",
        },
    ]
    plugin = _make_plugin(tmp_path, components=components)
    items = _reg_items(_audit_json(plugin))
    prefix_criticals = [
        i for i in _critical_only(items)
        if 'prefix_role_match' in i['message']
    ]
    assert prefix_criticals, f"phaser-impl + role workflow should emit critical, got items: {items}"


def test_no_duplicate_concern_unique_emits_no_critical(tmp_path):
    components = [
        {"name": "phaser-impl", "role": "phaser", "concern": "implementation"},
        {"name": "phaser-pr", "role": "phaser", "concern": "pr creation"},
    ]
    plugin = _make_plugin(tmp_path, components=components)
    items = _reg_items(_audit_json(plugin))
    dup_criticals = [
        i for i in _critical_only(items)
        if 'no_duplicate_concern' in i['message']
    ]
    assert not dup_criticals, f"unique concerns should not emit critical, got: {dup_criticals}"


def test_no_duplicate_concern_duplicate_emits_critical(tmp_path):
    components = [
        {"name": "phaser-impl", "role": "phaser", "concern": "implementation"},
        {"name": "phaser-pr", "role": "phaser", "concern": "implementation"},
    ]
    plugin = _make_plugin(tmp_path, components=components)
    items = _reg_items(_audit_json(plugin))
    dup_criticals = [
        i for i in _critical_only(items)
        if 'no_duplicate_concern' in i['message']
    ]
    assert dup_criticals, f"duplicate concern should emit critical, got items: {items}"


def test_ssot_authority_unique_is_stub_warning_phase1(tmp_path):
    """Phase 1 PoC: ssot_authority_unique は stub warning (Phase 2 で実装)。

    delegation (ssot_excludes) と concern の semantic verification は単純な overlap 検出
    では false positive を生むため、Authority field 追加と組み合わせて Phase 2 で実装する。
    """
    components = [
        {
            "name": "administrator",
            "role": "administrator",
            "concern": "polling status",
            "ssot_excludes": ["status-transition"],
        },
        {
            "name": "phaser-impl",
            "role": "phaser",
            "concern": "status-transition for implementation",
        },
    ]
    plugin = _make_plugin(tmp_path, components=components)
    items = _reg_items(_audit_json(plugin))
    # Phase 1 では critical を emit しないこと (false positive 抑制)
    ssot_criticals = [
        i for i in _critical_only(items)
        if 'ssot_authority_unique' in i['message']
    ]
    assert not ssot_criticals, (
        f"Phase 1 PoC: ssot_authority_unique should NOT emit critical (stub), got: {ssot_criticals}"
    )
    # stub warning が出ていること
    ssot_warnings = [
        i for i in items
        if i['severity'] == 'warning'
        and i['component'] == 'registry:rule:ssot_authority_unique'
    ]
    assert ssot_warnings, (
        f"ssot_authority_unique stub warning expected, got items: {items}"
    )


def test_seed_component_file_missing_emits_info(tmp_path):
    components = [
        {
            "name": "phaser-impl",
            "role": "phaser",
            "file": "skills/phaser-impl/SKILL.md",  # 不存在
            "concern": "implementation",
        },
    ]
    plugin = _make_plugin(tmp_path, components=components)
    items = _reg_items(_audit_json(plugin))
    info_items = [
        i for i in items
        if i['severity'] == 'info' and i['component'] == 'registry:component:phaser-impl'
    ]
    assert info_items, f"file missing should emit info, got items: {items}"


def test_stub_rules_emit_warnings(tmp_path):
    plugin = _make_plugin(tmp_path)
    items = _reg_items(_audit_json(plugin))
    warnings = [i for i in items if i['severity'] == 'warning']
    stub_ids = {'ssot_authority_unique', 'derived_drift_check', 'description_required_consistency'}
    found_ids = {
        i['component'].split(':')[-1]
        for i in warnings
        if i['component'].startswith('registry:rule:')
    }
    assert stub_ids.issubset(found_ids), (
        f"expected stub warnings for {stub_ids}, got: {found_ids} (all warnings: {warnings})"
    )


def test_non_seed_component_not_checked_phase1(tmp_path):
    """Phase 1 PoC: prefix_role_match は SEED_NAMES (administrator + phaser-* 5 件) のみ検査。
    SEED_NAMES 外の component は filter で除外され critical を emit しない。
    Phase 2 dual-stack で全 components 検査に拡大予定。
    """
    components = [
        {"name": "someother-impl", "role": "workflow", "concern": "out-of-seed test"},
    ]
    plugin = _make_plugin(tmp_path, components=components)
    items = _reg_items(_audit_json(plugin))
    prefix_criticals = [
        i for i in _critical_only(items)
        if 'prefix_role_match' in i['message']
    ]
    assert not prefix_criticals, (
        f"non-seed component should not be checked in Phase 1, got: {prefix_criticals}"
    )


def test_missing_hooks_monitors_emits_critical(tmp_path):
    """hooks-monitors section が registry.yaml に欠落していると critical を emit。
    REQUIRED_SECTIONS 検証の網羅性確認 (drift 4 で命名統一されたキーが正しく検証される)。
    """
    plugin = _make_plugin(tmp_path, omit_section='hooks-monitors')
    items = _reg_items(_audit_json(plugin))
    target = [
        i for i in items
        if i['severity'] == 'critical' and i['component'] == 'registry:section:hooks-monitors'
    ]
    assert target, f"missing hooks-monitors should emit critical, got items: {items}"
