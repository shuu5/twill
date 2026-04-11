"""resolve_next_workflow — orchestrator が inject_next_workflow で呼び出すモジュール。

CLI usage:
    python3 -m twl.autopilot.resolve_next_workflow --issue <N>

state ファイルの workflow_done フィールドを読み取り、
chain.ChainRunner.resolve_next_workflow() に委譲して次の workflow skill 名を stdout に出力する。

Output:
    - 成功: /twl:workflow-<name> を stdout に出力、exit 0
    - 失敗(workflow_done が null/空): stdout 空、exit 1
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys


def _read_state(issue_num: str, field: str, autopilot_dir: str) -> str:
    """state ファイルからフィールドを読み取る。失敗時は空文字を返す。"""
    env = {**os.environ}
    if autopilot_dir:
        env["AUTOPILOT_DIR"] = autopilot_dir
    try:
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.state", "read",
             "--type", "issue", "--issue", issue_num, "--field", field],
            capture_output=True, text=True, env=env,
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except Exception:
        return ""


def _resolve_next(issue_num: str, workflow_done: str, is_quick: bool) -> str:
    """chain.ChainRunner.resolve_next_workflow に委譲して次 skill 名を返す。"""
    from twl.autopilot.chain import ChainRunner
    runner = ChainRunner()
    return runner.resolve_next_workflow(workflow_done, is_autopilot=True, is_quick=is_quick)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="orchestrator inject 用 next workflow resolver"
    )
    parser.add_argument("--issue", required=True, help="Issue 番号")
    args = parser.parse_args(argv)

    issue_num = args.issue.lstrip("#")
    if not re.match(r"^\d+$", issue_num):
        print(f"ERROR: 不正な issue 番号: {issue_num}", file=sys.stderr)
        return 1

    autopilot_dir = os.environ.get("AUTOPILOT_DIR", "")

    workflow_done = _read_state(issue_num, "workflow_done", autopilot_dir)
    if not workflow_done or workflow_done == "null":
        print(
            f"ERROR: issue-{issue_num} の workflow_done が未設定または null",
            file=sys.stderr,
        )
        return 1

    is_quick_str = _read_state(issue_num, "is_quick", autopilot_dir)
    is_quick = is_quick_str.lower() == "true"

    try:
        next_skill = _resolve_next(issue_num, workflow_done, is_quick)
    except Exception as e:
        print(f"ERROR: resolve_next_workflow 失敗: {e}", file=sys.stderr)
        return 1

    if not next_skill or next_skill in ("", "quick-path"):
        print(
            f"ERROR: workflow_done={workflow_done} の次 skill が見つからない（terminal または stop）",
            file=sys.stderr,
        )
        return 1

    # skill 名が /twl: プレフィックスを持たない場合は付与する
    if not next_skill.startswith("/twl:"):
        next_skill = f"/twl:{next_skill}"

    print(next_skill)
    return 0


if __name__ == "__main__":
    sys.exit(main())
