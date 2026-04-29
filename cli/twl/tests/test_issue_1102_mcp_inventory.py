"""Tests for Issue #1102: feat(mcp): tools.py 棚卸し + 拡充計画策定.

TDD RED フェーズ用テストスタブ。
実装前は全テストが FAIL する（意図的 RED）。
対象ファイルが未作成のため assert path.exists() 系は全て FAIL する。

AC 一覧:
  AC1: 既存5 tool 棚卸し表
  AC2: 残15モジュール MCP 化候補 tool 案
  AC3: #1037 Tier 0 統合計画
  AC4: tool 命名規則の確定
  AC5: MCP RPC stdio deadlock 設計指針
  AC6: 子 Issue 2-5 詳細 AC 確定
  AC7: ADR-029 整合性確認
  AC8: glossary 4 語追加
  AC9: architecture spec stub 追加
"""

from pathlib import Path

import pytest

# プロジェクトルート（worktree root）
WORKTREE_ROOT = Path(__file__).resolve().parents[3]

# 対象ファイルパス
INVENTORY_MD = WORKTREE_ROOT / "plugins" / "twl" / "docs" / "mcp-tools-inventory.md"
GLOSSARY_MD = WORKTREE_ROOT / "plugins" / "twl" / "architecture" / "domain" / "glossary.md"
TWILL_INTEGRATION_MD = (
    WORKTREE_ROOT
    / "plugins"
    / "twl"
    / "architecture"
    / "domain"
    / "contexts"
    / "twill-integration.md"
)


# ---------------------------------------------------------------------------
# AC1: 既存5 tool 棚卸し表
# ---------------------------------------------------------------------------


class TestAC11InventoryExists:
    """AC1-1: plugins/twl/docs/mcp-tools-inventory.md が存在する."""

    def test_ac1_1_inventory_file_exists(self):
        # AC: mcp-tools-inventory.md が存在する
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"mcp-tools-inventory.md が存在しない: {INVENTORY_MD}"


class TestAC12FiveToolNames:
    """AC1-2: 5 tool 名が全て inventory に記載されている."""

    def test_ac1_2_twl_validate_in_inventory(self):
        # AC: twl_validate が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_validate" in content, "twl_validate が inventory に記載されていない"

    def test_ac1_2_twl_audit_in_inventory(self):
        # AC: twl_audit が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_audit" in content, "twl_audit が inventory に記載されていない"

    def test_ac1_2_twl_check_in_inventory(self):
        # AC: twl_check が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_check" in content, "twl_check が inventory に記載されていない"

    def test_ac1_2_twl_state_read_in_inventory(self):
        # AC: twl_state_read が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_state_read" in content, "twl_state_read が inventory に記載されていない"

    def test_ac1_2_twl_state_write_in_inventory(self):
        # AC: twl_state_write が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_state_write" in content, "twl_state_write が inventory に記載されていない"


class TestAC13HybridPath5Principles:
    """AC1-3: Hybrid Path 5 原則が inventory に記載されている."""

    def test_ac1_3_handler_pure_principle(self):
        # AC: Hybrid Path 原則 "handler pure" が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "handler pure" in content, "handler pure 原則が inventory に記載されていない"

    def test_ac1_3_json_dumps_principle(self):
        # AC: Hybrid Path 原則 "json.dumps" が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "json.dumps" in content, "json.dumps 原則が inventory に記載されていない"

    def test_ac1_3_try_except_importerror_principle(self):
        # AC: Hybrid Path 原則 "try/except ImportError" が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "try/except ImportError" in content or "ImportError" in content
        ), "try/except ImportError 原則が inventory に記載されていない"

    def test_ac1_3_explicit_args_principle(self):
        # AC: Hybrid Path 原則 "明示引数" が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "明示引数" in content, "明示引数 原則が inventory に記載されていない"

    def test_ac1_3_single_file_principle(self):
        # AC: Hybrid Path 原則 "1ファイル集約" が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "1ファイル集約" in content, "1ファイル集約 原則が inventory に記載されていない"


# ---------------------------------------------------------------------------
# AC2: 残15モジュール MCP 化候補 tool 案
# ---------------------------------------------------------------------------


class TestAC21FifteenModules:
    """AC2-1: 残15モジュールが inventory に記載されている."""

    FIFTEEN_MODULES = [
        "audit",
        "audit_history",
        "chain",
        "checkpoint",
        "github",
        "init",
        "launcher",
        "mergegate",
        "orchestrator",
        "parser",
        "plan",
        "project",
        "resolve_next_workflow",
        "session",
        "worktree",
    ]

    @pytest.mark.parametrize("module_name", FIFTEEN_MODULES)
    def test_ac2_1_module_in_inventory(self, module_name):
        # AC: 残15モジュール名が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert module_name in content, f"モジュール '{module_name}' が inventory に記載されていない"


class TestAC22TotalToolCount:
    """AC2-2: 各モジュールに tool 数が確定し総 tool 数 54 の記載がある."""

    def test_ac2_2_total_tool_count_54(self):
        # AC: 総 tool 数 = 54 の記載がある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "54" in content, "総 tool 数 54 が inventory に記載されていない"

    def test_ac2_2_read_write_action_classification(self):
        # AC: read / write / action 分類が記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "read" in content, "read 分類が inventory に記載されていない"
        assert "write" in content, "write 分類が inventory に記載されていない"
        assert "action" in content, "action 分類が inventory に記載されていない"


# ---------------------------------------------------------------------------
# AC3: #1037 Tier 0 統合計画
# ---------------------------------------------------------------------------


class TestAC31ValidationTools:
    """AC3-1: 検証系 5 tool が子 2 入力として確定している."""

    def test_ac3_1_twl_validate_deps_in_inventory(self):
        # AC: twl_validate_deps が子 2 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_validate_deps" in content, "twl_validate_deps が inventory に記載されていない"

    def test_ac3_1_twl_validate_merge_in_inventory(self):
        # AC: twl_validate_merge が子 2 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_validate_merge" in content, "twl_validate_merge が inventory に記載されていない"

    def test_ac3_1_twl_validate_commit_in_inventory(self):
        # AC: twl_validate_commit が子 2 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_validate_commit" in content, "twl_validate_commit が inventory に記載されていない"

    def test_ac3_1_twl_check_completeness_in_inventory(self):
        # AC: twl_check_completeness が子 2 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_check_completeness" in content
        ), "twl_check_completeness が inventory に記載されていない"

    def test_ac3_1_twl_check_specialist_in_inventory(self):
        # AC: twl_check_specialist が子 2 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_check_specialist" in content
        ), "twl_check_specialist が inventory に記載されていない"


class TestAC32StateTools:
    """AC3-2: 状態系 3 tool が子 3 入力として確定している."""

    def test_ac3_2_twl_get_session_state_in_inventory(self):
        # AC: twl_get_session_state が子 3 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_get_session_state" in content
        ), "twl_get_session_state が inventory に記載されていない"

    def test_ac3_2_twl_get_pane_state_in_inventory(self):
        # AC: twl_get_pane_state が子 3 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_get_pane_state" in content
        ), "twl_get_pane_state が inventory に記載されていない"

    def test_ac3_2_twl_audit_session_in_inventory(self):
        # AC: twl_audit_session が子 3 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_audit_session" in content
        ), "twl_audit_session が inventory に記載されていない"


class TestAC33CommunicationTools:
    """AC3-3: 通信系 3 tool が子 5 入力として確定している."""

    def test_ac3_3_twl_send_msg_in_inventory(self):
        # AC: twl_send_msg が子 5 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_send_msg" in content, "twl_send_msg が inventory に記載されていない"

    def test_ac3_3_twl_recv_msg_in_inventory(self):
        # AC: twl_recv_msg が子 5 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "twl_recv_msg" in content, "twl_recv_msg が inventory に記載されていない"

    def test_ac3_3_twl_notify_supervisor_in_inventory(self):
        # AC: twl_notify_supervisor が子 5 入力として inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_notify_supervisor" in content
        ), "twl_notify_supervisor が inventory に記載されていない"


# ---------------------------------------------------------------------------
# AC4: tool 命名規則の確定
# ---------------------------------------------------------------------------


class TestAC41NamingConvention:
    """AC4-1: inventory に twl_<module>_<action> snake_case 命名規則が記載されている."""

    def test_ac4_1_naming_convention_in_inventory(self):
        # AC: twl_<module>_<action> snake_case 命名規則が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_<module>_<action>" in content or "snake_case" in content
        ), "命名規則 twl_<module>_<action> snake_case が inventory に記載されていない"


class TestAC42ExistingFiveTools:
    """AC4-2: 既存5 tool (変更なし維持) の記載がある."""

    def test_ac4_2_existing_five_tools_unchanged(self):
        # AC: 既存5 tool (変更なし維持) の記載がある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "変更なし" in content or "維持" in content
        ), "既存5 tool の変更なし維持の記載が inventory にない"


class TestAC43ConflictAnalysis:
    """AC4-3: 衝突分析 3 ケースが inventory に記載されている."""

    def test_ac4_3_twl_audit_conflict_in_inventory(self):
        # AC: twl_audit 衝突分析が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        # 衝突分析として twl_audit と twl_audit_session が共存している記載を確認
        assert (
            "twl_audit" in content and "衝突" in content
        ), "twl_audit 衝突分析が inventory に記載されていない"

    def test_ac4_3_twl_state_read_vs_get_session_state_conflict(self):
        # AC: twl_state_read vs twl_get_session_state 衝突分析が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_state_read" in content and "twl_get_session_state" in content
        ), "twl_state_read vs twl_get_session_state の衝突分析が inventory に記載されていない"

    def test_ac4_3_twl_check_vs_check_completeness_conflict(self):
        # AC: twl_check vs twl_check_completeness 衝突分析が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "twl_check" in content and "twl_check_completeness" in content
        ), "twl_check vs twl_check_completeness の衝突分析が inventory に記載されていない"


# ---------------------------------------------------------------------------
# AC5: MCP RPC stdio deadlock 設計指針
# ---------------------------------------------------------------------------


class TestAC51H1H3Hypothesis:
    """AC5-1: #754 仮説 H1+H3 が inventory に記載されている."""

    def test_ac5_1_hypothesis_h1_in_inventory(self):
        # AC: #754 仮説 H1 が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "H1" in content or "#754" in content
        ), "#754 仮説 H1 が inventory に記載されていない"

    def test_ac5_1_hypothesis_h3_in_inventory(self):
        # AC: #754 仮説 H3 が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert "H3" in content, "#754 仮説 H3 が inventory に記載されていない"


class TestAC526DesignRules:
    """AC5-2: 子 2-5 全てに適用される 6 MUST design rule が inventory に記載されている."""

    def test_ac5_2_six_must_design_rules_in_inventory(self):
        # AC: 6 MUST design rule が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "MUST" in content
        ), "6 MUST design rule が inventory に記載されていない"
        # 6件のルールを確認するため、"MUST" が複数回登場することを確認
        must_count = content.count("MUST")
        assert must_count >= 6, f"MUST design rule が6件未満: {must_count} 件"


class TestAC53ParallelRPCRules:
    """AC5-3: 並列 RPC hang 予防ルール表 (5 観点) が inventory に記載されている."""

    def test_ac5_3_parallel_rpc_prevention_rules_in_inventory(self):
        # AC: 並列 RPC hang 予防ルール表が inventory に記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "hang" in content or "並列" in content or "deadlock" in content.lower()
        ), "並列 RPC hang 予防ルール表が inventory に記載されていない"


# ---------------------------------------------------------------------------
# AC6: 子 Issue 2-5 詳細 AC 確定
# ---------------------------------------------------------------------------


class TestAC61CommonFormatSection:
    """AC6-1: inventory に 子 Issue 共通フォーマット セクションがある (9 項目記載)."""

    def test_ac6_1_common_format_section_exists(self):
        # AC: inventory に 子 Issue 共通フォーマット セクションがある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "子Issue共通フォーマット" in content or "子 Issue 共通フォーマット" in content
        ), "子 Issue 共通フォーマット セクションが inventory に存在しない"


class TestAC62Child2Section:
    """AC6-2: inventory に 子2: 検証系 セクションがある."""

    def test_ac6_2_child2_validation_section_exists(self):
        # AC: inventory に 子2: 検証系 セクションがある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "子2" in content or "子2: 検証系" in content
        ), "子2: 検証系 セクションが inventory に存在しない"


class TestAC63Child3Section:
    """AC6-3: inventory に 子3: 状態系 セクションがある."""

    def test_ac6_3_child3_state_section_exists(self):
        # AC: inventory に 子3: 状態系 セクションがある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "子3" in content or "子3: 状態系" in content
        ), "子3: 状態系 セクションが inventory に存在しない"


class TestAC64Child4Section:
    """AC6-4: inventory に 子4: autopilot 系 セクションがある."""

    def test_ac6_4_child4_autopilot_section_exists(self):
        # AC: inventory に 子4: autopilot 系 セクションがある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "子4" in content or "子4: autopilot系" in content or "autopilot系" in content
        ), "子4: autopilot 系 セクションが inventory に存在しない"


class TestAC65Child5Section:
    """AC6-5: inventory に 子5: 通信系 (mailbox MCP hub) セクションがある."""

    def test_ac6_5_child5_communication_section_exists(self):
        # AC: inventory に 子5: 通信系 (mailbox MCP hub) セクションがある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "子5" in content or "通信系" in content or "mailbox" in content
        ), "子5: 通信系 (mailbox MCP hub) セクションが inventory に存在しない"


class TestAC67CheckboxCount:
    """AC6-7: inventory の checkbox ([ ]) が 45 個以上ある."""

    def test_ac6_7_checkbox_count_ge_45(self):
        # AC: inventory の checkbox ([ ]) が 45 個以上ある
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        checkbox_count = content.count("[ ]")
        assert (
            checkbox_count >= 45
        ), f"inventory の checkbox が 45 個未満: {checkbox_count} 個"


# ---------------------------------------------------------------------------
# AC7: ADR-029 整合性確認
# ---------------------------------------------------------------------------


class TestAC71ADR029Alignment:
    """AC7-1: inventory に ADR-029 Decision 1-4 との整合性が記載されている."""

    def test_ac7_1_adr029_alignment_in_inventory(self):
        # AC: inventory に ADR-029 Decision 1-4 との整合性が記載されている
        # RED: ファイル未作成のため FAIL する
        assert INVENTORY_MD.exists(), f"inventory ファイルが存在しない: {INVENTORY_MD}"
        content = INVENTORY_MD.read_text()
        assert (
            "ADR-029" in content or "ADR029" in content
        ), "ADR-029 との整合性が inventory に記載されていない"


# ---------------------------------------------------------------------------
# AC8: glossary 4 語追加
# ---------------------------------------------------------------------------


class TestAC81EpicDefinition:
    """AC8-1: glossary.md に "epic" が定義されている."""

    def test_ac8_1_epic_defined_in_glossary(self):
        # AC: glossary.md に "epic" が定義されている
        # RED: 定義が未追加のため FAIL する
        assert GLOSSARY_MD.exists(), f"glossary.md が存在しない: {GLOSSARY_MD}"
        content = GLOSSARY_MD.read_text()
        assert "epic" in content.lower(), "glossary.md に 'epic' が定義されていない"


class TestAC82MCPServerDefinition:
    """AC8-2: glossary.md に "MCP server" が定義されている (英語表記)."""

    def test_ac8_2_mcp_server_defined_in_glossary(self):
        # AC: glossary.md に "MCP server" が定義されている
        # RED: 定義が未追加のため FAIL する
        assert GLOSSARY_MD.exists(), f"glossary.md が存在しない: {GLOSSARY_MD}"
        content = GLOSSARY_MD.read_text()
        assert "MCP server" in content, "glossary.md に 'MCP server' が定義されていない"


class TestAC83MCPToolDefinition:
    """AC8-3: glossary.md に "MCP tool" が定義されている."""

    def test_ac8_3_mcp_tool_defined_in_glossary(self):
        # AC: glossary.md に "MCP tool" が定義されている
        # RED: 定義が未追加のため FAIL する
        assert GLOSSARY_MD.exists(), f"glossary.md が存在しない: {GLOSSARY_MD}"
        content = GLOSSARY_MD.read_text()
        assert "MCP tool" in content, "glossary.md に 'MCP tool' が定義されていない"


class TestAC84ToolsPyDefinition:
    """AC8-4: glossary.md に "tools.py" が定義されている."""

    def test_ac8_4_tools_py_defined_in_glossary(self):
        # AC: glossary.md に "tools.py" が定義されている
        # RED: 定義が未追加のため FAIL する
        assert GLOSSARY_MD.exists(), f"glossary.md が存在しない: {GLOSSARY_MD}"
        content = GLOSSARY_MD.read_text()
        assert "tools.py" in content, "glossary.md に 'tools.py' が定義されていない"


# ---------------------------------------------------------------------------
# AC9: architecture spec stub 追加
# ---------------------------------------------------------------------------


class TestAC91Phase2ChapterExists:
    """AC9-1: twill-integration.md に Phase 2 章が存在する."""

    def test_ac9_1_phase2_chapter_in_twill_integration(self):
        # AC: twill-integration.md に Phase 2 章が存在する
        # RED: Phase 2 章が未追加のため FAIL する
        assert TWILL_INTEGRATION_MD.exists(), (
            f"twill-integration.md が存在しない: {TWILL_INTEGRATION_MD}"
        )
        content = TWILL_INTEGRATION_MD.read_text()
        assert (
            "Phase 2" in content or "## Phase 2" in content
        ), "twill-integration.md に 'Phase 2' 章が存在しない"
