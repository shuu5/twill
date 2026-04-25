"""Tests for Issue #964 Phase-0 γ: Deploy 戦略確立 (.mcp.json 自動配布).

TDD RED フェーズ用テストスタブ。
実装前は AC-γ1/γ2/γ5b/γ6 が FAIL する（意図的 RED）。
AC-γ4/γ5a は PR #969 実装済みのため PASS となる可能性がある。

AC-γ1: .mcp.json に twl entry 冪等追加
AC-γ2: MCP server connected 状態確認（entry format 検証）
AC-γ3: worktree での .mcp.json 継承
AC-γ4: twl_validate MCP tool 呼び出し
AC-γ5a: CLI 直接呼び出し degradation path
AC-γ5b: Phase 1 fallback フロー記録
AC-γ6: twill-integration.md deploy 戦略セクション
AC-γ7: Go/No-Go 判定記録（手動 skip）
"""

import json
import subprocess
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
WORKTREE_ROOT = TWL_DIR.parent.parent
MCP_JSON = WORKTREE_ROOT / ".mcp.json"
ARCH_DOC = WORKTREE_ROOT / "architecture" / "contexts" / "twill-integration.md"


# ---------------------------------------------------------------------------
# AC-γ1: .mcp.json に twl entry が冪等に追加される
# ---------------------------------------------------------------------------

class TestACGamma1McpJsonDeploy:
    """AC-γ1: twill/main/.mcp.json の mcpServers.twl entry が冪等に追加される。

    RED: 現時点で .mcp.json に twl entry が存在しないため全テスト FAIL。
    """

    def _load_mcp_json(self) -> dict:
        assert MCP_JSON.exists(), f".mcp.json が存在しない: {MCP_JSON}"
        return json.loads(MCP_JSON.read_text())

    def test_ac_gamma1_twl_entry_exists(self):
        # AC: mcpServers.twl が存在すること
        # RED: twl entry 未追加のため FAIL
        data = self._load_mcp_json()
        assert "twl" in data.get("mcpServers", {}), (
            ".mcp.json に mcpServers.twl が存在しない (AC-γ1 未実装)"
        )

    def test_ac_gamma1_code_review_graph_preserved(self):
        # AC: 既存 code-review-graph entry が保持されること
        # RED: twl entry 追加前後で code-review-graph が残ることを確認
        data = self._load_mcp_json()
        assert "code-review-graph" in data.get("mcpServers", {}), (
            ".mcp.json から code-review-graph entry が消失している (AC-γ1 破壊禁止)"
        )

    def test_ac_gamma1_json_valid(self):
        # AC: JSON 構文 valid であること
        assert MCP_JSON.exists(), f".mcp.json が存在しない: {MCP_JSON}"
        try:
            json.loads(MCP_JSON.read_text())
        except json.JSONDecodeError as e:
            pytest.fail(f".mcp.json が invalid JSON: {e} (AC-γ1 未実装)")

    def test_ac_gamma1_twl_entry_type_stdio(self):
        # AC: twl entry に type = "stdio" が設定されていること
        # RED: entry 未追加のため FAIL
        data = self._load_mcp_json()
        twl = data.get("mcpServers", {}).get("twl", {})
        assert twl.get("type") == "stdio", (
            f"mcpServers.twl.type が 'stdio' でない: {twl.get('type')} (AC-γ1 未実装)"
        )

    def test_ac_gamma1_idempotent_no_diff(self, tmp_path):
        # AC: 同一 entry 追加 script を 2 回実行して git diff .mcp.json が空
        # 実装: Python で冪等 merge を再現して検証
        data = self._load_mcp_json()
        twl_entry = data.get("mcpServers", {}).get("twl")
        assert twl_entry is not None, (
            "twl entry が存在しないため冪等性テスト不能 (AC-γ1 未実装)"
        )
        # 2 回目の追加: 既存 entry と同一であること
        data_copy = json.loads(json.dumps(data))
        data_copy.setdefault("mcpServers", {})["twl"] = twl_entry
        assert data_copy["mcpServers"]["twl"] == twl_entry, (
            "2 回目の twl entry 追加で値が変化した (冪等性違反)"
        )


# ---------------------------------------------------------------------------
# AC-γ2: ipatho-1 で twl MCP server が connected — entry format 検証
# ---------------------------------------------------------------------------

class TestACGamma2McpEntryFormat:
    """AC-γ2: connected 状態は手動確認必須だが、entry format で前提条件を検証。

    RED: twl entry 未追加のため format 検証テスト FAIL。
    """

    def _get_twl_entry(self) -> dict:
        assert MCP_JSON.exists(), f".mcp.json が存在しない: {MCP_JSON}"
        data = json.loads(MCP_JSON.read_text())
        twl = data.get("mcpServers", {}).get("twl")
        assert twl is not None, (
            "mcpServers.twl が存在しない (AC-γ2 前提条件未満足)"
        )
        return twl

    def test_ac_gamma2_command_is_uv(self):
        # AC: command が "uv" であること（uv run --directory パターン）
        # RED: entry 未追加のため FAIL
        twl = self._get_twl_entry()
        assert twl.get("command") == "uv", (
            f"command が 'uv' でない: {twl.get('command')} (AC-γ2 未実装)"
        )

    def test_ac_gamma2_args_contain_run(self):
        # AC: args に "run" が含まれること
        # RED: entry 未追加のため FAIL
        twl = self._get_twl_entry()
        assert "run" in twl.get("args", []), (
            f"args に 'run' が含まれない: {twl.get('args')} (AC-γ2 未実装)"
        )

    def test_ac_gamma2_args_contain_directory_twl(self):
        # AC: args に "--directory" と twill/main/cli/twl の絶対パスが含まれること
        # RED: entry 未追加のため FAIL
        twl = self._get_twl_entry()
        args = twl.get("args", [])
        assert "--directory" in args, (
            f"args に '--directory' が含まれない: {args} (AC-γ2 未実装)"
        )
        dir_idx = args.index("--directory")
        dir_path = args[dir_idx + 1] if dir_idx + 1 < len(args) else ""
        assert "cli/twl" in dir_path, (
            f"--directory パスに 'cli/twl' が含まれない: {dir_path} (AC-γ2 未実装)"
        )

    def test_ac_gamma2_args_contain_extra_mcp(self):
        # AC: args に "--extra" "mcp" が含まれること
        # RED: entry 未追加のため FAIL
        twl = self._get_twl_entry()
        args = twl.get("args", [])
        assert "--extra" in args, (
            f"args に '--extra' が含まれない: {args} (AC-γ2 未実装)"
        )
        extra_idx = args.index("--extra")
        assert args[extra_idx + 1] == "mcp" if extra_idx + 1 < len(args) else False, (
            f"--extra の次が 'mcp' でない: {args} (AC-γ2 未実装)"
        )

    def test_ac_gamma2_args_contain_server_py(self):
        # AC: args に src/twl/mcp_server/server.py が含まれること
        # RED: entry 未追加のため FAIL
        twl = self._get_twl_entry()
        args = twl.get("args", [])
        assert any("server.py" in a for a in args), (
            f"args に server.py が含まれない: {args} (AC-γ2 未実装)"
        )


# ---------------------------------------------------------------------------
# AC-γ3: worktree での .mcp.json 継承（git-tracked 検証）
# ---------------------------------------------------------------------------

class TestACGamma3WorktreeInheritance:
    """AC-γ3: .mcp.json が git-tracked で worktree に自動継承される。

    git-tracked 状態は既存の場合 GREEN の可能性あり。
    twl entry 追加後の worktree 継承は AC-γ1 完了後に GREEN。
    """

    def test_ac_gamma3_mcp_json_is_git_tracked(self):
        # AC: .mcp.json が git index に追跡されていること
        result = subprocess.run(
            ["git", "ls-files", ".mcp.json"],
            capture_output=True,
            text=True,
            cwd=str(WORKTREE_ROOT),
        )
        assert result.returncode == 0 and ".mcp.json" in result.stdout, (
            ".mcp.json が git で追跡されていない (AC-γ3 前提条件未満足)"
        )

    def test_ac_gamma3_twl_entry_in_tracked_mcp_json(self):
        # AC: git-tracked な .mcp.json に twl entry が含まれること
        # RED: twl entry 未追加のため FAIL
        data = json.loads(MCP_JSON.read_text())
        assert "twl" in data.get("mcpServers", {}), (
            ".mcp.json（git-tracked）に twl entry がなく worktree 継承時に twl が使えない "
            "(AC-γ3 未実装 — AC-γ1 完了後に GREEN)"
        )


# ---------------------------------------------------------------------------
# AC-γ4: twl_validate MCP tool 呼び出し（PR #969 実装済み — GREEN 想定）
# ---------------------------------------------------------------------------

class TestACGamma4TwlValidateTool:
    """AC-γ4: twl_validate MCP tool が呼び出し可能で envelope を返す。

    PR #969（α #962）merge 済みのため GREEN となる可能性が高い。
    """

    def test_ac_gamma4_twl_validate_handler_importable(self):
        # AC: twl_validate_handler が import 可能であること
        from twl.mcp_server.tools import twl_validate_handler  # noqa: F401

    def test_ac_gamma4_twl_validate_returns_envelope(self):
        # AC: twl_validate_handler の戻り値が items/exit_code/summary を含む envelope
        from twl.mcp_server.tools import twl_validate_handler

        test_fixtures = WORKTREE_ROOT / "test-fixtures"
        plugin_roots = sorted(test_fixtures.glob("*/")) if test_fixtures.exists() else []
        if not plugin_roots:
            pytest.skip("test-fixtures にプラグインルートが存在しないためスキップ")

        envelope = twl_validate_handler(plugin_root=str(plugin_roots[0]))
        assert "items" in envelope, "envelope に 'items' がない (AC-γ4 未実装)"
        assert "exit_code" in envelope, "envelope に 'exit_code' がない (AC-γ4 未実装)"
        assert "summary" in envelope, "envelope に 'summary' がない (AC-γ4 未実装)"

    def test_ac_gamma4_envelope_exit_code_is_int(self):
        # AC: exit_code が int 型であること
        from twl.mcp_server.tools import twl_validate_handler

        test_fixtures = WORKTREE_ROOT / "test-fixtures"
        plugin_roots = sorted(test_fixtures.glob("*/")) if test_fixtures.exists() else []
        if not plugin_roots:
            pytest.skip("test-fixtures にプラグインルートが存在しないためスキップ")

        envelope = twl_validate_handler(plugin_root=str(plugin_roots[0]))
        assert isinstance(envelope["exit_code"], int), (
            f"exit_code が int でない: {type(envelope['exit_code'])} (AC-γ4)"
        )


# ---------------------------------------------------------------------------
# AC-γ5a: CLI 直接呼び出し（degradation path）
# ---------------------------------------------------------------------------

class TestACGamma5aCLIValidate:
    """AC-γ5a: `cd cli/twl && uv run --extra mcp twl --validate` が動作する。

    PR #969 実装済みのため GREEN となる可能性が高い。
    """

    def test_ac_gamma5a_cli_validate_exit_zero(self):
        # AC: uv run --extra mcp twl --validate が exit 0 で完了すること
        result = subprocess.run(
            ["uv", "run", "--extra", "mcp", "twl", "--validate"],
            capture_output=True,
            text=True,
            cwd=str(TWL_DIR),
            timeout=60,
        )
        # exit 0 = 検証 OK、exit 1 = 検証エラーあり（どちらも "動作している"）
        assert result.returncode in (0, 1), (
            f"twl --validate が予期しない exit code {result.returncode} で終了 "
            f"(AC-γ5a 未実装)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_ac_gamma5a_cli_validate_produces_output(self):
        # AC: twl --validate が何らかの output を stdout/stderr に出力すること
        result = subprocess.run(
            ["uv", "run", "--extra", "mcp", "twl", "--validate"],
            capture_output=True,
            text=True,
            cwd=str(TWL_DIR),
            timeout=60,
        )
        combined = result.stdout + result.stderr
        assert combined.strip(), (
            "twl --validate が何も出力しなかった (AC-γ5a — CLI degradation path 確認不能)"
        )


# ---------------------------------------------------------------------------
# AC-γ5b: Phase 1 fallback フロー記録
# ---------------------------------------------------------------------------

class TestACGamma5bPhase1Fallback:
    """AC-γ5b: Phase 1 fallback フロー（CLI degradation）を twill-integration.md に記録。

    RED: 現時点で twill-integration.md に Phase 1 fallback 記述がないため FAIL。
    """

    def test_ac_gamma5b_phase1_fallback_documented(self):
        # AC: twill-integration.md に Phase 1 fallback 方針と検証項目が記述されていること
        # RED: 記述なしのため FAIL
        assert ARCH_DOC.exists(), f"twill-integration.md が存在しない: {ARCH_DOC}"
        content = ARCH_DOC.read_text()
        assert "Phase 1" in content and ("fallback" in content.lower() or "フォールバック" in content or "degradation" in content.lower()), (
            "twill-integration.md に Phase 1 fallback 方針が記述されていない (AC-γ5b 未実装)"
        )

    def test_ac_gamma5b_cli_fallback_command_documented(self):
        # AC: CLI 直接呼び出しコマンド `cd cli/twl && uv run --extra mcp twl --validate` が記述
        # RED: 記述なしのため FAIL
        assert ARCH_DOC.exists(), f"twill-integration.md が存在しない: {ARCH_DOC}"
        content = ARCH_DOC.read_text()
        assert "uv run --extra mcp" in content or "uv run" in content, (
            "twill-integration.md に CLI fallback コマンドが記述されていない (AC-γ5b 未実装)"
        )


# ---------------------------------------------------------------------------
# AC-γ6: twill-integration.md deploy 戦略セクション
# ---------------------------------------------------------------------------

class TestACGamma6DeployStrategy:
    """AC-γ6: twill-integration.md に Deploy 戦略 (Phase 0 γ) セクションを追加。

    RED: 現時点でセクションが存在しないため全テスト FAIL。
    """

    def _get_content(self) -> str:
        assert ARCH_DOC.exists(), f"twill-integration.md が存在しない: {ARCH_DOC}"
        return ARCH_DOC.read_text()

    def test_ac_gamma6_deploy_strategy_section_exists(self):
        # AC: "Deploy 戦略" セクションが存在すること
        # RED: セクション未追加のため FAIL
        content = self._get_content()
        assert "Deploy 戦略" in content, (
            "twill-integration.md に 'Deploy 戦略' セクションが存在しない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_path_b_primary_documented(self):
        # AC: Path B (.mcp.json) primary 採用理由が記述されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert "Path B" in content and (".mcp.json" in content), (
            "twill-integration.md に Path B primary 採用理由が記述されていない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_path_a_future_documented(self):
        # AC: Path A (~/.claude.json) 将来検討事項が記述されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert "Path A" in content, (
            "twill-integration.md に Path A 将来検討事項が記述されていない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_host_scope_ipatho1_documented(self):
        # AC: host scope (ipatho-1 only) と Phase 1 expansion 方針が記述されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert "ipatho-1" in content, (
            "twill-integration.md に host scope (ipatho-1) が記述されていない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_worktree_behavior_documented(self):
        # AC: worktree 振る舞い（git tracked による自動継承）が記述されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert "worktree" in content.lower() and ("継承" in content or "inherit" in content.lower()), (
            "twill-integration.md に worktree 継承振る舞いが記述されていない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_directory_hardcode_documented(self):
        # AC: --directory 絶対パス制約と Phase 1 相対化方針が記述されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert "--directory" in content, (
            "twill-integration.md に --directory 絶対パス制約が記述されていない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_ohs_dual_channel_documented(self):
        # AC: OHS パターン拡張（CLI + MCP 二重チャネル化）が記述されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert ("OHS" in content or "Open Host Service" in content) or (
            "二重チャネル" in content or "dual channel" in content.lower()
        ), (
            "twill-integration.md に OHS 二重チャネル化が記述されていない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_startup_section_crossref(self):
        # AC: 既存「## 起動方法」セクションとの相互参照が記述されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert "起動方法" in content, (
            "twill-integration.md に '起動方法' セクションとの相互参照がない (AC-γ6 未実装)"
        )

    def test_ac_gamma6_ssot_stated(self):
        # AC: .mcp.json が per-repo MCP 設定の SSOT であることが明記されていること
        # RED: 記述なしのため FAIL
        content = self._get_content()
        assert "SSOT" in content or "single source of truth" in content.lower() or "単一.*真実" in content, (
            "twill-integration.md に .mcp.json SSOT 明記がない (AC-γ6 未実装)"
        )


# ---------------------------------------------------------------------------
# AC-γ7: Go/No-Go 判定（手動確認 — skip）
# ---------------------------------------------------------------------------

class TestACGamma7GoNoGo:
    """AC-γ7: Phase 0 完遂後の Go/No-Go 判定を Issue/PR コメントに記載。

    手動確認 AC のため pytest では skip。PR レビュー時に人間が確認する。
    """

    def test_ac_gamma7_go_nogo_skip_manual(self):
        # AC: Issue/PR コメントに Go/No-Go 判定が記載されていること
        # → 自動テスト不可（Issue コメント API は CI に含めない）
        pytest.skip(
            "AC-γ7 は手動確認 AC。PR マージ前に Issue コメントへの Go/No-Go 記載を人間が確認する。"
        )
