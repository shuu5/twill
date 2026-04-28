"""GitHub API wrapper for autopilot operations.

Replaces: parse-issue-ac.sh, merge-gate-issues.sh, create-harness-issue.sh,
          scripts/lib/resolve-project.sh

CLI usage:
    python3 -m twl.autopilot.github extract-ac <issue-number> [owner/repo]
    python3 -m twl.autopilot.github extract-parent-epic <issue-number> [owner/repo]
    python3 -m twl.autopilot.github extract-closes-ac <issue-number> [owner/repo]
    python3 -m twl.autopilot.github update-epic-ac-checklist <issue-number> [owner/repo]
    python3 -m twl.autopilot.github resolve-project [owner]
    python3 -m twl.autopilot.github pr-findings <pr-number> [owner/repo]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

_ISSUE_NUM_RE = re.compile(r"^\d+$")
_REPO_RE = re.compile(r"^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$")
_OWNER_RE = re.compile(r"^[a-zA-Z0-9_-]+$")
_PR_NUM_RE = re.compile(r"^\d+$")


def _validate_issue_num(issue_num: str) -> None:
    if not _ISSUE_NUM_RE.match(issue_num):
        raise GitHubError(f"Issue番号は整数である必要があります: {issue_num!r}")


def _validate_repo(repo: str) -> None:
    if not _REPO_RE.match(repo):
        raise GitHubError(f"不正な owner/repo 形式: {repo!r}")


def _gh(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run a gh command and return the completed process."""
    cmd = ["gh", *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise GitHubError(f"gh command failed: {' '.join(cmd)}\n{result.stderr}")
    return result


def _gh_json(*args: str) -> Any:
    """Run a gh command and parse JSON output."""
    result = _gh(*args)
    return json.loads(result.stdout)


# ---------------------------------------------------------------------------
# Error types
# ---------------------------------------------------------------------------


class GitHubError(Exception):
    """Raised for GitHub API errors."""


class ACNotFoundError(GitHubError):
    """Raised when no AC section or checklist is found."""


# ---------------------------------------------------------------------------
# Issue AC extraction (replaces parse-issue-ac.sh)
# ---------------------------------------------------------------------------

_CHECKBOX_RE = re.compile(r"^\s*-\s*\[[ x]\]\s*(.+)", re.IGNORECASE)


def _extract_ac_from_text(text: str) -> list[str]:
    """Extract AC checkbox items from markdown text."""
    lines = text.splitlines()
    return [
        m.group(1).strip()
        for line in lines
        if (m := _CHECKBOX_RE.match(line))
    ]


def extract_issue_ac(issue_num: str, repo: str | None = None) -> list[str]:
    """Extract acceptance criteria checklist from an Issue.

    Mirrors parse-issue-ac.sh behaviour:
    - Fetch issue body via gh API
    - Also fetch comments and PR review comments
    - Extract ``- [ ]`` / ``- [x]`` items from the 受け入れ基準 section

    Args:
        issue_num: Issue number (integer string).
        repo: Optional ``owner/repo`` string for cross-repo access.

    Returns:
        List of AC text strings (numbered lines omitted — callers can enumerate).

    Raises:
        GitHubError: On API failure.
        ACNotFoundError: If no AC section or checklist found.
    """
    _validate_issue_num(issue_num)
    if repo:
        _validate_repo(repo)

    repo_flag = ["-R", repo] if repo else []

    # Fetch issue body
    issue_data = _gh_json("issue", "view", issue_num, *repo_flag, "--json", "body,number")
    body: str = issue_data.get("body") or ""
    if not body:
        raise GitHubError(f"Issue #{issue_num} の body が空です")

    # Extract 受け入れ基準 section from body
    ac_section = _extract_ac_section(body)
    body_acs = _extract_ac_from_text(ac_section) if ac_section else _extract_ac_from_text(body)

    # Fetch comments
    comment_acs: list[str] = []
    try:
        comments = _gh_json("issue", "view", issue_num, *repo_flag, "--json", "comments")
        for comment in comments.get("comments", []):
            comment_acs.extend(_extract_ac_from_text(comment.get("body") or ""))
    except (GitHubError, json.JSONDecodeError):
        pass

    all_acs = body_acs + comment_acs
    if not all_acs:
        raise ACNotFoundError(f"Issue #{issue_num} にACチェックボックスが見つかりません")

    return all_acs


def _extract_ac_section(body: str) -> str:
    """Extract the 受け入れ基準 section from issue body markdown."""
    lines = body.splitlines()
    in_section = False
    section_lines: list[str] = []

    for line in lines:
        if re.match(r"^##\s+受け入れ基準", line):
            in_section = True
            continue
        if in_section:
            if re.match(r"^##\s+", line):
                break
            section_lines.append(line)

    return "\n".join(section_lines)


# ---------------------------------------------------------------------------
# Parent Epic extraction (Issue #1026 ADR-024 AC1)
# ---------------------------------------------------------------------------

# `Parent: #N` 規約は plugins/twl/commands/issue-create.md L51 で SSoT 定義済み。
# 子 Issue body 内の `^[\s]*Parent:\s*#(\d+)` を抽出する。
_PARENT_EPIC_RE = re.compile(r"(?:^|\n)\s*Parent:\s*#(\d+)", re.MULTILINE)


def extract_parent_epic(issue_num: str, repo: str | None = None) -> int | None:
    """Extract parent Epic issue number from a child Issue's body.

    Parses the SSoT regulated `Parent: #N` line (issue-create.md L51).
    Returns the parent number as int when found, None when not present.

    **Multiple Parent lines**: Returns the **first match** if multiple `Parent:`
    lines exist. This is consistent with `re.search` semantics. Callers should
    treat duplicate `Parent:` lines as a body-format error and rely on the
    first line as authoritative.

    Args:
        issue_num: Child Issue number (integer string).
        repo: Optional ``owner/repo`` string for cross-repo access.

    Returns:
        Parent Epic number as int, or None if no Parent line found in body.

    Raises:
        GitHubError: On invalid issue_num/repo or gh API failure.
    """
    _validate_issue_num(issue_num)
    if repo:
        _validate_repo(repo)

    repo_flag = ["-R", repo] if repo else []

    issue_data = _gh_json("issue", "view", issue_num, *repo_flag, "--json", "body,number")
    body: str = issue_data.get("body") or ""
    if not body:
        return None

    match = _PARENT_EPIC_RE.search(body)
    if match is None:
        return None
    return int(match.group(1))


# ---------------------------------------------------------------------------
# Closes-AC extraction + Epic AC checkbox auto-update (Issue #1070)
# ---------------------------------------------------------------------------

# `Closes-AC: #EPIC:ACN` 規約 (Issue #1070 AC1)。子 Issue body から複数行抽出。
# Note: Code blocks (``` ... ``` / ~~~ ... ~~~) are stripped before regex match
# to avoid false-matches on documentation examples (R2-H1 review fix).
_CLOSES_AC_RE = re.compile(
    r"(?:^|\n)\s*Closes-AC:\s*#(\d+):AC(\d+)", re.MULTILINE
)
_FENCED_CODE_BLOCK_RE = re.compile(
    r"^(```|~~~).*?^(```|~~~)\s*$", re.MULTILINE | re.DOTALL
)


def _strip_fenced_code_blocks(text: str) -> str:
    """Remove fenced code blocks (``` or ~~~) from markdown text.

    Used to prevent false-matches when scanning for Closes-AC references —
    a child Issue body may contain documentation examples inside code fences
    that should NOT trigger Epic AC flips.
    """
    return _FENCED_CODE_BLOCK_RE.sub("", text)


def _validate_positive_int(value: int, label: str) -> None:
    if not isinstance(value, int) or value <= 0:
        raise GitHubError(f"{label}は正の整数である必要があります: {value!r}")


def _patch_checkbox_in_text(body: str, ac_num: int) -> tuple[str, bool]:
    """Pure: flip ``- [ ] **AC{ac_num}**`` to ``- [x] **AC{ac_num}**``.

    Strict format match: only ``- [ ] **AC{N}**`` lines are matched.
    Bare ``- [ ] AC1`` (no bold) is intentionally NOT matched to minimize
    false-positive flips on prose mentions.

    Args:
        body: Epic body markdown text.
        ac_num: AC number to flip (1-based).

    Returns:
        Tuple of (patched_body, was_changed). ``was_changed`` is True iff
        at least one ``- [ ]`` was flipped to ``- [x]`` for this AC.
        Idempotent: already-checked boxes return (body, False).
    """
    pattern = re.compile(
        rf"^(\s*-\s*)\[ \](\s*\*\*AC{ac_num}\*\*)", re.MULTILINE
    )
    new_body, count = pattern.subn(r"\1[x]\2", body)
    return new_body, count > 0


def extract_closes_ac(
    issue_num: str, repo: str | None = None
) -> list[tuple[int, int]]:
    """Extract ``Closes-AC: #EPIC:ACN`` references from a child Issue body.

    Returns the list of ``(epic_num, ac_num)`` tuples in document order.
    Returns ``[]`` if no ``Closes-AC`` lines exist (NOT an error — the
    convention is optional and will only apply forward-going).

    Args:
        issue_num: Child Issue number (integer string).
        repo: Optional ``owner/repo`` string for cross-repo access.

    Returns:
        List of ``(epic_num, ac_num)`` tuples.

    Raises:
        GitHubError: On invalid issue_num/repo or gh API failure.
    """
    _validate_issue_num(issue_num)
    if repo:
        _validate_repo(repo)

    repo_flag = ["-R", repo] if repo else []

    issue_data = _gh_json("issue", "view", issue_num, *repo_flag, "--json", "body,number")
    body: str = issue_data.get("body") or ""
    if not body:
        return []

    # Strip fenced code blocks so doc examples like ```Closes-AC: #N:AC1``` are
    # not mistaken for actual references (R2-H1 review fix).
    sanitized = _strip_fenced_code_blocks(body)

    return [
        (int(epic), int(ac))
        for epic, ac in _CLOSES_AC_RE.findall(sanitized)
    ]


def flip_epic_ac_checkbox(
    epic_num: int, ac_num: int, repo: str | None = None
) -> bool:
    """Fetch Epic body, flip ``- [ ] **AC{ac_num}**`` checkbox, and persist via gh.

    Args:
        epic_num: Parent Epic Issue number.
        ac_num: AC number to flip.
        repo: Optional ``owner/repo`` string for cross-repo Epic access.

    Returns:
        ``True`` if an unchecked checkbox was flipped (gh issue edit was called).
        ``False`` if already checked (idempotent skip — no API write) or if no
        matching ``- [ ] **AC{N}**`` line exists in the Epic body (format deviation).

    Raises:
        GitHubError: On invalid input or gh API failure.

    Note:
        TOCTOU: this performs fetch → patch → edit without ``If-Match`` semantics.
        If a parallel writer mutates the Epic body between fetch and edit, the
        flip wins last-write. Acceptable for the autopilot single-Wave model;
        concurrent flips on the same Epic are rare and self-converging
        (re-running the hook is idempotent). Bulk-merge race is a known
        limitation tracked separately.
    """
    _validate_positive_int(epic_num, "Epic番号")
    _validate_positive_int(ac_num, "AC番号")
    if repo:
        _validate_repo(repo)

    repo_flag = ["-R", repo] if repo else []

    issue_data = _gh_json(
        "issue", "view", str(epic_num), *repo_flag, "--json", "body,number"
    )
    body: str = issue_data.get("body") or ""

    new_body, changed = _patch_checkbox_in_text(body, ac_num)
    if not changed:
        # Idempotent: skip the write (saves a gh API rate-hit)
        return False

    _gh("issue", "edit", str(epic_num), *repo_flag, "--body", new_body)
    return True


def update_epic_ac_checklist(
    child_issue_num: str, repo: str | None = None
) -> bool:
    """Orchestrator: parse ``Closes-AC`` from child, flip each Epic AC checkbox.

    For each ``(epic_num, ac_num)`` reference in the child Issue body, attempts
    to flip the corresponding Epic body checkbox. Errors per-Epic are
    suppressed (logged via stderr) so a transient failure on one Epic does
    not block updates for others — this matches the AC1+AC2 chain-runner.sh
    skip-on-error strategy.

    Args:
        child_issue_num: Child Issue number (integer string).
        repo: Optional ``owner/repo`` string.

    Returns:
        ``True`` if at least one checkbox was flipped (newly checked).
        ``False`` if no ``Closes-AC`` references found, or all flips were
        idempotent (already checked).

    Raises:
        GitHubError: On invalid child_issue_num/repo or initial body fetch failure.
    """
    refs = extract_closes_ac(child_issue_num, repo)
    if not refs:
        return False

    any_flipped = False
    for epic_num, ac_num in refs:
        try:
            if flip_epic_ac_checkbox(epic_num, ac_num, repo):
                any_flipped = True
        except GitHubError as exc:
            # Suppress per-Epic failure; mirrors chain-runner.sh skip-on-error.
            print(
                f"[update-epic-ac-checklist] WARN: Epic #{epic_num} AC{ac_num}"
                f" 更新失敗 (継続): {exc}",
                file=sys.stderr,
            )
    return any_flipped


# ---------------------------------------------------------------------------
# PR findings extraction (AC2 — reviews, status checks)
# ---------------------------------------------------------------------------


def get_pr_findings(pr_num: str, repo: str | None = None) -> dict[str, Any]:
    """Extract PR review and status check findings.

    Returns:
        Dict with keys:
          - reviews: list of review dicts (state, body, author)
          - status_checks: list of check run dicts (name, conclusion)
    """
    if not _PR_NUM_RE.match(pr_num):
        raise GitHubError(f"不正なPR番号: {pr_num!r}")

    if repo:
        _validate_repo(repo)
    repo_flag = ["-R", repo] if repo else []

    # Reviews
    reviews: list[dict[str, Any]] = []
    try:
        review_data = _gh_json(
            "pr", "view", pr_num, *repo_flag,
            "--json", "reviews",
        )
        for r in review_data.get("reviews", []):
            reviews.append({
                "state": r.get("state", ""),
                "body": r.get("body", ""),
                "author": r.get("author", {}).get("login", ""),
            })
    except (GitHubError, json.JSONDecodeError):
        pass

    # Status checks (check runs)
    status_checks: list[dict[str, Any]] = []
    try:
        checks_data = _gh_json(
            "pr", "view", pr_num, *repo_flag,
            "--json", "statusCheckRollup",
        )
        for check in checks_data.get("statusCheckRollup", []):
            status_checks.append({
                "name": check.get("name", check.get("context", "")),
                "conclusion": check.get("conclusion", check.get("state", "")),
            })
    except (GitHubError, json.JSONDecodeError):
        pass

    return {"reviews": reviews, "status_checks": status_checks}


# ---------------------------------------------------------------------------
# Project resolution (replaces scripts/lib/resolve-project.sh)
# ---------------------------------------------------------------------------

_GRAPHQL_USER = """
query($owner: String!, $num: Int!) {
  user(login: $owner) {
    projectV2(number: $num) {
      id
      title
      repositories(first: 20) { nodes { nameWithOwner } }
    }
  }
}
"""

_GRAPHQL_ORG = """
query($owner: String!, $num: Int!) {
  organization(login: $owner) {
    projectV2(number: $num) {
      id
      title
      repositories(first: 20) { nodes { nameWithOwner } }
    }
  }
}
"""


def resolve_project(owner: str | None = None) -> dict[str, Any]:
    """Find the GitHub Project V2 linked to the current repository.

    Mirrors scripts/lib/resolve-project.sh behaviour:
    - Enumerate all projects owned by ``owner``
    - Match project that links to the current repo
    - Prefer project whose title contains the repo name

    Returns:
        Dict with keys: project_num, project_id, owner, repo_name, repo_fullname

    Raises:
        GitHubError: If no linked project found.
    """
    # Determine owner and repo
    repo_info = _gh_json("repo", "view", "--json", "nameWithOwner,owner")
    repo_fullname: str = repo_info["nameWithOwner"]
    resolved_owner: str = owner or repo_info["owner"]["login"]
    repo_name = repo_fullname.split("/", 1)[1]

    if not _OWNER_RE.match(resolved_owner):
        raise GitHubError(f"不正な owner: {resolved_owner!r}")

    # List projects
    projects_result = _gh(
        "project", "list",
        "--owner", resolved_owner,
        "--format", "json",
        check=False,
    )
    if projects_result.returncode != 0:
        raise GitHubError(
            "Project 一覧を取得できません。gh auth refresh -s project を実行してください"
        )

    projects_data = json.loads(projects_result.stdout)
    project_nums: list[int] = [p["number"] for p in projects_data.get("projects", [])]

    if not project_nums:
        raise GitHubError(f"owner {resolved_owner} に Project が存在しません")

    matched_num: int | None = None
    matched_id: str | None = None
    title_match_num: int | None = None
    title_match_id: str | None = None

    for pnum in project_nums:
        project_data = _query_project(resolved_owner, pnum)
        if project_data is None:
            continue

        linked_repos: list[str] = [
            n["nameWithOwner"]
            for n in project_data.get("repositories", {}).get("nodes", [])
        ]
        if repo_fullname not in linked_repos:
            continue

        pid: str = project_data["id"]
        title: str = project_data.get("title", "")

        if matched_num is None:
            matched_num = pnum
            matched_id = pid

        if repo_name in title and title_match_num is None:
            title_match_num = pnum
            title_match_id = pid

    final_num = title_match_num if title_match_num is not None else matched_num
    final_id = title_match_id if title_match_id is not None else matched_id

    if final_num is None or final_id is None:
        raise GitHubError("リポジトリにリンクされた Project Board が見つかりません")

    return {
        "project_num": final_num,
        "project_id": final_id,
        "owner": resolved_owner,
        "repo_name": repo_name,
        "repo_fullname": repo_fullname,
    }


def _query_project(owner: str, project_num: int) -> dict[str, Any] | None:
    """Query a project via GraphQL, trying user then org queries."""
    for query in (_GRAPHQL_USER, _GRAPHQL_ORG):
        result = subprocess.run(
            ["gh", "api", "graphql",
             "-f", f"query={query}",
             "-f", f"owner={owner}",
             "-F", f"num={project_num}"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            continue
        data = json.loads(result.stdout).get("data", {})
        # user or organization path
        for key in ("user", "organization"):
            proj = data.get(key, {}).get("projectV2")
            if proj:
                return proj
    return None


# ---------------------------------------------------------------------------
# Issue creation helpers (replaces create-harness-issue.sh / merge-gate-issues.sh)
# ---------------------------------------------------------------------------


def create_issue(
    title: str,
    body: str,
    labels: list[str] | None = None,
    repo: str | None = None,
) -> dict[str, Any]:
    """Create a GitHub Issue and return its metadata.

    Args:
        title: Issue title.
        body: Issue body (markdown).
        labels: Optional list of label names to apply.
        repo: Optional ``owner/repo`` for cross-repo creation.

    Returns:
        Dict with keys: number, url, title
    """
    repo_flag = ["-R", repo] if repo else []
    if repo:
        _validate_repo(repo)

    args = ["issue", "create", *repo_flag, "--title", title, "--body", body]
    for label in (labels or []):
        args += ["--label", label]

    result = _gh(*args)
    # gh issue create outputs the issue URL on stdout
    url = result.stdout.strip()

    # Extract number from URL
    num_match = re.search(r"/issues/(\d+)$", url)
    if not num_match:
        raise GitHubError(f"Issue 作成後の URL から番号を取得できませんでした: {url!r}")
    number = int(num_match.group(1))

    return {"number": number, "url": url, "title": title}


def add_issue_to_project(issue_url: str, project_num: int, owner: str) -> bool:
    """Add an issue to a GitHub Project V2.

    Returns True on success, False on failure (does not raise).
    """
    if not _OWNER_RE.match(owner):
        return False

    result = subprocess.run(
        ["gh", "project", "item-add", str(project_num),
         "--owner", owner, "--url", issue_url],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return False
    return True


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if not args:
        print("Usage: python3 -m twl.autopilot.github <command> [args...]", file=sys.stderr)
        print(
            "Commands: extract-ac, extract-parent-epic, extract-closes-ac, "
            "update-epic-ac-checklist, resolve-project, pr-findings",
            file=sys.stderr,
        )
        return 1

    command = args[0]
    rest = args[1:]

    try:
        if command == "extract-ac":
            if not rest:
                print("Usage: extract-ac <issue-number> [owner/repo]", file=sys.stderr)
                return 1
            issue_num = rest[0]
            repo = rest[1] if len(rest) > 1 else None
            acs = extract_issue_ac(issue_num, repo)
            for i, ac in enumerate(acs, 1):
                print(f"{i}. {ac}")
            return 0

        elif command == "extract-parent-epic":
            # Issue #1026 ADR-024 AC1: 子 Issue body の `Parent: #N` から親 Epic 番号を抽出
            # exit 0 = 親 Epic 番号 stdout 出力 / exit 2 = 親なし (caller が skip 判断) / exit 1 = エラー
            if not rest:
                print("Usage: extract-parent-epic <issue-number> [owner/repo]", file=sys.stderr)
                return 1
            issue_num = rest[0]
            repo = rest[1] if len(rest) > 1 else None
            parent = extract_parent_epic(issue_num, repo)
            if parent is None:
                return 2
            print(str(parent))
            return 0

        elif command == "extract-closes-ac":
            # Issue #1070 AC2: 子 Issue body の `Closes-AC: #EPIC:ACN` 全行を抽出
            # exit 0 = 1 件以上見つかった (各 line stdout) / exit 2 = 0 件 / exit 1 = エラー
            if not rest:
                print("Usage: extract-closes-ac <issue-number> [owner/repo]", file=sys.stderr)
                return 1
            issue_num = rest[0]
            repo = rest[1] if len(rest) > 1 else None
            refs = extract_closes_ac(issue_num, repo)
            if not refs:
                return 2
            for epic, ac in refs:
                print(f"{epic}:{ac}")
            return 0

        elif command == "update-epic-ac-checklist":
            # Issue #1070 AC3: 子 Issue の Closes-AC 全件で親 Epic body の
            # `- [ ] **AC{N}**` を `- [x]` に flip し gh issue edit で persist。
            # exit 0 = 1 件以上 flip 実行 / exit 2 = no-op (idempotent or no refs) / exit 1 = エラー
            if not rest:
                print("Usage: update-epic-ac-checklist <issue-number> [owner/repo]", file=sys.stderr)
                return 1
            issue_num = rest[0]
            repo = rest[1] if len(rest) > 1 else None
            flipped = update_epic_ac_checklist(issue_num, repo)
            if not flipped:
                return 2
            return 0

        elif command == "resolve-project":
            owner = rest[0] if rest else None
            info = resolve_project(owner)
            print(json.dumps(info))
            return 0

        elif command == "pr-findings":
            if not rest:
                print("Usage: pr-findings <pr-number> [owner/repo]", file=sys.stderr)
                return 1
            pr_num = rest[0]
            repo = rest[1] if len(rest) > 1 else None
            findings = get_pr_findings(pr_num, repo)
            print(json.dumps(findings))
            return 0

        else:
            print(f"Unknown command: {command}", file=sys.stderr)
            return 1

    except (GitHubError, ACNotFoundError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
