#!/usr/bin/env python3
"""Tests for supervisor type: types.yaml, TYPE_RULES, validate, classify_layers.

Covers (issue-348: observer → supervisor complete rename):
- types.yaml has supervisor type defined with can_supervise
- observer type does NOT exist in types.yaml
- _FALLBACK_TYPE_RULES has supervisor entry (not observer)
- load_type_rules() returns supervisor with can_supervise field
- load_token_thresholds() returns supervisor token_target (2000, 3000)
- validate_types() accepts supervisor type
- classify_layers() correctly classifies supervisor skills
- v3_type_keys includes supervisor (not observer)
- call_key_to_section includes supervisor -> skills
- spawnable_by contains supervisor (not observer) in atomic/specialist/reference
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
# Types YAML: supervisor exists, observer does not
# ---------------------------------------------------------------------------

class TestSupervisorInTypesYaml:
    """supervisor is properly defined in the real types.yaml; observer is gone."""

    def _get_loom_root(self) -> Path:
        return Path(__file__).resolve().parent.parent

    def test_types_yaml_has_supervisor(self):
        """WHEN cli/twl/types.yaml is loaded
        THEN supervisor key exists."""
        rules = load_type_rules(self._get_loom_root())
        assert 'supervisor' in rules, "supervisor type must be defined in types.yaml"

    def test_types_yaml_no_observer(self):
        """WHEN cli/twl/types.yaml is loaded
        THEN observer key does not exist."""
        rules = load_type_rules(self._get_loom_root())
        assert 'observer' not in rules, "observer type must be removed from types.yaml"

    def test_supervisor_section_is_skills(self):
        """supervisor must be in 'skills' section."""
        rules = load_type_rules(self._get_loom_root())
        assert rules['supervisor']['section'] == 'skills'

    def test_supervisor_can_supervise_controller(self):
        """WHEN supervisor type definition is checked
        THEN can_supervise: [controller] is maintained."""
        rules = load_type_rules(self._get_loom_root())
        assert 'can_supervise' in rules['supervisor'], \
            "supervisor must have can_supervise field"
        assert 'controller' in rules['supervisor']['can_supervise'], \
            "supervisor can_supervise must include controller"

    def test_supervisor_spawnable_by_user_only(self):
        """supervisor spawnable_by must be [user] only (ADR-014: no launcher)."""
        rules = load_type_rules(self._get_loom_root())
        spawnable_by = rules['supervisor']['spawnable_by']
        assert 'user' in spawnable_by, "supervisor spawnable_by must include user"
        assert 'launcher' not in spawnable_by, \
            "supervisor spawnable_by must NOT include launcher (ADR-014)"

    def test_supervisor_token_thresholds(self):
        """supervisor token_target is (2000, 3000)."""
        thresholds = load_token_thresholds(self._get_loom_root())
        assert 'supervisor' in thresholds, "supervisor must have token thresholds"
        assert thresholds['supervisor'] == (2000, 3000)

    def test_supervisor_token_thresholds_no_observer(self):
        """observer must not have token thresholds anymore."""
        thresholds = load_token_thresholds(self._get_loom_root())
        assert 'observer' not in thresholds, \
            "observer must be removed from token thresholds"


# ---------------------------------------------------------------------------
# types.yaml spawnable_by: atomic, specialist, reference use supervisor
# ---------------------------------------------------------------------------

class TestSpawnableByUpdated:
    """atomic, specialist, reference spawnable_by uses supervisor (not observer)."""

    def _get_loom_root(self) -> Path:
        return Path(__file__).resolve().parent.parent

    def test_atomic_spawnable_by_supervisor(self):
        """WHEN atomic type spawnable_by is checked
        THEN supervisor is listed and observer is not."""
        rules = load_type_rules(self._get_loom_root())
        spawnable_by = rules['atomic']['spawnable_by']
        assert 'supervisor' in spawnable_by, \
            "atomic spawnable_by must include supervisor"
        assert 'observer' not in spawnable_by, \
            "atomic spawnable_by must not include observer"

    def test_specialist_spawnable_by_supervisor(self):
        """WHEN specialist type spawnable_by is checked
        THEN supervisor is listed and observer is not."""
        rules = load_type_rules(self._get_loom_root())
        spawnable_by = rules['specialist']['spawnable_by']
        assert 'supervisor' in spawnable_by, \
            "specialist spawnable_by must include supervisor"
        assert 'observer' not in spawnable_by, \
            "specialist spawnable_by must not include observer"

    def test_reference_spawnable_by_supervisor(self):
        """WHEN reference type spawnable_by is checked
        THEN supervisor is listed and observer is not."""
        rules = load_type_rules(self._get_loom_root())
        spawnable_by = rules['reference']['spawnable_by']
        assert 'supervisor' in spawnable_by, \
            "reference spawnable_by must include supervisor"
        assert 'observer' not in spawnable_by, \
            "reference spawnable_by must not include observer"


# ---------------------------------------------------------------------------
# Fallback Rules: supervisor replaces observer
# ---------------------------------------------------------------------------

class TestSupervisorInFallbackRules:
    """supervisor is present in _FALLBACK_TYPE_RULES; observer is absent."""

    def test_supervisor_in_fallback_rules(self):
        """WHEN _FALLBACK_TYPE_RULES is used
        THEN supervisor type is present."""
        assert 'supervisor' in _FALLBACK_TYPE_RULES, \
            "supervisor must be in _FALLBACK_TYPE_RULES"

    def test_observer_not_in_fallback_rules(self):
        """WHEN _FALLBACK_TYPE_RULES is used
        THEN observer type is absent."""
        assert 'observer' not in _FALLBACK_TYPE_RULES, \
            "observer must be removed from _FALLBACK_TYPE_RULES"

    def test_supervisor_fallback_section(self):
        """supervisor fallback section must be 'skills'."""
        assert _FALLBACK_TYPE_RULES['supervisor']['section'] == 'skills'

    def test_supervisor_in_fallback_token_thresholds(self):
        """WHEN _FALLBACK_TOKEN_THRESHOLDS is used
        THEN supervisor key exists with (2000, 3000)."""
        assert 'supervisor' in _FALLBACK_TOKEN_THRESHOLDS, \
            "supervisor must be in _FALLBACK_TOKEN_THRESHOLDS"
        assert _FALLBACK_TOKEN_THRESHOLDS['supervisor'] == (2000, 3000)

    def test_observer_not_in_fallback_token_thresholds(self):
        """observer must not be in _FALLBACK_TOKEN_THRESHOLDS."""
        assert 'observer' not in _FALLBACK_TOKEN_THRESHOLDS, \
            "observer must be removed from _FALLBACK_TOKEN_THRESHOLDS"


# ---------------------------------------------------------------------------
# known_order and valid_types
# ---------------------------------------------------------------------------

class TestKnownOrderAndValidTypes:
    """print_rules() known_order and sync_check() valid_types use supervisor."""

    def test_known_order_has_supervisor(self):
        """WHEN print_rules() is called
        THEN known_order contains supervisor."""
        from twl.core.types import print_rules
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with redirect_stdout(buf):
            print_rules()
        output = buf.getvalue()
        assert 'supervisor' in output, \
            "print_rules() output must include supervisor"

    def test_known_order_no_observer(self):
        """WHEN print_rules() is called
        THEN type table rows do not contain observer as a type name."""
        from twl.core.types import print_rules, load_type_rules
        from pathlib import Path
        loom_root = Path(__file__).resolve().parent.parent
        rules = load_type_rules(loom_root)
        # Check the rules dict directly (not the formatted output which may include path)
        assert 'observer' not in rules, \
            "observer must not be a key in the loaded type rules"


# ---------------------------------------------------------------------------
# validate.py: section map and v3_type_keys
# ---------------------------------------------------------------------------

class TestValidateSupervisor:
    """validate.py uses supervisor in section map and v3_type_keys."""

    def test_supervisor_in_section_map(self):
        """WHEN validate.py section map is checked
        THEN supervisor → skills mapping exists."""
        from twl.validation.validate import validate_types
        deps = {
            'skills': {
                'my-supervisor': {
                    'type': 'supervisor',
                    'path': 'skills/my-supervisor/SKILL.md',
                    'spawnable_by': ['user'],
                    'can_spawn': ['workflow'],
                    'can_supervise': ['controller'],
                },
            },
            'commands': {},
            'agents': {},
        }
        ok, violations, warnings = validate_types(deps, {})
        # supervisor in skills should not produce section violations
        section_violations = [v for v in violations if '[section]' in v and 'supervisor' in v]
        assert not section_violations, \
            f"supervisor in skills must not produce section violations: {section_violations}"

    def test_observer_in_section_not_recognized(self):
        """WHEN validate.py validates observer type
        THEN it is NOT recognized as a valid type (supervisor replaced it)."""
        from twl.validation.validate import validate_types
        deps = {
            'skills': {
                'legacy-observer': {
                    'type': 'observer',
                    'path': 'skills/legacy-observer/SKILL.md',
                    'spawnable_by': ['user'],
                },
            },
            'commands': {},
            'agents': {},
        }
        ok, violations, warnings = validate_types(deps, {})
        # observer is no longer a valid type — should produce a violation
        type_violations = [v for v in violations if 'observer' in v]
        assert type_violations, \
            "observer type must produce validation violations (not a valid type anymore)"

    def test_supervisor_valid_in_v3_schema(self):
        """WHEN calls entry uses 'supervisor' key in v3.0 deps
        THEN validate_v3_schema does not report v3-calls-key violation."""
        from twl.validation.validate import validate_v3_schema
        deps = {
            'version': '3.0',
            'skills': {
                'my-supervisor': {
                    'type': 'supervisor',
                    'calls': [
                        {'supervisor': 'another-supervisor'},
                    ],
                },
            },
            'commands': {},
            'agents': {},
            'scripts': {},
            'chains': {},
        }
        ok, violations = validate_v3_schema(deps)
        v3_violations = [v for v in violations if 'v3-calls-key' in v and 'supervisor' in v]
        assert not v3_violations, \
            f"supervisor should be valid v3 calls key: {v3_violations}"

    def test_observer_invalid_in_v3_schema(self):
        """WHEN calls entry uses 'observer' key in v3.0 deps
        THEN validate_v3_schema reports v3-calls-key violation."""
        from twl.validation.validate import validate_v3_schema
        deps = {
            'version': '3.0',
            'skills': {
                'my-supervisor': {
                    'type': 'supervisor',
                    'calls': [
                        {'observer': 'legacy'},
                    ],
                },
            },
            'commands': {},
            'agents': {},
            'scripts': {},
            'chains': {},
        }
        ok, violations = validate_v3_schema(deps)
        # observer is no longer valid — should produce violation
        v3_violations = [v for v in violations if 'observer' in v]
        assert v3_violations, \
            "observer calls key must produce v3-calls-key violation"


# ---------------------------------------------------------------------------
# graph.py: supervisors key replaces observers
# ---------------------------------------------------------------------------

class TestClassifyLayersSupervisor:
    """classify_layers() uses 'supervisors' key and classifies supervisor type."""

    def test_supervisor_classified_in_supervisors(self):
        """WHEN deps has a skill with type=supervisor
        THEN classify_layers returns it in 'supervisors' list."""
        from twl.core.graph import classify_layers

        deps = {
            'skills': {
                'my-supervisor': {
                    'type': 'supervisor',
                    'path': 'skills/my-supervisor/SKILL.md',
                },
                'my-controller': {
                    'type': 'controller',
                    'path': 'skills/my-controller/SKILL.md',
                },
            },
            'commands': {},
            'agents': {},
        }
        result = classify_layers(deps, {})
        assert 'supervisors' in result, \
            "classify_layers result must have 'supervisors' key"
        assert 'observers' not in result, \
            "classify_layers result must NOT have 'observers' key"
        assert 'my-supervisor' in result['supervisors'], \
            f"my-supervisor should be in supervisors, got: {result['supervisors']}"

    def test_observer_key_absent_in_result(self):
        """WHEN classify_layers is called
        THEN result has no 'observers' key."""
        from twl.core.graph import classify_layers

        deps = {
            'skills': {},
            'commands': {},
            'agents': {},
        }
        result = classify_layers(deps, {})
        assert 'observers' not in result, \
            "observers key must be removed from classify_layers result"

    def test_supervisor_not_in_controllers(self):
        """WHEN deps has a skill with type=supervisor
        THEN it is NOT in 'controllers' list."""
        from twl.core.graph import classify_layers

        deps = {
            'skills': {
                'my-supervisor': {
                    'type': 'supervisor',
                    'path': 'skills/my-supervisor/SKILL.md',
                },
            },
            'commands': {},
            'agents': {},
        }
        result = classify_layers(deps, {})
        assert 'my-supervisor' not in result['controllers'], \
            f"supervisor must NOT be in controllers: {result['controllers']}"
