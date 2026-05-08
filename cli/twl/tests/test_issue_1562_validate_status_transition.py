"""Tests for Issue #1562: twl_validate_status_transition_handler MCP tool (RED フェーズ).

TDD RED フェーズ用テストスタブ。実装前は全テストが FAIL する（意図的 RED）。

AC 一覧:
- AC1: tool が gh project item-edit + Refined option ID 3d983780 パターンマッチかつ
       evidence なしのとき {decision: "deny", reason: <actionable>, evidence_path: null} を返す
- AC2: spec-review-session / Phase4-complete.json の evidence があるとき
       {decision: "allow", reason: "evidence found: <path>", evidence_path: <検出 path>} を返す
- AC3: 本 tool 範囲外 → テスト生成スキップ（out-of-scope）
- AC4: output schema は {decision: "allow"|"deny", reason: str, evidence_path: str|None}
       任意で matched_option_id を含めて良い
- AC5: pytest 単体テスト 11 件 (T1-T11 truth table) を追加
- AC6: tools.py の 3 箇所に entry 追加
       (handler function / @mcp.tool() decorator / fallback stub)
- AC7: 既存 In Progress option ID 47fc9ee4 の判定動作はリグレッションしない (T4/T5)
"""

from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"


# ---------------------------------------------------------------------------
# AC1 / AC2 / AC4 / AC5 / AC7: Truth Table T1-T11
# ---------------------------------------------------------------------------


class TestAC5TruthTable:
    """AC5: pytest 単体テスト 11 件 (T1-T11 truth table) を追加."""

    # ------------------------------------------------------------------
    # T1: Refined option ID + spec-review-session → allow
    # ------------------------------------------------------------------

    def test_t1_refined_option_id_with_spec_review_session(self, tmp_path):
        # AC2: spec-review-session 存在時 → allow + evidence found: <path>
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        spec_file = tmp_path / ".spec-review-session-12345.json"
        spec_file.write_text("{}", encoding="utf-8")

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "evidence found:" in result["reason"]
        assert result["evidence_path"] is not None
        assert ".spec-review-session-12345.json" in result["evidence_path"]

    # ------------------------------------------------------------------
    # T2: Refined option ID + Phase4-complete.json → allow
    # ------------------------------------------------------------------

    def test_t2_refined_option_id_with_phase4_complete(self, tmp_path):
        # AC2: Phase4-complete.json 存在時 → allow + evidence found: <path>
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        phase4_dir = tmp_path / "ci-dir" / "issue-1562"
        phase4_dir.mkdir(parents=True)
        phase4_file = phase4_dir / "Phase4-complete.json"
        phase4_file.write_text("{}", encoding="utf-8")

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "evidence found:" in result["reason"]
        assert result["evidence_path"] is not None
        assert "Phase4-complete.json" in result["evidence_path"]

    # ------------------------------------------------------------------
    # T3: Refined option ID + evidence なし → deny
    # ------------------------------------------------------------------

    def test_t3_refined_option_id_no_evidence_deny(self, tmp_path):
        # AC1: evidence なし + Refined option ID → deny + actionable reason
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "deny"
        assert result["reason"]  # actionable な reason が存在する（空でない）
        assert result["evidence_path"] is None

    # ------------------------------------------------------------------
    # T4: In Progress option ID + spec-review-session → allow (regression)
    # ------------------------------------------------------------------

    def test_t4_in_progress_option_id_with_spec_review_session(self, tmp_path):
        # AC7: 既存 In Progress option ID 47fc9ee4 + evidence あり → allow（リグレッション保証）
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        spec_file = tmp_path / ".spec-review-session-99999.json"
        spec_file.write_text("{}", encoding="utf-8")

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 47fc9ee4",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"

    # ------------------------------------------------------------------
    # T5: In Progress option ID + evidence なし → deny (regression)
    # ------------------------------------------------------------------

    def test_t5_in_progress_option_id_no_evidence_deny(self, tmp_path):
        # AC7: 既存 In Progress option ID 47fc9ee4 + evidence なし → deny（リグレッション保証）
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 47fc9ee4",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "deny"
        assert result["evidence_path"] is None

    # ------------------------------------------------------------------
    # T6: Partial match (3d9837801) → allow (word boundary: no match)
    # ------------------------------------------------------------------

    def test_t6_partial_option_id_word_boundary_allow(self, tmp_path):
        # AC1: word boundary により 3d9837801 は Refined option ID にマッチしない → no-op allow
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d9837801",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"]

    # ------------------------------------------------------------------
    # T7: item-list コマンド → allow (not item-edit)
    # ------------------------------------------------------------------

    def test_t7_item_list_command_allow(self, tmp_path):
        # AC1: gh project item-list は item-edit でないため → no-op allow
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="gh project item-list 6 --owner shuu5",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"]

    # ------------------------------------------------------------------
    # T8: Todo option ID (f75ad846) → allow (対象外)
    # ------------------------------------------------------------------

    def test_t8_todo_option_id_allow(self, tmp_path):
        # AC1: f75ad846 (Todo) は対象 option ID でないため → no-op allow
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id f75ad846",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"]

    # ------------------------------------------------------------------
    # T9: tool_name が Edit → allow (対象外ツール)
    # ------------------------------------------------------------------

    def test_t9_edit_tool_allow(self, tmp_path):
        # AC1: tool_name=Edit は Bash でないため → no-op allow
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="some arbitrary content",
            tool_name="Edit",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"]

    # ------------------------------------------------------------------
    # T10: 空コマンド → allow
    # ------------------------------------------------------------------

    def test_t10_empty_command_allow(self, tmp_path):
        # AC1: 空コマンドは対象外 → no-op allow
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"]

    # ------------------------------------------------------------------
    # T11: gh api graphql → allow (not item-edit)
    # ------------------------------------------------------------------

    def test_t11_gh_api_graphql_allow(self, tmp_path):
        # AC1: gh api graphql は item-edit でないため → no-op allow
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command='gh api graphql -f query="{ viewer { login } }"',
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert result["decision"] == "allow"
        assert "no-op" in result["reason"]


# ---------------------------------------------------------------------------
# AC4: output schema 検証
# ---------------------------------------------------------------------------


class TestAC4OutputSchema:
    """AC4: output schema は {decision, reason, evidence_path} で固定."""

    def test_ac4_allow_result_has_required_keys(self, tmp_path):
        # AC4: allow 時のレスポンスに必須キーが含まれること
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="gh project item-list 6 --owner shuu5",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert "decision" in result
        assert "reason" in result
        assert "evidence_path" in result
        assert result["decision"] in ("allow", "deny")
        assert isinstance(result["reason"], str)
        # evidence_path は str または None
        assert result["evidence_path"] is None or isinstance(result["evidence_path"], str)

    def test_ac4_deny_result_has_required_keys(self, tmp_path):
        # AC4: deny 時のレスポンスに必須キーが含まれること
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path / "nonexistent-session-dir"),
            controller_issue_dir=str(tmp_path / "nonexistent-ci-dir"),
        )

        assert "decision" in result
        assert "reason" in result
        assert "evidence_path" in result
        assert result["decision"] == "deny"
        assert isinstance(result["reason"], str)
        assert result["reason"]  # non-empty actionable message
        assert result["evidence_path"] is None

    def test_ac4_spec_review_evidence_priority_over_phase4(self, tmp_path):
        # AC2: spec-review-session が Phase4-complete より優先されること
        # RED: twl_validate_status_transition_handler 未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        # 両方作成
        spec_file = tmp_path / ".spec-review-session-77777.json"
        spec_file.write_text("{}", encoding="utf-8")
        phase4_dir = tmp_path / "ci-dir" / "issue-1562"
        phase4_dir.mkdir(parents=True)
        (phase4_dir / "Phase4-complete.json").write_text("{}", encoding="utf-8")

        result = twl_validate_status_transition_handler(
            command="gh project item-edit --project-id 6 --item-id abc --field-id XYZ --single-select-option-id 3d983780",
            tool_name="Bash",
            session_tmp_dir=str(tmp_path),
            controller_issue_dir=str(tmp_path / "ci-dir"),
        )

        assert result["decision"] == "allow"
        # spec-review-session が優先されるため evidence_path に spec-review-session が含まれる
        assert result["evidence_path"] is not None
        assert ".spec-review-session-" in result["evidence_path"]


# ---------------------------------------------------------------------------
# AC6 (optional): tools.py に twl_validate_status_transition_handler が存在すること
# ---------------------------------------------------------------------------


class TestAC6FunctionExistsInToolsPy:
    """AC6: tools.py に handler function が定義されていること."""

    def test_ac6_handler_function_importable(self):
        # AC6: tools.py に twl_validate_status_transition_handler 関数が存在する
        # RED: 関数未実装のため ImportError で FAIL
        from twl.mcp_server.tools import twl_validate_status_transition_handler

        assert callable(twl_validate_status_transition_handler), (
            "twl_validate_status_transition_handler は callable である必要があります"
        )
