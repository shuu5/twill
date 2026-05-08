"""Tests for Issue #1578: twl_validate_issue_create_handler MCP tool (RED フェーズ).

TDD RED フェーズ用テストスタブ。実装前は全テストが FAIL する（意図的 RED）。

AC3: mcp__twl__validate_issue_create 新設 + unit test
  - tools.py に twl_validate_issue_create_handler 追加
  - PreToolUse:Bash hook として gh issue create を検知
  - CO_EXPLORE_DONE / explore-summary ファイルを証跡として allow/deny を決定
  - outputType: "log" として settings.json に登録

RED 理由:
  `from twl.mcp_server.tools import twl_validate_issue_create_handler` が
  ImportError で失敗するため、全テストが FAIL する。
"""

from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"


# ---------------------------------------------------------------------------
# ヘルパー: handler import（RED: 未実装時は ImportError）
# ---------------------------------------------------------------------------


def _import_handler():
    """twl_validate_issue_create_handler を import する。未実装なら ImportError."""
    from twl.mcp_server.tools import twl_validate_issue_create_handler  # noqa: PLC0415

    return twl_validate_issue_create_handler


# ---------------------------------------------------------------------------
# AC3 T1: gh issue create + CO_EXPLORE_DONE 未設定 → deny
# ---------------------------------------------------------------------------


class TestDenyScenarios:
    """CO_EXPLORE_DONE 未設定 / explore-summary なし → deny のシナリオ群."""

    def test_t1_gh_issue_create_no_env_deny(self, tmp_path, monkeypatch):
        """gh issue create + CO_EXPLORE_DONE 未設定 → deny.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        result = handler(
            command="gh issue create --title 'new feature' --body 'description'",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "deny"
        assert result["reason"]  # non-empty actionable message
        assert "co-explore" in result["reason"].lower() or "explore" in result["reason"].lower()

    def test_t2_gh_issue_create_with_template_no_env_deny(self, tmp_path, monkeypatch):
        """gh issue create --template + CO_EXPLORE_DONE 未設定 → deny.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        result = handler(
            command="gh issue create --template bug_report.md --title 'bug'",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "deny"

    def test_t3_gh_issue_create_no_summary_file_deny(self, tmp_path, monkeypatch):
        """explore-summary ファイルなし + CO_EXPLORE_DONE 未設定 → deny + path hint.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        # explore_summary_dir 存在するが summary ファイルはない
        explore_dir = tmp_path / ".explore"
        explore_dir.mkdir()

        result = handler(
            command="gh issue create --title 'no summary' --body 'body'",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(explore_dir),
        )

        assert result["decision"] == "deny"
        # summary ファイルのパスへの言及が含まれること
        assert ".explore" in result["reason"] or "summary" in result["reason"].lower()


# ---------------------------------------------------------------------------
# AC3 T4-T6: allow シナリオ群
# ---------------------------------------------------------------------------


class TestAllowScenarios:
    """CO_EXPLORE_DONE=1 または explore-summary 存在 → allow のシナリオ群."""

    def test_t4_co_explore_done_env_allow(self, tmp_path, monkeypatch):
        """CO_EXPLORE_DONE=1 設定済み → allow.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        result = handler(
            command="gh issue create --title 'new feature' --body 'description'",
            tool_name="Bash",
            env={"CO_EXPLORE_DONE": "1"},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "allow"
        assert result["reason"]

    def test_t5_explore_summary_exists_allow(self, tmp_path, monkeypatch):
        """explore-summary ファイル存在 → allow（ファイル存在が証跡）.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        # explore-summary ファイルを作成
        explore_dir = tmp_path / ".explore" / "99"
        explore_dir.mkdir(parents=True)
        (explore_dir / "summary.md").write_text("# Summary\n\nContent", encoding="utf-8")

        result = handler(
            command="gh issue create --title 'with summary' --body 'body'",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(tmp_path / ".explore"),
        )

        assert result["decision"] == "allow"

    def test_t6_cross_repo_with_done_env_allow(self, tmp_path, monkeypatch):
        """--repo 指定（cross-repo）+ CO_EXPLORE_DONE=1 → allow.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        result = handler(
            command="gh issue create --repo shuu5/other-repo --title 'cross' --body 'b'",
            tool_name="Bash",
            env={"CO_EXPLORE_DONE": "1"},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "allow"


# ---------------------------------------------------------------------------
# AC3 T7-T9: gate 対象外コマンド → allow (no-op)
# ---------------------------------------------------------------------------


class TestNonTargetCommands:
    """gh issue create でないコマンドは gate 対象外 → no-op allow."""

    def test_t7_gh_pr_create_allow(self, tmp_path, monkeypatch):
        """gh pr create → allow (gate 対象外).

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        result = handler(
            command="gh pr create --title 'feat' --body 'desc'",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"].lower() or result["reason"]

    def test_t8_gh_issue_list_allow(self, tmp_path, monkeypatch):
        """gh issue list → allow (gate 対象外).

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        result = handler(
            command="gh issue list --state open",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "allow"

    def test_t9_git_commit_allow(self, tmp_path, monkeypatch):
        """git commit → allow (gh issue create でない).

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        result = handler(
            command="git commit -m 'feat: add feature'",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "allow"

    def test_t10_non_bash_tool_allow(self, tmp_path, monkeypatch):
        """tool_name=Edit → allow (Bash 以外は gate 対象外).

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        result = handler(
            command="gh issue create --title 'via edit tool' --body 'body'",
            tool_name="Edit",
            env={},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert result["decision"] == "allow"


# ---------------------------------------------------------------------------
# AC3: output schema 検証
# ---------------------------------------------------------------------------


class TestOutputSchema:
    """output schema: {decision, reason, evidence_path} の構造検証."""

    def test_schema_deny_has_required_keys(self, tmp_path, monkeypatch):
        """deny 時のレスポンスに必須キーが含まれること.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        monkeypatch.delenv("CO_EXPLORE_DONE", raising=False)

        result = handler(
            command="gh issue create --title 'test' --body 'body'",
            tool_name="Bash",
            env={},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert "decision" in result
        assert "reason" in result
        assert result["decision"] == "deny"
        assert isinstance(result["reason"], str)
        assert result["reason"]  # non-empty

    def test_schema_allow_has_required_keys(self, tmp_path, monkeypatch):
        """allow 時のレスポンスに必須キーが含まれること.

        RED: twl_validate_issue_create_handler 未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        result = handler(
            command="gh issue create --title 'test' --body 'body'",
            tool_name="Bash",
            env={"CO_EXPLORE_DONE": "1"},
            explore_summary_dir=str(tmp_path / "nonexistent-explore"),
        )

        assert "decision" in result
        assert "reason" in result
        assert result["decision"] == "allow"
        assert isinstance(result["reason"], str)


# ---------------------------------------------------------------------------
# AC3: tools.py に twl_validate_issue_create_handler が importable であること
# ---------------------------------------------------------------------------


class TestHandlerImportable:
    """tools.py に handler function が定義されていること."""

    def test_handler_function_importable(self):
        """tools.py に twl_validate_issue_create_handler が存在し callable であること.

        RED: 関数未実装のため ImportError で FAIL
        """
        handler = _import_handler()

        assert callable(handler), (
            "twl_validate_issue_create_handler は callable である必要があります"
        )

    def test_tools_py_contains_handler_definition(self):
        """tools.py のソースに twl_validate_issue_create_handler の定義が含まれること.

        RED: 関数未定義のため fail
        """
        assert TOOLS_PY.exists(), f"tools.py が見つかりません: {TOOLS_PY}"

        source = TOOLS_PY.read_text(encoding="utf-8")
        assert "twl_validate_issue_create_handler" in source, (
            "tools.py に twl_validate_issue_create_handler 定義が存在しません"
        )
