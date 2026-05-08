"""Tests for Issue #1578: twl_validate_issue_create_handler MCP tool.

AC3: mcp__twl__validate_issue_create 新設 + unit test
  - tools.py に twl_validate_issue_create_handler 追加
  - PreToolUse:Bash hook として gh issue create を検知
  - 4 allow paths: SKIP_ISSUE_GATE / co-explore-bootstrap / co-issue-phase4-create / phase3-gate
  - outputType: "log" として settings.json に登録
"""

from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"


def _import_handler():
    """twl_validate_issue_create_handler を import する."""
    from twl.mcp_server.tools import twl_validate_issue_create_handler  # noqa: PLC0415

    return twl_validate_issue_create_handler


# ---------------------------------------------------------------------------
# Deny scenarios
# ---------------------------------------------------------------------------


class TestDenyScenarios:
    """allow path なし → deny のシナリオ群."""

    def test_t1_gh_issue_create_no_allow_path_deny(self, tmp_path):
        """gh issue create + no allow path → deny."""
        handler = _import_handler()

        result = handler(
            command="gh issue create --title 'new feature' --body 'description'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "deny"
        assert result["reason"]
        assert "ADR-037" in result["reason"] or "explore" in result["reason"].lower()

    def test_t2_gh_issue_create_with_template_deny(self, tmp_path):
        """gh issue create --template + no allow path → deny."""
        handler = _import_handler()

        result = handler(
            command="gh issue create --template bug_report.md --title 'bug'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "deny"

    def test_t3_skip_without_reason_deny(self, tmp_path):
        """SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON 欠落 → deny."""
        handler = _import_handler()

        result = handler(
            command="SKIP_ISSUE_GATE=1 gh issue create --title 'no reason'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "deny"
        assert "SKIP_ISSUE_REASON" in result["reason"]

    def test_t4_co_explore_bootstrap_without_state_file_deny(self, tmp_path):
        """TWL_CALLER_AUTHZ=co-explore-bootstrap + state file なし → deny."""
        handler = _import_handler()

        # ensure no bootstrap state files in tmp_path
        for f in tmp_path.glob(".co-explore-bootstrap-*.json"):
            f.unlink()

        result = handler(
            command="TWL_CALLER_AUTHZ=co-explore-bootstrap gh issue create --title 'spoof'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "deny"
        assert "state file" in result["reason"] or "bootstrap" in result["reason"]

    def test_t5_co_issue_phase4_without_summary_deny(self, tmp_path):
        """TWL_CALLER_AUTHZ=co-issue-phase4-create + no explore-summary.md → deny."""
        handler = _import_handler()

        # controller_issue_dir exists but has no explore-summary.md
        ctrl_dir = tmp_path / ".controller-issue"
        ctrl_dir.mkdir()

        result = handler(
            command="TWL_CALLER_AUTHZ=co-issue-phase4-create gh issue create --title 'no summary'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(ctrl_dir),
        )

        assert result["decision"] == "deny"
        assert "explore-summary" in result["reason"] or "summary" in result["reason"].lower()


# ---------------------------------------------------------------------------
# Allow scenarios
# ---------------------------------------------------------------------------


class TestAllowScenarios:
    """各 allow path → allow のシナリオ群."""

    def test_t6_skip_gate_with_reason_allow(self, tmp_path):
        """SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON → allow (bypass)."""
        handler = _import_handler()

        result = handler(
            command="SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='trivial config: label rename' gh issue create --title 'x'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "allow"
        assert "bypass" in result["reason"]

    def test_t7_co_explore_bootstrap_with_state_file_allow(self, tmp_path):
        """TWL_CALLER_AUTHZ=co-explore-bootstrap + state file 存在 → allow."""
        handler = _import_handler()

        state_file = tmp_path / ".co-explore-bootstrap-abc123.json"
        state_file.write_text('{"title":"test","controller":"co-explore"}')

        result = handler(
            command="TWL_CALLER_AUTHZ=co-explore-bootstrap gh issue create --title 'new'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "allow"
        assert "co-explore-bootstrap" in result["reason"]
        assert result["evidence_path"] is not None

    def test_t8_co_issue_phase4_with_summary_allow(self, tmp_path):
        """TWL_CALLER_AUTHZ=co-issue-phase4-create + explore-summary.md 存在 → allow."""
        handler = _import_handler()

        ctrl_dir = tmp_path / ".controller-issue"
        session_dir = ctrl_dir / "test-session-123"
        session_dir.mkdir(parents=True)
        (session_dir / "explore-summary.md").write_text("# Summary\n\nContent")

        result = handler(
            command="TWL_CALLER_AUTHZ=co-issue-phase4-create gh issue create --title 'issue'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(ctrl_dir),
        )

        assert result["decision"] == "allow"
        assert "co-issue-phase4" in result["reason"]
        assert result["evidence_path"] is not None

    def test_t9_phase3_gate_file_allow(self, tmp_path):
        """phase3-gate ファイル存在 → allow (co-issue in-flight path)."""
        handler = _import_handler()

        gate_file = tmp_path / ".co-issue-phase3-gate-abc123.json"
        gate_file.write_text('{"phase3_completed":false}')

        result = handler(
            command="gh issue create --title 'in-flight'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "allow"
        assert "phase3" in result["reason"]

    def test_t10_cross_repo_with_skip_allow(self, tmp_path):
        """--repo 指定 (cross-repo) + SKIP_ISSUE_GATE → allow."""
        handler = _import_handler()

        result = handler(
            command="SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='trivial config' gh issue create --repo shuu5/other --title 'x'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert result["decision"] == "allow"


# ---------------------------------------------------------------------------
# Non-target commands → allow (no-op)
# ---------------------------------------------------------------------------


class TestNonTargetCommands:
    """gh issue create でないコマンドは gate 対象外 → no-op allow."""

    def test_t11_gh_pr_create_allow(self, tmp_path):
        """gh pr create → allow (gate 対象外)."""
        handler = _import_handler()

        result = handler(
            command="gh pr create --title 'feat' --body 'desc'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"].lower()

    def test_t12_gh_issue_list_allow(self, tmp_path):
        """gh issue list → allow (gate 対象外)."""
        handler = _import_handler()

        result = handler(
            command="gh issue list --state open",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
        )

        assert result["decision"] == "allow"

    def test_t13_git_commit_allow(self, tmp_path):
        """git commit → allow (gh issue create でない)."""
        handler = _import_handler()

        result = handler(
            command="git commit -m 'feat: add feature'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
        )

        assert result["decision"] == "allow"

    def test_t14_non_bash_tool_allow(self, tmp_path):
        """tool_name=Edit → allow (Bash 以外は gate 対象外)."""
        handler = _import_handler()

        result = handler(
            command="gh issue create --title 'via edit tool' --body 'body'",
            tool_name="Edit",
            session_tmp_dir=str(tmp_path),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"].lower()


# ---------------------------------------------------------------------------
# Output schema verification
# ---------------------------------------------------------------------------


class TestOutputSchema:
    """output schema: {decision, reason, evidence_path} の構造検証."""

    def test_schema_deny_has_required_keys(self, tmp_path):
        """deny 時のレスポンスに必須キーが含まれること."""
        handler = _import_handler()

        result = handler(
            command="gh issue create --title 'test' --body 'body'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert "decision" in result
        assert "reason" in result
        assert "evidence_path" in result
        assert result["decision"] == "deny"
        assert isinstance(result["reason"], str)
        assert result["reason"]

    def test_schema_allow_has_required_keys(self, tmp_path):
        """allow 時のレスポンスに必須キーが含まれること."""
        handler = _import_handler()

        # phase3-gate path (simplest allow)
        gate_file = tmp_path / ".co-issue-phase3-gate-xyz.json"
        gate_file.write_text('{"phase3_completed":false}')

        result = handler(
            command="gh issue create --title 'test' --body 'body'",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent"),
        )

        assert "decision" in result
        assert "reason" in result
        assert "evidence_path" in result
        assert result["decision"] == "allow"
        assert isinstance(result["reason"], str)


# ---------------------------------------------------------------------------
# tools.py に twl_validate_issue_create_handler が importable であること
# ---------------------------------------------------------------------------


class TestHandlerImportable:
    """tools.py に handler function が定義されていること."""

    def test_handler_function_importable(self):
        """tools.py に twl_validate_issue_create_handler が存在し callable であること."""
        handler = _import_handler()

        assert callable(handler), "twl_validate_issue_create_handler は callable である必要があります"

    def test_tools_py_contains_handler_definition(self):
        """tools.py のソースに twl_validate_issue_create_handler の定義が含まれること."""
        assert TOOLS_PY.exists(), f"tools.py が見つかりません: {TOOLS_PY}"

        source = TOOLS_PY.read_text(encoding="utf-8")
        assert "twl_validate_issue_create_handler" in source, (
            "tools.py に twl_validate_issue_create_handler 定義が存在しません"
        )
