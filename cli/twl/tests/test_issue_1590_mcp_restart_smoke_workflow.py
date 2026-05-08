"""Tests for Issue #1590: mcp-restart-smoke CI workflow.

RED phase tests -- fail until .github/workflows/mcp-restart-smoke.yml is created.

AC1: .github/workflows/mcp-restart-smoke.yml 新設（YAML keys 検証）
AC2: jobs.smoke-test.steps のシーケンス検証
AC3: on.pull_request.paths filter 検証
AC4: failure log の repair guidance step 検証
"""

from __future__ import annotations

from pathlib import Path

import pytest

try:
    import yaml  # type: ignore[import]
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

REPO_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "mcp-restart-smoke.yml"


@pytest.fixture(scope="module")
def workflow_exists() -> None:
    """ワークフローファイルの存在を前提とする fixture."""
    if not WORKFLOW_PATH.exists():
        pytest.fail(
            f"AC1: .github/workflows/mcp-restart-smoke.yml が存在しない: {WORKFLOW_PATH}"
        )


@pytest.fixture(scope="module")
def workflow_text(workflow_exists) -> str:
    return WORKFLOW_PATH.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def workflow_yaml(workflow_text: str) -> dict:
    if not HAS_YAML:
        pytest.skip("PyYAML not installed; install with pip install pyyaml")
    return yaml.safe_load(workflow_text)


# ---------------------------------------------------------------------------
# AC1: ワークフローファイル新設 + 必須 YAML keys
# ---------------------------------------------------------------------------


def test_ac1_workflow_file_exists():
    # AC: .github/workflows/mcp-restart-smoke.yml を新設する
    assert WORKFLOW_PATH.exists(), (
        f"AC1: mcp-restart-smoke.yml が存在しない: {WORKFLOW_PATH}"
    )


def test_ac1_name_key(workflow_yaml: dict):
    # AC: name: mcp-restart-smoke を含むこと
    assert workflow_yaml.get("name") == "mcp-restart-smoke", (
        f"AC1: name キーが 'mcp-restart-smoke' でない。実際: {workflow_yaml.get('name')}"
    )


def test_ac1_on_has_pull_request_trigger(workflow_yaml: dict):
    # AC: on: に pull_request: トリガーを含むこと
    on = workflow_yaml.get("on") or workflow_yaml.get(True)  # YAML では `on` が True にパースされる場合あり
    assert on is not None, "AC1: on: キーが存在しない"
    assert "pull_request" in on, (
        f"AC1: on: に pull_request トリガーがない。実際のキー: {list(on.keys()) if isinstance(on, dict) else on}"
    )


def test_ac1_on_has_workflow_dispatch_trigger(workflow_yaml: dict):
    # AC: on: に workflow_dispatch: トリガーを含むこと
    on = workflow_yaml.get("on") or workflow_yaml.get(True)
    assert on is not None, "AC1: on: キーが存在しない"
    assert "workflow_dispatch" in on, (
        f"AC1: on: に workflow_dispatch トリガーがない。実際のキー: {list(on.keys()) if isinstance(on, dict) else on}"
    )


def test_ac1_permissions_empty(workflow_yaml: dict):
    # AC: permissions: {} （最小権限）を含むこと
    perms = workflow_yaml.get("permissions")
    assert perms is not None, "AC1: permissions キーが存在しない"
    assert perms == {} or perms == {}, (
        f"AC1: permissions が空でない（最小権限でない）。実際: {perms}"
    )


def test_ac1_defaults_shell_bash(workflow_yaml: dict):
    # AC: defaults.run.shell: bash を含むこと
    defaults = workflow_yaml.get("defaults")
    assert defaults is not None, "AC1: defaults キーが存在しない"
    run = defaults.get("run") if isinstance(defaults, dict) else None
    assert run is not None, "AC1: defaults.run キーが存在しない"
    assert run.get("shell") == "bash", (
        f"AC1: defaults.run.shell が bash でない。実際: {run.get('shell')}"
    )


def test_ac1_jobs_smoke_test_exists(workflow_yaml: dict):
    # AC: jobs.smoke-test: キーが存在すること
    jobs = workflow_yaml.get("jobs", {})
    assert "smoke-test" in jobs, (
        f"AC1: jobs.smoke-test が存在しない。実際の jobs: {list(jobs.keys())}"
    )


def test_ac1_jobs_smoke_test_runs_on_ubuntu(workflow_yaml: dict):
    # AC: jobs.smoke-test.runs-on: ubuntu-latest
    jobs = workflow_yaml.get("jobs", {})
    smoke = jobs.get("smoke-test", {})
    assert smoke.get("runs-on") == "ubuntu-latest", (
        f"AC1: smoke-test.runs-on が ubuntu-latest でない。実際: {smoke.get('runs-on')}"
    )


def test_ac1_jobs_smoke_test_timeout_minutes(workflow_yaml: dict):
    # AC: jobs.smoke-test.timeout-minutes: 5
    jobs = workflow_yaml.get("jobs", {})
    smoke = jobs.get("smoke-test", {})
    assert smoke.get("timeout-minutes") == 5, (
        f"AC1: smoke-test.timeout-minutes が 5 でない。実際: {smoke.get('timeout-minutes')}"
    )


def test_ac1_jobs_smoke_test_has_steps(workflow_yaml: dict):
    # AC: jobs.smoke-test.steps: が存在すること
    jobs = workflow_yaml.get("jobs", {})
    smoke = jobs.get("smoke-test", {})
    steps = smoke.get("steps")
    assert steps is not None and isinstance(steps, list) and len(steps) > 0, (
        f"AC1: smoke-test.steps が存在しないか空。実際: {steps}"
    )


# ---------------------------------------------------------------------------
# AC2: smoke-test steps のシーケンス検証
# ---------------------------------------------------------------------------


def _get_steps(workflow_yaml: dict) -> list:
    return workflow_yaml.get("jobs", {}).get("smoke-test", {}).get("steps", [])


def _step_uses(steps: list, action_prefix: str) -> list:
    return [s for s in steps if s.get("uses", "").startswith(action_prefix)]


def _steps_containing(steps: list, keyword: str) -> list:
    """run フィールドに keyword を含む steps を返す."""
    return [s for s in steps if keyword in s.get("run", "")]


def test_ac2_step_checkout_v4(workflow_yaml: dict):
    # AC: (a) actions/checkout@v4 step が存在すること
    steps = _get_steps(workflow_yaml)
    matches = _step_uses(steps, "actions/checkout@v4")
    assert len(matches) >= 1, (
        f"AC2: actions/checkout@v4 step が見つからない。steps の uses: "
        f"{[s.get('uses') for s in steps if s.get('uses')]}"
    )


def test_ac2_step_mcp_json_path_rewrite(workflow_yaml: dict):
    # AC: (a-bis) .mcp.json の絶対 path 書き換え step (Python script で $GITHUB_WORKSPACE に書き換え)
    steps = _get_steps(workflow_yaml)
    # GITHUB_WORKSPACE と .mcp.json 書き換えに関する run コマンドを持つ step を探す
    candidates = [
        s for s in steps
        if "GITHUB_WORKSPACE" in s.get("run", "") and "mcp.json" in s.get("run", "")
    ]
    # Python スクリプトか python コマンド使用を確認
    python_candidates = [
        s for s in candidates
        if "python" in s.get("run", "").lower()
    ]
    assert len(python_candidates) >= 1, (
        "AC2: .mcp.json の絶対 path 書き換え step (Python + GITHUB_WORKSPACE) が見つからない。"
        f"GITHUB_WORKSPACE + mcp.json を含む steps: {[s.get('name', s.get('run', '')[:50]) for s in candidates]}"
    )


def test_ac2_step_setup_python_v5(workflow_yaml: dict):
    # AC: (b) actions/setup-python@v5 step が存在すること
    steps = _get_steps(workflow_yaml)
    matches = _step_uses(steps, "actions/setup-python@v5")
    assert len(matches) >= 1, (
        f"AC2: actions/setup-python@v5 step が見つからない。steps の uses: "
        f"{[s.get('uses') for s in steps if s.get('uses')]}"
    )


def test_ac2_step_pip_install_uv_not_setup_uv_action(workflow_yaml: dict):
    # AC: (b) pip install uv を使用すること（setup-uv@v3 は使わない）
    steps = _get_steps(workflow_yaml)
    # setup-uv@v3 が使われていないことを確認
    setup_uv_matches = [s for s in steps if "setup-uv" in s.get("uses", "")]
    assert len(setup_uv_matches) == 0, (
        f"AC2: setup-uv@v3 action が使われている（pip install uv を使うべき）: {setup_uv_matches}"
    )
    # pip install uv が run フィールドに存在することを確認
    pip_uv_steps = _steps_containing(steps, "pip install uv")
    assert len(pip_uv_steps) >= 1, (
        "AC2: 'pip install uv' を実行する step が見つからない"
    )


def test_ac2_step_uv_sync_extra_mcp(workflow_yaml: dict):
    # AC: (c) uv sync --extra mcp を cli/twl working-directory で実行すること
    steps = _get_steps(workflow_yaml)
    uv_sync_steps = [
        s for s in steps
        if "uv sync" in s.get("run", "") and "mcp" in s.get("run", "")
    ]
    assert len(uv_sync_steps) >= 1, (
        "AC2: 'uv sync --extra mcp' step が見つからない"
    )
    # working-directory が cli/twl であることを確認
    wd_ok = [
        s for s in uv_sync_steps
        if s.get("working-directory") == "cli/twl"
    ]
    assert len(wd_ok) >= 1, (
        f"AC2: uv sync step の working-directory が 'cli/twl' でない。"
        f"実際: {[s.get('working-directory') for s in uv_sync_steps]}"
    )


def test_ac2_step_doctor_disabled_with_if_false(workflow_yaml: dict):
    # AC: (d) doctor 検証 step は if: ${{ false }} で disable されていること
    steps = _get_steps(workflow_yaml)
    # doctor に関連する step を探す（twl mcp doctor や doctor キーワード）
    doctor_steps = [
        s for s in steps
        if "doctor" in s.get("run", "").lower() or "doctor" in s.get("name", "").lower()
    ]
    assert len(doctor_steps) >= 1, (
        "AC2: doctor 検証 step が見つからない"
    )
    # if: ${{ false }} で無効化されていることを確認
    disabled = [
        s for s in doctor_steps
        if str(s.get("if", "")).strip() in ("${{ false }}", "false", "False")
    ]
    assert len(disabled) >= 1, (
        f"AC2: doctor step が if: ${{{{ false }}}} で disable されていない。"
        f"実際の if: {[s.get('if') for s in doctor_steps]}"
    )


def test_ac2_step_restart_smoke_twl_mcp_restart(workflow_yaml: dict):
    # AC: (e) restart smoke: twl mcp restart を実行すること
    steps = _get_steps(workflow_yaml)
    restart_steps = [
        s for s in steps
        if "twl mcp restart" in s.get("run", "")
    ]
    assert len(restart_steps) >= 1, (
        "AC2: 'twl mcp restart' を含む step が見つからない"
    )


def test_ac2_step_restart_smoke_pgrep_polling(workflow_yaml: dict):
    # AC: (e) pgrep -f 'fastmcp run.*src/twl/mcp_server/server.py' で polling loop すること
    steps = _get_steps(workflow_yaml)
    pgrep_steps = [
        s for s in steps
        if "pgrep" in s.get("run", "") and "fastmcp run" in s.get("run", "")
        and "mcp_server" in s.get("run", "")
    ]
    assert len(pgrep_steps) >= 1, (
        "AC2: pgrep -f 'fastmcp run.*mcp_server/server.py' による polling step が見つからない"
    )


def test_ac2_step_cleanup_if_always(workflow_yaml: dict):
    # AC: (f) cleanup step は if: always() で実行されること
    steps = _get_steps(workflow_yaml)
    # pkill と always() の組み合わせを持つ step を探す
    cleanup_steps = [
        s for s in steps
        if "pkill" in s.get("run", "") and "fastmcp run" in s.get("run", "")
    ]
    assert len(cleanup_steps) >= 1, (
        "AC2: pkill を含む cleanup step が見つからない"
    )
    always_cleanup = [
        s for s in cleanup_steps
        if "always()" in str(s.get("if", ""))
    ]
    assert len(always_cleanup) >= 1, (
        f"AC2: cleanup step の if: always() が設定されていない。"
        f"実際の if: {[s.get('if') for s in cleanup_steps]}"
    )


def test_ac2_cleanup_uses_pkill_term_with_or_true(workflow_yaml: dict):
    # AC: (f) pkill -TERM -f 'fastmcp run.*src/twl/mcp_server/server.py' || true
    steps = _get_steps(workflow_yaml)
    pkill_term_steps = [
        s for s in steps
        if "pkill" in s.get("run", "")
        and "-TERM" in s.get("run", "")
        and "|| true" in s.get("run", "")
    ]
    assert len(pkill_term_steps) >= 1, (
        "AC2: 'pkill -TERM ... || true' パターンの cleanup step が見つからない"
    )


# ---------------------------------------------------------------------------
# AC3: on.pull_request.paths filter 検証
# ---------------------------------------------------------------------------

REQUIRED_PATHS = [
    ".mcp.json",
    "cli/twl/src/twl/mcp_server/**",
    "cli/twl/tests/test_mcp_lifecycle.py",
    "cli/twl/pyproject.toml",
    "cli/twl/uv.lock",
    ".github/workflows/mcp-restart-smoke.yml",
]


def test_ac3_pull_request_paths_filter_exists(workflow_yaml: dict):
    # AC: on.pull_request.paths が存在すること
    on = workflow_yaml.get("on") or workflow_yaml.get(True)
    assert on is not None, "AC3: on: キーが存在しない"
    pr = on.get("pull_request")
    assert pr is not None, "AC3: on.pull_request が存在しない"
    assert isinstance(pr, dict), f"AC3: on.pull_request が dict でない。実際: {type(pr)}"
    paths = pr.get("paths")
    assert paths is not None and isinstance(paths, list), (
        f"AC3: on.pull_request.paths が存在しないかリストでない。実際: {paths}"
    )


@pytest.mark.parametrize("expected_path", REQUIRED_PATHS)
def test_ac3_pull_request_paths_contains_required(workflow_yaml: dict, expected_path: str):
    # AC: on.pull_request.paths に必須 pattern が含まれること
    on = workflow_yaml.get("on") or workflow_yaml.get(True)
    pr = (on or {}).get("pull_request", {})
    paths = pr.get("paths", [])
    assert expected_path in paths, (
        f"AC3: on.pull_request.paths に '{expected_path}' が含まれない。"
        f"実際の paths: {paths}"
    )


# ---------------------------------------------------------------------------
# AC4: failure log の repair guidance step 検証
# ---------------------------------------------------------------------------


def test_ac4_failure_step_exists_after_restart_smoke(workflow_yaml: dict):
    # AC: smoke test step (e) の直後に if: failure() step が存在すること
    steps = _get_steps(workflow_yaml)
    failure_steps = [
        s for s in steps
        if "failure()" in str(s.get("if", ""))
    ]
    assert len(failure_steps) >= 1, (
        "AC4: if: failure() を持つ repair guidance step が存在しない"
    )


def test_ac4_failure_step_mentions_issue_1588(workflow_yaml: dict):
    # AC: failure step が #1588 への参照を含むこと（root cause 真因説明）
    steps = _get_steps(workflow_yaml)
    failure_steps = [
        s for s in steps
        if "failure()" in str(s.get("if", ""))
    ]
    assert len(failure_steps) >= 1, "AC4: if: failure() step が存在しない"
    # #1588 への参照が run または name に含まれるか確認
    ref_1588 = [
        s for s in failure_steps
        if "#1588" in s.get("run", "") or "#1588" in s.get("name", "")
    ]
    assert len(ref_1588) >= 1, (
        f"AC4: failure step に '#1588' への参照がない。"
        f"failure steps の run/name: "
        f"{[(s.get('name', ''), s.get('run', '')[:80]) for s in failure_steps]}"
    )


def test_ac4_failure_step_mentions_issue_1589(workflow_yaml: dict):
    # AC: failure step が #1589 への参照を含むこと
    steps = _get_steps(workflow_yaml)
    failure_steps = [
        s for s in steps
        if "failure()" in str(s.get("if", ""))
    ]
    ref_1589 = [
        s for s in failure_steps
        if "#1589" in s.get("run", "") or "#1589" in s.get("name", "")
    ]
    assert len(ref_1589) >= 1, (
        f"AC4: failure step に '#1589' への参照がない。"
        f"failure steps の run/name: "
        f"{[(s.get('name', ''), s.get('run', '')[:80]) for s in failure_steps]}"
    )


def test_ac4_failure_step_mentions_adr_0008(workflow_yaml: dict):
    # AC: failure step が ADR-0008 への参照を含むこと
    steps = _get_steps(workflow_yaml)
    failure_steps = [
        s for s in steps
        if "failure()" in str(s.get("if", ""))
    ]
    ref_adr = [
        s for s in failure_steps
        if "ADR-0008" in s.get("run", "") or "ADR-0008" in s.get("name", "")
    ]
    assert len(ref_adr) >= 1, (
        f"AC4: failure step に 'ADR-0008' への参照がない。"
        f"failure steps の run/name: "
        f"{[(s.get('name', ''), s.get('run', '')[:80]) for s in failure_steps]}"
    )


def test_ac4_failure_step_command_fix_guidance(workflow_yaml: dict):
    # AC: failure step に .mcp.json.mcpServers.twl.command を "uv" に修正する手順を含むこと
    steps = _get_steps(workflow_yaml)
    failure_steps = [
        s for s in steps
        if "failure()" in str(s.get("if", ""))
    ]
    # "uv" と mcpServers または command への言及を確認
    fix_guidance = [
        s for s in failure_steps
        if (
            '"uv"' in s.get("run", "") or "'uv'" in s.get("run", "")
        ) and (
            "command" in s.get("run", "") or "mcpServers" in s.get("run", "")
        )
    ]
    assert len(fix_guidance) >= 1, (
        "AC4: failure step に .mcp.json.mcpServers.twl.command を 'uv' に修正する手順がない。"
        f"failure steps: {[(s.get('name', ''), s.get('run', '')[:120]) for s in failure_steps]}"
    )
