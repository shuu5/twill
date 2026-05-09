"""Tests for Issue #1614: PreToolUse Bash hook HookOutput schema compliance.

TDD RED phase tests — all tests fail before implementation.

ACs from explore-summary:
- AC-1: 4 MCP validator tools return HookOutput schema-compliant JSON
- AC-2: No legacy decision="allow"/"deny" in transformed output
- AC-3: Gate behavioral compatibility preserved (deny still blocks)
- AC-4: evidence_path/matched_option_id info preserved in reason/systemMessage

HookOutput valid schema (Claude Code 2.1.x):
  decision:          "approve" | "block"      (optional)
  permissionDecision: "allow" | "deny" | "ask" (optional)
  hookSpecificOutput: dict                     (optional)
  continue:          bool                      (optional)
  suppressOutput:    bool                      (optional)
  stopReason:        str                       (optional)
  reason:            str                       (optional)
  systemMessage:     str                       (optional)
"""

from pathlib import Path

import pytest

VALID_HOOK_OUTPUT_FIELDS = frozenset({
    "decision",
    "permissionDecision",
    "hookSpecificOutput",
    "continue",
    "suppressOutput",
    "stopReason",
    "reason",
    "systemMessage",
})

VALID_DECISION_VALUES = frozenset({"approve", "block"})
VALID_PERMISSION_DECISION_VALUES = frozenset({"allow", "deny", "ask"})


def _assert_hook_output_valid(result: dict, *, context: str = "") -> None:
    prefix = f"{context}: " if context else ""
    assert isinstance(result, dict), f"{prefix}HookOutput must be a dict"
    extra = set(result.keys()) - VALID_HOOK_OUTPUT_FIELDS
    assert not extra, (
        f"{prefix}HookOutput schema violation — extra fields not allowed by Zod schema: {extra}"
    )
    if "decision" in result:
        assert result["decision"] in VALID_DECISION_VALUES, (
            f"{prefix}decision='{result['decision']}' invalid; must be 'approve' or 'block'"
        )
    if "permissionDecision" in result:
        assert result["permissionDecision"] in VALID_PERMISSION_DECISION_VALUES, (
            f"{prefix}permissionDecision='{result['permissionDecision']}' invalid"
        )


# ---------------------------------------------------------------------------
# AC-1: twl_validate_status_transition output conforms to HookOutput schema
# ---------------------------------------------------------------------------


class TestAC1StatusTransitionHookOutputSchema:
    """AC-1: twl_validate_status_transition MCP output is HookOutput-valid."""

    def test_ac1_no_op_not_item_edit_conforms_to_schema(self, tmp_path):
        # AC-1: non-item-edit command → no-op allow → HookOutput-valid output
        # RED: _to_hook_output doesn't exist → ImportError
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        raw = twl_validate_status_transition_handler(
            command="gh project item-list 6 --owner shuu5",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path),
        )
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="no-op allow")

    def test_ac1_deny_case_conforms_to_schema(self, tmp_path):
        # AC-1: Refined option ID + no evidence → deny → must produce decision="block"
        # RED: _to_hook_output doesn't exist; current raw has decision="deny" (wrong enum) + extra fields
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        raw = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci"),
        )
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="deny case")

    def test_ac1_allow_with_evidence_conforms_to_schema(self, tmp_path):
        # AC-1: Refined option ID + spec-review-session present → allow → HookOutput-valid
        # RED: current raw has decision="allow" (wrong enum) + evidence_path (extra field)
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        (tmp_path / ".spec-review-session-1614test.json").write_text("{}")
        raw = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent-ci"),
        )
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="allow with evidence")


# ---------------------------------------------------------------------------
# AC-1: twl_validate_issue_create output conforms to HookOutput schema
# ---------------------------------------------------------------------------


class TestAC1IssueCreateHookOutputSchema:
    """AC-1: twl_validate_issue_create MCP output is HookOutput-valid."""

    def test_ac1_no_op_not_gh_issue_create_conforms_to_schema(self, tmp_path):
        # AC-1: non-gh-issue-create command → no-op → HookOutput-valid
        # RED: _to_hook_output doesn't exist; current raw has extra field evidence_path
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_issue_create_handler  # noqa: PLC0415

        raw = twl_validate_issue_create_handler(
            command="git status",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path),
        )
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="no-op")

    def test_ac1_deny_case_conforms_to_schema(self, tmp_path):
        # AC-1: unauthorized gh issue create → deny → must produce decision="block"
        # RED: current raw has decision="deny" (wrong enum) + evidence_path (extra field)
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_issue_create_handler  # noqa: PLC0415

        raw = twl_validate_issue_create_handler(
            command="gh issue create --title 'unauthorized issue'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="deny case")


# ---------------------------------------------------------------------------
# AC-1: twl_validate_merge output conforms to HookOutput schema
# ---------------------------------------------------------------------------


class TestAC1ValidateMergeHookOutputSchema:
    """AC-1: twl_validate_merge MCP output is HookOutput-valid."""

    def test_ac1_merge_guard_result_conforms_to_schema(self):
        # AC-1: merge handler returns {ok, branch, exit_code, summary} — all extra fields
        # RED: _to_hook_output doesn't exist; current raw has {ok, branch, base, exit_code, summary}
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_merge_handler  # noqa: PLC0415

        raw = twl_validate_merge_handler(branch="feat/1614-test", base="main")
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="merge guard")

    def test_ac1_merge_timeout_result_conforms_to_schema(self):
        # AC-1: timeout result {ok: False, error: "timeout"} must also be HookOutput-valid
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_merge_handler  # noqa: PLC0415

        raw = twl_validate_merge_handler(branch="test", base="main", timeout_sec=0)
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="merge timeout")


# ---------------------------------------------------------------------------
# AC-1: twl_validate_commit output conforms to HookOutput schema
# ---------------------------------------------------------------------------


class TestAC1ValidateCommitHookOutputSchema:
    """AC-1: twl_validate_commit MCP output is HookOutput-valid."""

    def test_ac1_commit_no_violations_conforms_to_schema(self):
        # AC-1: commit handler returns {ok, items, exit_code, summary, commit_message} — extra fields
        # RED: _to_hook_output doesn't exist; current raw has {ok, items, exit_code, summary, commit_message}
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_commit_handler  # noqa: PLC0415

        raw = twl_validate_commit_handler(
            command='git commit -m "feat: valid commit message"',
            files=[],
        )
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="commit no violations")

    def test_ac1_commit_timeout_result_conforms_to_schema(self):
        # AC-1: timeout result must also be HookOutput-valid
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_commit_handler  # noqa: PLC0415

        raw = twl_validate_commit_handler(
            command='git commit -m "feat: test"',
            files=[],
            timeout_sec=0,
        )
        result = _to_hook_output(raw)
        _assert_hook_output_valid(result, context="commit timeout")


# ---------------------------------------------------------------------------
# AC-2: No legacy decision="allow"/"deny" in transformed output
# ---------------------------------------------------------------------------


class TestAC2NoLegacyDecisionEnum:
    """AC-2: Transformed MCP output must not contain decision='allow' or decision='deny'."""

    def test_ac2_status_transition_no_allow_decision(self, tmp_path):
        # AC-2: no-op allow must not produce decision="allow" (use "approve" or omit)
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        raw = twl_validate_status_transition_handler(
            command="gh project item-list 6",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path),
        )
        result = _to_hook_output(raw)
        assert result.get("decision") != "allow", (
            "'allow' is not a valid decision value — use 'approve' (Claude Code 2.1.x schema)"
        )
        assert result.get("decision") != "deny", (
            "'deny' is not a valid decision value — use 'block' (Claude Code 2.1.x schema)"
        )

    def test_ac2_issue_create_no_allow_decision(self, tmp_path):
        # AC-2: issue_create no-op must not produce decision="allow"
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_issue_create_handler  # noqa: PLC0415

        raw = twl_validate_issue_create_handler(
            command="git status",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path),
        )
        result = _to_hook_output(raw)
        assert result.get("decision") != "allow"
        assert result.get("decision") != "deny"


# ---------------------------------------------------------------------------
# AC-3: Gate behavioral compatibility preserved
# ---------------------------------------------------------------------------


class TestAC3BehavioralCompatibility:
    """AC-3: deny still produces a blocking decision after transformation."""

    def test_ac3_status_transition_deny_maps_to_block(self, tmp_path):
        # AC-3: deny (no evidence) → must still block after transformation
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        raw = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "no-evidence"),
            controller_issue_dir=str(tmp_path / "no-evidence"),
        )
        result = _to_hook_output(raw)
        is_block = result.get("decision") == "block" or result.get("permissionDecision") == "deny"
        assert is_block, f"deny case must produce blocking signal, got: {result}"

    def test_ac3_status_transition_allow_is_not_block(self, tmp_path):
        # AC-3: allow (with evidence) → must NOT produce blocking decision
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        (tmp_path / ".spec-review-session-ac3test.json").write_text("{}")
        raw = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )
        result = _to_hook_output(raw)
        is_block = result.get("decision") == "block" or result.get("permissionDecision") == "deny"
        assert not is_block, f"allow case must not produce blocking signal, got: {result}"

    def test_ac3_issue_create_deny_maps_to_block(self, tmp_path):
        # AC-3: unauthorized gh issue create deny → must block after transformation
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_issue_create_handler  # noqa: PLC0415

        raw = twl_validate_issue_create_handler(
            command="gh issue create --title 'unauthorized'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )
        result = _to_hook_output(raw)
        is_block = result.get("decision") == "block" or result.get("permissionDecision") == "deny"
        assert is_block, f"deny case must produce blocking signal, got: {result}"


# ---------------------------------------------------------------------------
# AC-4: evidence_path / matched_option_id info preserved in reason/systemMessage
# ---------------------------------------------------------------------------


class TestAC4EvidenceInfoPreserved:
    """AC-4: evidence_path info must appear in reason or systemMessage (not as extra key)."""

    def test_ac4_evidence_path_not_top_level_key(self, tmp_path):
        # AC-4: evidence_path must NOT be a top-level HookOutput key (Zod strict violation)
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        (tmp_path / ".spec-review-session-evidence-test.json").write_text("{}")
        raw = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )
        result = _to_hook_output(raw)
        assert "evidence_path" not in result, (
            "evidence_path must not be a top-level key in HookOutput (Zod strict violation)"
        )
        assert "matched_option_id" not in result, (
            "matched_option_id must not be a top-level key in HookOutput"
        )

    def test_ac4_evidence_path_info_in_reason_or_systemmessage(self, tmp_path):
        # AC-4: when evidence_path is non-null, its info must appear in reason or systemMessage
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_status_transition_handler  # noqa: PLC0415

        spec_file = tmp_path / ".spec-review-session-9999evidence.json"
        spec_file.write_text("{}")
        raw = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )
        result = _to_hook_output(raw)
        combined_text = (result.get("reason") or "") + (result.get("systemMessage") or "")
        assert spec_file.name in combined_text or "evidence" in combined_text.lower(), (
            f"evidence_path info (.spec-review-session-9999evidence.json) must be preserved "
            f"in reason or systemMessage, got: {result}"
        )

    def test_ac4_issue_create_evidence_path_not_top_level(self, tmp_path):
        # AC-4: twl_validate_issue_create evidence_path must not be a top-level key
        # RED: _to_hook_output doesn't exist
        from twl.mcp_server.tools import _to_hook_output  # noqa: PLC0415
        from twl.mcp_server.tools import twl_validate_issue_create_handler  # noqa: PLC0415

        raw = twl_validate_issue_create_handler(
            command="gh issue create --title 'test'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )
        result = _to_hook_output(raw)
        assert "evidence_path" not in result, (
            "evidence_path must not be a top-level HookOutput key"
        )
