#!/usr/bin/env python3
"""Tests for observer type: types.yaml, TYPE_RULES, validate, classify_layers.

Covers:
- types.yaml has observer type defined with can_supervise
- _FALLBACK_TYPE_RULES has observer entry
- load_type_rules() returns observer with can_supervise field
- load_token_thresholds() returns observer token_target (2000, 3000)
- validate_types() accepts observer type
- validate_types() validates can_supervise relationships
- classify_layers() correctly classifies observer skills
- v3_type_keys includes observer
- call_key_to_section includes observer -> skills
- Existing 7 types still validate correctly (no regression)
"""

import sys
from pathlib import Path

import pytest
import yaml

SRC = str(Path(__file__).resolve().parent.parent / "src")
sys.path.insert(0, SRC)

from twl.core.types import (
    _FALLBACK_TYPE_RULES,
    _FALLBACK_TOKEN_THRESHOLDS,
    load_type_rules,
    load_token_thresholds,
)


# ---------------------------------------------------------------------------
# Types YAML + Fallback Rules
# ---------------------------------------------------------------------------

class TestObserverInFallbackRules:
    """observer is present in _FALLBACK_TYPE_RULES."""

    def test_observer_in_fallback_rules(self):
        """WHEN _FALLBACK_TYPE_RULES is used
        THEN observer type is present."""
        assert 'observer' in _FALLBACK_TYPE_RULES

    def test_observer_fallback_section(self):
        """observer fallback section must be 'skills'."""
        assert _FALLBACK_TYPE_RULES['observer']['section'] == 'skills'

    def test_observer_fallback_can_spawn(self):
        """observer fallback can_spawn includes workflow, atomic, composite, specialist, reference, script."""
        expected = {'workflow', 'atomic', 'composite', 'specialist', 'reference', 'script'}
        assert _FALLBACK_TYPE_RULES['observer']['can_spawn'] == expected

    def test_observer_fallback_spawnable_by(self):
        """observer fallback spawnable_by includes user and launcher."""
        assert 'user' in _FALLBACK_TYPE_RULES['observer']['spawnable_by']
        assert 'launcher' in _FALLBACK_TYPE_RULES['observer']['spawnable_by']

    def test_observer_in_fallback_token_thresholds(self):
        """observer is in _FALLBACK_TOKEN_THRESHOLDS with (2000, 3000)."""
        assert 'observer' in _FALLBACK_TOKEN_THRESHOLDS
        assert _FALLBACK_TOKEN_THRESHOLDS['observer'] == (2000, 3000)


class TestObserverInTypesYaml:
    """observer is properly defined in the real types.yaml."""

    def _get_loom_root(self) -> Path:
        return Path(__file__).resolve().parent.parent

    def test_types_yaml_has_observer(self):
        """WHEN real types.yaml is loaded
        THEN observer is present."""
        rules = load_type_rules(self._get_loom_root())
        assert 'observer' in rules

    def test_observer_section_is_skills(self):
        """observer must be in 'skills' section."""
        rules = load_type_rules(self._get_loom_root())
        assert rules['observer']['section'] == 'skills'

    def test_observer_can_spawn(self):
        """observer can_spawn includes the required types."""
        rules = load_type_rules(self._get_loom_root())
        expected = {'workflow', 'atomic', 'composite', 'specialist', 'reference', 'script'}
        assert rules['observer']['can_spawn'] == expected

    def test_observer_spawnable_by(self):
        """observer spawnable_by includes user and launcher."""
        rules = load_type_rules(self._get_loom_root())
        assert 'user' in rules['observer']['spawnable_by']
        assert 'launcher' in rules['observer']['spawnable_by']

    def test_observer_can_supervise(self):
        """observer can_supervise includes controller."""
        rules = load_type_rules(self._get_loom_root())
        assert 'can_supervise' in rules['observer']
        assert 'controller' in rules['observer']['can_supervise']

    def test_observer_token_thresholds(self):
        """observer token_target is (2000, 3000)."""
        thresholds = load_token_thresholds(self._get_loom_root())
        assert 'observer' in thresholds
        assert thresholds['observer'] == (2000, 3000)


class TestExistingTypesNotBroken:
    """Existing 7 types still load correctly (no regression)."""

    def _get_loom_root(self) -> Path:
        return Path(__file__).resolve().parent.parent

    def test_all_original_types_present(self):
        """WHEN types.yaml is loaded
        THEN all original 7 types remain present."""
        rules = load_type_rules(self._get_loom_root())
        for t in ('controller', 'workflow', 'atomic', 'composite', 'specialist', 'reference', 'script'):
            assert t in rules, f"Type '{t}' missing from TYPE_RULES"

    def test_eight_types_total(self):
        """WHEN types.yaml is loaded
        THEN exactly 8 types are defined (7 original + observer)."""
        rules = load_type_rules(self._get_loom_root())
        assert len(rules) == 8, f"Expected 8 types, got {len(rules)}: {sorted(rules.keys())}"

    def test_controller_token_thresholds_unchanged(self):
        """controller token_target remains (1500, 2500)."""
        thresholds = load_token_thresholds(self._get_loom_root())
        assert thresholds['controller'] == (1500, 2500)

    def test_workflow_token_thresholds_unchanged(self):
        """workflow token_target remains (1200, 2000)."""
        thresholds = load_token_thresholds(self._get_loom_root())
        assert thresholds['workflow'] == (1200, 2000)


# ---------------------------------------------------------------------------
# validate_types() with observer
# ---------------------------------------------------------------------------

class TestValidateTypesObserver:
    """validate_types() accepts observer type and validates can_supervise."""

    def _make_deps(self, extra_skills=None, extra_agents=None):
        deps = {
            'skills': {
                'my-observer': {
                    'type': 'observer',
                    'path': 'skills/my-observer/SKILL.md',
                    'spawnable_by': ['user'],
                    'can_spawn': ['workflow', 'specialist'],
                },
            },
            'commands': {},
            'agents': {},
        }
        if extra_skills:
            deps['skills'].update(extra_skills)
        if extra_agents:
            deps['agents'].update(extra_agents)
        return deps

    def test_observer_type_valid(self, tmp_path):
        """WHEN observer type component is in skills section
        THEN validate_types returns no violations."""
        from twl.validation.validate import validate_types
        deps = self._make_deps()
        ok, violations, warnings = validate_types(deps, {})
        # observer in skills is valid
        assert not any('observer' in v for v in violations), \
            f"Unexpected observer violations: {violations}"

    def test_observer_can_supervise_valid(self, tmp_path):
        """WHEN observer declares can_supervise: [controller]
        THEN validate_types returns no violations for can_supervise."""
        from twl.validation.validate import validate_types
        deps = {
            'skills': {
                'my-observer': {
                    'type': 'observer',
                    'path': 'skills/my-observer/SKILL.md',
                    'spawnable_by': ['user'],
                    'can_spawn': ['workflow'],
                    'can_supervise': ['controller'],
                },
            },
            'commands': {},
            'agents': {},
        }
        ok, violations, warnings = validate_types(deps, {})
        supervise_violations = [v for v in violations if 'can_supervise' in v]
        assert not supervise_violations, f"Unexpected can_supervise violations: {supervise_violations}"

    def test_observer_can_supervise_invalid(self, tmp_path):
        """WHEN observer declares can_supervise with invalid type
        THEN validate_types reports a can_supervise violation."""
        from twl.validation.validate import validate_types
        deps = {
            'skills': {
                'my-observer': {
                    'type': 'observer',
                    'path': 'skills/my-observer/SKILL.md',
                    'spawnable_by': ['user'],
                    'can_spawn': ['workflow'],
                    'can_supervise': ['specialist'],  # observer cannot supervise specialist
                },
            },
            'commands': {},
            'agents': {},
        }
        ok, violations, warnings = validate_types(deps, {})
        supervise_violations = [v for v in violations if 'can_supervise' in v]
        assert supervise_violations, "Expected can_supervise violation for invalid supervise target"

    def test_observer_wrong_section(self, tmp_path):
        """WHEN observer type component is placed in commands section
        THEN validate_types reports a section violation."""
        from twl.validation.validate import validate_types
        deps = {
            'skills': {},
            'commands': {
                'bad-observer': {
                    'type': 'observer',
                    'path': 'commands/bad-observer.md',
                },
            },
            'agents': {},
        }
        ok, violations, warnings = validate_types(deps, {})
        section_violations = [v for v in violations if '[section]' in v and 'observer' in v]
        assert section_violations, "Expected section violation for observer in commands"


# ---------------------------------------------------------------------------
# classify_layers() with observer
# ---------------------------------------------------------------------------

class TestClassifyLayersObserver:
    """classify_layers() correctly classifies observer skills."""

    def test_observer_classified_in_observers(self):
        """WHEN deps has a skill with type=observer
        THEN classify_layers returns it in 'observers' list."""
        from twl.core.graph import classify_layers

        deps = {
            'skills': {
                'my-observer': {
                    'type': 'observer',
                    'path': 'skills/my-observer/SKILL.md',
                },
                'my-controller': {
                    'type': 'controller',
                    'path': 'skills/my-controller/SKILL.md',
                },
            },
            'commands': {},
            'agents': {},
        }
        # graph is empty for this test
        result = classify_layers(deps, {})
        assert 'observers' in result, "classify_layers result must have 'observers' key"
        assert 'my-observer' in result['observers'], \
            f"my-observer should be in observers, got: {result['observers']}"
        assert 'my-controller' in result['controllers'], \
            f"my-controller should be in controllers, got: {result['controllers']}"

    def test_observer_not_in_controllers(self):
        """WHEN deps has a skill with type=observer
        THEN it is NOT in 'controllers' list."""
        from twl.core.graph import classify_layers

        deps = {
            'skills': {
                'my-observer': {
                    'type': 'observer',
                    'path': 'skills/my-observer/SKILL.md',
                },
            },
            'commands': {},
            'agents': {},
        }
        result = classify_layers(deps, {})
        assert 'my-observer' not in result['controllers'], \
            f"observer should NOT be in controllers: {result['controllers']}"

    def test_observer_not_in_workflows(self):
        """WHEN deps has a skill with type=observer
        THEN it is NOT in 'workflows' list."""
        from twl.core.graph import classify_layers

        deps = {
            'skills': {
                'my-observer': {
                    'type': 'observer',
                    'path': 'skills/my-observer/SKILL.md',
                },
            },
            'commands': {},
            'agents': {},
        }
        result = classify_layers(deps, {})
        assert 'my-observer' not in result['workflows'], \
            f"observer should NOT be in workflows: {result['workflows']}"


# ---------------------------------------------------------------------------
# v3_type_keys and call_key_to_section
# ---------------------------------------------------------------------------

class TestV3SchemaObserver:
    """validate_v3_schema() recognizes observer as valid type key."""

    def test_observer_call_key_valid(self):
        """WHEN calls entry uses 'observer' key in v3.0 deps
        THEN validate_v3_schema does not report v3-calls-key violation."""
        from twl.validation.validate import validate_v3_schema

        deps = {
            'version': '3.0',
            'skills': {
                'my-observer': {
                    'type': 'observer',
                    'calls': [
                        {'observer': 'another-observer'},
                    ],
                },
            },
            'commands': {},
            'agents': {},
            'scripts': {},
            'chains': {},
        }
        ok, violations = validate_v3_schema(deps)
        v3_violations = [v for v in violations if 'v3-calls-key' in v and 'observer' in v]
        assert not v3_violations, f"observer should be valid v3 calls key: {v3_violations}"
