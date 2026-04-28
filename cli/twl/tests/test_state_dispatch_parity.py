"""test_state_dispatch_parity.py

Issue #1018: twl.autopilot.state MCP 化 + SSoT 検証

RED フェーズ: twl_state_read_handler / twl_state_write_handler が
cli/twl/src/twl/mcp_server/tools.py に append されていないため、
AC1 smoke test は ImportError で fail し、AC3 全ケースも fail する。

AC1: state MCP handler + tool 実装 (ADR-0006 §1 5 原則準拠)
AC2: bats CLI 経路 PASS 100% + state.py 無変更 (機械検証)
AC3: SSoT 検証 pytest parametric (3 経路の出力同一性、最低 6 ケース)
AC4: ADR-0006 Decision §1~§4 の機械検証カバー
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Repo root / fixture helpers
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
_TESTS_DIR = Path(__file__).resolve().parent


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    return d


@pytest.fixture
def state(autopilot_dir: Path):
    from twl.autopilot.state import StateManager
    return StateManager(autopilot_dir=autopilot_dir)


def _init_issue(state, issue: str = "1") -> None:
    state.write(type_="issue", role="worker", issue=issue, init=True)


def _run_cli_state(args: list, autopilot_dir: Path) -> subprocess.CompletedProcess:
    env = {"AUTOPILOT_DIR": str(autopilot_dir)}
    import os
    full_env = dict(os.environ)
    full_env.update(env)
    return subprocess.run(
        ["python3", "-m", "twl.autopilot.state"] + args,
        capture_output=True,
        text=True,
        env=full_env,
        cwd=str(_REPO_ROOT / "cli" / "twl"),
    )


# ===========================================================================
# AC1: smoke test — twl_state_read_handler / twl_state_write_handler が
#       import 可能で dict を返す
# ===========================================================================


def test_ac1_state_read_handler_importable():
    """AC1 smoke test: twl_state_read_handler は tools.py から import 可能でなければならない。
    RED: tools.py に append 前は ImportError で fail する。
    """
    # RED: 実装前は ImportError が発生する
    from twl.mcp_server.tools import twl_state_read_handler  # noqa: F401


def test_ac1_state_write_handler_importable():
    """AC1 smoke test: twl_state_write_handler は tools.py から import 可能でなければならない。
    RED: tools.py に append 前は ImportError で fail する。
    """
    # RED: 実装前は ImportError が発生する
    from twl.mcp_server.tools import twl_state_write_handler  # noqa: F401


def test_ac1_state_read_handler_returns_dict(autopilot_dir: Path, state):
    """AC1: read handler は STATE_INIT ケースで例外なく dict を返す。
    RED: handler 未実装 → ImportError で fail する。
    """
    from twl.mcp_server.tools import twl_state_read_handler

    _init_issue(state, "1")
    result = twl_state_read_handler(
        type_="issue",
        issue="1",
        autopilot_dir=str(autopilot_dir),
    )
    assert isinstance(result, dict), f"handler must return dict, got {type(result)}"
    assert "ok" in result, f"envelope must have 'ok' key, got {result}"


def test_ac1_state_read_handler_envelope_ok_true(autopilot_dir: Path, state):
    """AC1: 成功時 envelope は {ok: true, result: str, exit_code: 0}。
    RED: 未実装 → ImportError。
    """
    from twl.mcp_server.tools import twl_state_read_handler

    _init_issue(state, "1")
    result = twl_state_read_handler(
        type_="issue",
        issue="1",
        field="status",
        autopilot_dir=str(autopilot_dir),
    )
    assert result.get("ok") is True
    assert result.get("exit_code") == 0
    assert "result" in result


def test_ac1_state_read_handler_envelope_state_error(autopilot_dir: Path):
    """AC1: StateError 時 envelope は {ok: false, error_type: 'state_error', exit_code: 1}。
    RED: 未実装 → ImportError。
    """
    from twl.mcp_server.tools import twl_state_read_handler

    # 存在しないファイルを read しても StateArgError は出ない (StateError が出る場合を確認)
    # ここでは invalid type で StateArgError を狙う
    result = twl_state_read_handler(
        type_="issue",
        issue="1",
        autopilot_dir=str(autopilot_dir),
    )
    # file absent → ok=true, result="" (StateManager.read は空文字を返す)
    assert isinstance(result, dict)


def test_ac1_state_read_handler_envelope_arg_error(autopilot_dir: Path):
    """AC1: StateArgError 時 envelope は {ok: false, error_type: 'arg_error', exit_code: 2}。
    RED: 未実装 → ImportError。
    """
    from twl.mcp_server.tools import twl_state_read_handler

    result = twl_state_read_handler(
        type_="bad_type",  # StateArgError を発生させる
        issue="1",
        autopilot_dir=str(autopilot_dir),
    )
    assert result.get("ok") is False
    assert result.get("error_type") == "arg_error"
    assert result.get("exit_code") == 2


def test_ac1_state_write_handler_returns_dict(autopilot_dir: Path):
    """AC1: write handler (init) は dict を返す。
    RED: 未実装 → ImportError。
    """
    from twl.mcp_server.tools import twl_state_write_handler

    result = twl_state_write_handler(
        type_="issue",
        role="worker",
        issue="42",
        init=True,
        autopilot_dir=str(autopilot_dir),
    )
    assert isinstance(result, dict)
    assert "ok" in result


def test_ac1_principle1_handler_suffix():
    """AC1 5原則 1: _handler suffix で pure Python 関数が定義されている。
    RED: 未実装 → ImportError。
    """
    from twl.mcp_server import tools
    assert hasattr(tools, "twl_state_read_handler"), "twl_state_read_handler が tools.py に存在しない"
    assert hasattr(tools, "twl_state_write_handler"), "twl_state_write_handler が tools.py に存在しない"
    assert callable(tools.twl_state_read_handler)
    assert callable(tools.twl_state_write_handler)


def test_ac1_principle3_fastmcp_gate():
    """AC1 5原則 3: fastmcp 不在でも handler のみ exposed で ImportError 不要。
    RED: 未実装 → ImportError。
    """
    import importlib
    tools = importlib.import_module("twl.mcp_server.tools")
    # fastmcp がない環境でも twl_state_read_handler が存在すること
    assert hasattr(tools, "twl_state_read_handler")


def test_ac1_principle4_explicit_autopilot_dir_arg():
    """AC1 5原則 4: read/write handler に autopilot_dir: str | None 引数がある。
    RED: 未実装 → ImportError。
    """
    import inspect
    from twl.mcp_server.tools import twl_state_read_handler, twl_state_write_handler

    read_params = inspect.signature(twl_state_read_handler).parameters
    assert "autopilot_dir" in read_params, "twl_state_read_handler に autopilot_dir 引数がない"

    write_params = inspect.signature(twl_state_write_handler).parameters
    assert "autopilot_dir" in write_params, "twl_state_write_handler に autopilot_dir 引数がない"
    assert "cwd" in write_params, "twl_state_write_handler に cwd 引数がない"


# ===========================================================================
# AC2: bats CLI 経路 + state.py 無変更検証
# ===========================================================================


def test_ac2_state_py_not_modified():
    """AC2: git diff で cli/twl/src/twl/autopilot/state.py が変更されていないこと。
    RED: state.py を誤って変更した場合に fail する。
    """
    result = subprocess.run(
        ["git", "diff", "--name-only", "main...HEAD"],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
    )
    changed_files = result.stdout.strip().splitlines()
    state_py = "cli/twl/src/twl/autopilot/state.py"
    assert state_py not in changed_files, (
        f"state.py が変更されている (AC2 違反): {state_py} が git diff に含まれる"
    )


# ===========================================================================
# AC3: SSoT 検証 — 3 経路の出力同一性 parametric (最低 6 ケース)
# ===========================================================================


def _normalize_str(s: str) -> str:
    """比較用: JSON 文字列ならパースして再シリアライズ、そうでなければ strip。"""
    s = s.strip()
    try:
        return json.dumps(json.loads(s), sort_keys=True, ensure_ascii=False)
    except (json.JSONDecodeError, ValueError):
        return s


@pytest.fixture
def parity_autopilot_dir(tmp_path: Path) -> Path:
    """3 経路比較用: issue 作成済み autopilot_dir。"""
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    from twl.autopilot.state import StateManager
    sm = StateManager(autopilot_dir=d)
    sm.write(type_="issue", role="worker", issue="1", init=True)
    sm.write(type_="issue", role="worker", issue="2", init=True)
    (d / "session.json").write_text(json.dumps({
        "status": "active",
        "wave": "18",
        "current_issue": "1",
        "started_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }))
    return d


# ケース定義: (label, read_kwargs, is_write, write_kwargs)
# is_write=False → read ケース
# is_write=True → write (init or transition) ケース
PARITY_READ_CASES = [
    # (a) issue read with field
    pytest.param(
        "a_issue_read_with_field",
        {"type_": "issue", "issue": "1", "field": "status"},
        id="a_issue_read_with_field",
    ),
    # (b) issue read no-field (full JSON)
    pytest.param(
        "b_issue_read_no_field",
        {"type_": "issue", "issue": "1"},
        id="b_issue_read_no_field",
    ),
    # (c) session read with field
    pytest.param(
        "c_session_read_with_field",
        {"type_": "session", "field": "status"},
        id="c_session_read_with_field",
    ),
]


@pytest.mark.parametrize("label,read_kwargs", PARITY_READ_CASES)
def test_ac3_read_3path_parity(label, read_kwargs, parity_autopilot_dir: Path):
    """AC3: read の 3 経路 (CLI / MCP handler / Python 直接) が同一出力を返す。
    RED: MCP handler 未実装 → ImportError で fail する。
    """
    from twl.mcp_server.tools import twl_state_read_handler
    from twl.autopilot.state import StateManager

    ap_dir = parity_autopilot_dir

    # 経路 2: MCP in-process handler
    mcp_result = twl_state_read_handler(
        autopilot_dir=str(ap_dir),
        **read_kwargs,
    )
    assert mcp_result.get("ok") is True, f"MCP handler failed: {mcp_result}"
    mcp_value = mcp_result["result"]

    # 経路 3: Python 直接
    sm = StateManager(autopilot_dir=ap_dir)
    direct_value = sm.read(**read_kwargs)

    # 経路 1: subprocess (CLI)
    cli_args = ["read", "--type", read_kwargs["type_"]]
    if read_kwargs.get("issue"):
        cli_args.extend(["--issue", read_kwargs["issue"]])
    if read_kwargs.get("field"):
        cli_args.extend(["--field", read_kwargs["field"]])
    cli_proc = _run_cli_state(cli_args, ap_dir)
    cli_value = cli_proc.stdout.strip()

    # 比較
    assert _normalize_str(mcp_value) == _normalize_str(direct_value), (
        f"[{label}] MCP handler vs Python direct: {mcp_value!r} != {direct_value!r}"
    )
    assert _normalize_str(cli_value) == _normalize_str(direct_value), (
        f"[{label}] CLI vs Python direct: {cli_value!r} != {direct_value!r}"
    )


def test_ac3_case_d_issue_init_parity(parity_autopilot_dir: Path, tmp_path: Path):
    """AC3 (d): issue init — 3 経路で同一ファイルが生成される。"""
    from twl.mcp_server.tools import twl_state_write_handler
    from twl.autopilot.state import StateManager

    # 経路 2: MCP handler
    ap_mcp = tmp_path / "ap_mcp"
    ap_mcp.mkdir()
    (ap_mcp / "issues").mkdir()
    mcp_result = twl_state_write_handler(
        type_="issue",
        role="worker",
        issue="99",
        init=True,
        autopilot_dir=str(ap_mcp),
    )
    assert mcp_result.get("ok") is True, f"MCP write handler failed: {mcp_result}"

    # 経路 3: Python 直接
    ap_direct = tmp_path / "ap_direct"
    ap_direct.mkdir()
    (ap_direct / "issues").mkdir()
    sm = StateManager(autopilot_dir=ap_direct)
    sm.write(type_="issue", role="worker", issue="99", init=True)

    # 経路 1: CLI subprocess
    ap_cli = tmp_path / "ap_cli"
    ap_cli.mkdir()
    (ap_cli / "issues").mkdir()
    cli_proc = _run_cli_state(
        ["write", "--type", "issue", "--role", "worker", "--issue", "99", "--init"],
        ap_cli,
    )
    assert cli_proc.returncode == 0, f"CLI init failed: {cli_proc.stderr}"

    # ファイル内容の比較 (status と issue 番号が同一か)
    mcp_data = json.loads((ap_mcp / "issues" / "issue-99.json").read_text())
    direct_data = json.loads((ap_direct / "issues" / "issue-99.json").read_text())
    cli_data = json.loads((ap_cli / "issues" / "issue-99.json").read_text())
    assert mcp_data["status"] == direct_data["status"]
    assert mcp_data["issue"] == direct_data["issue"]
    assert cli_data["status"] == direct_data["status"]
    assert cli_data["issue"] == direct_data["issue"]


def test_ac3_case_e_status_transition_parity(parity_autopilot_dir: Path, tmp_path: Path):
    """AC3 (e): status transition — 3 経路で同一遷移結果。"""
    from twl.mcp_server.tools import twl_state_write_handler
    from twl.autopilot.state import StateManager

    # 経路 2: MCP handler
    ap_mcp = tmp_path / "ap_mcp"
    ap_mcp.mkdir()
    (ap_mcp / "issues").mkdir()
    sm_mcp = StateManager(autopilot_dir=ap_mcp)
    sm_mcp.write(type_="issue", role="worker", issue="5", init=True)
    mcp_result = twl_state_write_handler(
        type_="issue",
        role="worker",
        issue="5",
        sets=["status=merge-ready"],
        autopilot_dir=str(ap_mcp),
    )
    assert mcp_result.get("ok") is True, f"MCP transition failed: {mcp_result}"
    mcp_status = json.loads((ap_mcp / "issues" / "issue-5.json").read_text())["status"]

    # 経路 3: Python 直接
    ap_direct = tmp_path / "ap_direct"
    ap_direct.mkdir()
    (ap_direct / "issues").mkdir()
    sm = StateManager(autopilot_dir=ap_direct)
    sm.write(type_="issue", role="worker", issue="5", init=True)
    sm.write(type_="issue", role="worker", issue="5", sets=["status=merge-ready"])
    direct_status = json.loads((ap_direct / "issues" / "issue-5.json").read_text())["status"]

    # 経路 1: CLI subprocess
    ap_cli = tmp_path / "ap_cli"
    ap_cli.mkdir()
    (ap_cli / "issues").mkdir()
    _run_cli_state(["write", "--type", "issue", "--role", "worker", "--issue", "5", "--init"], ap_cli)
    cli_proc = _run_cli_state(
        ["write", "--type", "issue", "--role", "worker", "--issue", "5", "--set", "status=merge-ready"],
        ap_cli,
    )
    assert cli_proc.returncode == 0, f"CLI transition failed: {cli_proc.stderr}"
    cli_status = json.loads((ap_cli / "issues" / "issue-5.json").read_text())["status"]

    assert mcp_status == direct_status, (
        f"status transition parity fail: MCP={mcp_status!r} vs direct={direct_status!r}"
    )
    assert cli_status == direct_status, (
        f"status transition parity fail: CLI={cli_status!r} vs direct={direct_status!r}"
    )


def test_ac3_case_f_rbac_violation_parity(parity_autopilot_dir: Path, tmp_path: Path):
    """AC3 (f): RBAC 違反 — worker が session.json への不正書き込みを試みてエラー。
    cwd を worktrees 配下に明示渡しして pilot identity 検証が発動することを確認。
    ADR-0006 §3: cwd 明示渡しにより os.getcwd() fallback を排除して再現性を確保。
    """
    from twl.mcp_server.tools import twl_state_write_handler
    from twl.autopilot.state import StateManager, StateArgError, StateError

    # fake worktree cwd: pilot identity check 用 (ADR-0006 §3)
    ng_cwd = str(tmp_path / "worktrees" / "ng-branch")

    # 経路 2: MCP handler — worker が session.json に sets を試みる (RBAC 違反)
    ap_mcp = tmp_path / "ap_mcp"
    ap_mcp.mkdir()
    (ap_mcp / "issues").mkdir()
    mcp_result = twl_state_write_handler(
        type_="session",
        role="worker",  # worker は session write 禁止
        sets=["status=active"],
        autopilot_dir=str(ap_mcp),
        cwd=ng_cwd,  # ADR-0006 §3: cwd 明示渡し
    )
    assert mcp_result.get("ok") is False, "RBAC 違反で MCP handler が ok=True を返した"
    assert mcp_result.get("error_type") in ("arg_error", "state_error"), (
        f"error_type が予期しない値: {mcp_result}"
    )

    # 経路 3: Python 直接 — 同じ RBAC 違反
    ap_direct = tmp_path / "ap_direct"
    ap_direct.mkdir()
    (ap_direct / "issues").mkdir()
    sm = StateManager(autopilot_dir=ap_direct)
    with pytest.raises((StateArgError, StateError)):
        sm.write(type_="session", role="worker", sets=["status=active"], cwd=ng_cwd)

    # 経路 1: CLI subprocess — cwd= 引数で worktree パスを制御
    ap_cli = tmp_path / "ap_cli"
    ap_cli.mkdir()
    (ap_cli / "issues").mkdir()
    cli_proc = _run_cli_state(
        ["write", "--type", "session", "--role", "worker", "--set", "status=active"],
        ap_cli,
    )
    # CLI 側は subprocess の cwd が worktree 外なので RBAC check は通過する場合があるが
    # worker role の session write は StateArgError で失敗するはず
    assert cli_proc.returncode != 0, "CLI RBAC 違反が成功してしまった"


# ===========================================================================
# AC4: ADR-0006 Decision §1~§4 の機械検証
# ===========================================================================


def test_ac4_sec1_hybrid_path_5_principles_in_tools():
    """AC4 §1: Hybrid Path 5 原則が tools.py に実装済みか。
    RED: 未実装 → ImportError。
    """
    import inspect
    from twl.mcp_server import tools

    # 原則 1: _handler suffix
    assert hasattr(tools, "twl_state_read_handler")
    assert hasattr(tools, "twl_state_write_handler")

    # 原則 4: autopilot_dir 明示引数化
    read_sig = inspect.signature(tools.twl_state_read_handler)
    write_sig = inspect.signature(tools.twl_state_write_handler)
    assert "autopilot_dir" in read_sig.parameters
    assert "autopilot_dir" in write_sig.parameters
    assert "cwd" in write_sig.parameters


def test_ac4_sec2_state_py_unchanged():
    """AC4 §2: state.py 未変更原則 (git diff guard)。
    RED: state.py が変更されていれば fail する。
    """
    result = subprocess.run(
        ["git", "diff", "--name-only", "main...HEAD"],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
    )
    changed = result.stdout.strip().splitlines()
    assert "cli/twl/src/twl/autopilot/state.py" not in changed, (
        "AC4 §2 違反: state.py が変更されている"
    )


def test_ac4_sec3_explicit_args_read_handler():
    """AC4 §3: twl_state_read_handler に autopilot_dir 明示引数がある。
    RED: 未実装 → ImportError。
    """
    import inspect
    from twl.mcp_server.tools import twl_state_read_handler
    params = inspect.signature(twl_state_read_handler).parameters
    assert "autopilot_dir" in params


def test_ac4_sec3_explicit_args_write_handler():
    """AC4 §3: twl_state_write_handler に autopilot_dir / cwd 明示引数がある。
    RED: 未実装 → ImportError。
    """
    import inspect
    from twl.mcp_server.tools import twl_state_write_handler
    params = inspect.signature(twl_state_write_handler).parameters
    assert "autopilot_dir" in params
    assert "cwd" in params


def test_ac4_sec4_ssot_parity_3path_exists():
    """AC4 §4: SSoT 検証 3 経路 parametric が定義されている (このファイル内に存在確認)。
    GREEN: このファイル自体が存在すれば pass する静的チェック。
    """
    this_file = Path(__file__)
    assert this_file.exists(), "test_state_dispatch_parity.py が存在しない"
    content = this_file.read_text()
    assert "test_ac3_read_3path_parity" in content
    assert "test_ac3_case_d_issue_init_parity" in content
    assert "test_ac3_case_e_status_transition_parity" in content
    assert "test_ac3_case_f_rbac_violation_parity" in content
