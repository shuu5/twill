#!/usr/bin/env python3
"""soft_deny_match: permission UI の応答を soft_deny ルールと照合する。

exit code:
  0 = no-match (Layer 0 Auto 承認)
  1 = match-confirm (Layer 1 Confirm 昇格)
  2 = match-escalate (Layer 2 Escalate 昇格)

Usage:
  python3 -m twl.intervention.soft_deny_match \\
    --prompt-context "<pane text>" \\
    [--rules-path <path-to-soft-deny-rules.md>] \\
    [--session-id <id>] \\
    [--observation-dir <dir>] \\
    [--count-category <rule_id>]
"""

import argparse
import datetime
import json
import os
import pathlib
import re
import sys
import tempfile
from typing import Any


# ---------------------------------------------------------------------------
# Rules loading
# ---------------------------------------------------------------------------

def _find_rules_file(rules_path_arg: str | None = None) -> pathlib.Path:
    """soft-deny-rules.md を探す。優先順位: 引数 > 環境変数 > 相対パス。"""
    if rules_path_arg:
        return pathlib.Path(rules_path_arg)

    env_path = os.environ.get("SOFT_DENY_RULES_PATH")
    if env_path:
        return pathlib.Path(env_path)

    # このファイルから相対パスでフォールバック
    # cli/twl/src/twl/intervention/soft_deny_match.py
    # -> plugins/twl/skills/su-observer/refs/soft-deny-rules.md
    this_file = pathlib.Path(__file__).resolve()
    # cli/twl/src/twl/intervention -> cli/twl/src/twl -> cli/twl/src -> cli/twl -> cli -> repo_root
    repo_root = this_file.parent.parent.parent.parent.parent.parent
    candidate = repo_root / "plugins" / "twl" / "skills" / "su-observer" / "refs" / "soft-deny-rules.md"
    return candidate


def _extract_yaml_from_frontmatter(text: str) -> str:
    """--- ... --- frontmatter を抽出して yaml 文字列を返す。"""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    end_idx = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end_idx = i
            break
    if end_idx is None:
        return ""
    return "\n".join(lines[1:end_idx])


def _extract_yaml_from_fence(text: str) -> str:
    """```yaml ... ``` フェンスブロックを抽出して yaml 文字列を返す。"""
    import re as _re
    pattern = _re.compile(r"```yaml\s*\n(.*?)```", _re.DOTALL)
    match = pattern.search(text)
    if match:
        return match.group(1)
    return ""


def load_rules(rules_path: pathlib.Path) -> list[dict[str, Any]]:
    """soft-deny-rules.md を parse して rule list を返す。"""
    try:
        import yaml  # type: ignore
    except ImportError:
        yaml = None  # type: ignore

    text = rules_path.read_text(encoding="utf-8")

    # frontmatter yaml を優先、次に fenced yaml block
    yaml_text = _extract_yaml_from_frontmatter(text) or _extract_yaml_from_fence(text)
    if not yaml_text:
        return []

    if yaml is None:
        return []

    try:
        data = yaml.safe_load(yaml_text)
    except Exception:
        return []

    if not isinstance(data, dict):
        return []
    return data.get("rules", [])


# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------

def match_rules(
    prompt_context: str,
    rules: list[dict[str, Any]],
) -> tuple[str, str | None]:
    """prompt_context に対して rules を照合する。

    Returns:
        (result, matched_rule_id):
          result = "no-match" | "match-confirm" | "match-escalate"
          matched_rule_id = None または rule["id"]
    """
    # escalate ルールを先に評価（より強い制約が優先）
    escalate_rules = [r for r in rules if r.get("layer") == "escalate"]
    confirm_rules = [r for r in rules if r.get("layer") == "confirm"]

    for rule in escalate_rules:
        regex = rule.get("regex", "")
        rule_id = rule.get("id", "unknown")
        try:
            if regex and re.search(regex, prompt_context):
                return "match-escalate", rule_id
        except re.error:
            continue

    for rule in confirm_rules:
        regex = rule.get("regex", "")
        rule_id = rule.get("id", "unknown")
        try:
            if regex and re.search(regex, prompt_context):
                return "match-confirm", rule_id
        except re.error:
            continue

    return "no-match", None


# ---------------------------------------------------------------------------
# soft-deny-counter.json recording
# ---------------------------------------------------------------------------

_SESSION_ID_PATTERN = re.compile(r'^[A-Za-z0-9._-]+$')


def _validate_session_id(session_id: str) -> bool:
    """session_id がパストラバーサルに安全な文字のみを含むか検証する。"""
    return bool(_SESSION_ID_PATTERN.fullmatch(session_id))


def record_soft_deny_counter(
    observation_dir: str,
    session_id: str,
    category: str,
) -> None:
    """soft-deny-counter.json に match 記録を append する。

    counter json 形式: {"entries": [{"ts": "iso8601", "category": "rule_id"}]}
    """
    # パストラバーサル防止: session_id を allowlist で検証
    if not _validate_session_id(session_id):
        raise ValueError(f"invalid session_id (unsafe chars): {session_id!r}")

    obs_root = pathlib.Path(observation_dir).resolve()
    counter_dir = obs_root / session_id
    # 結合後のパスが obs_root 配下であることを検証
    try:
        counter_dir.relative_to(obs_root)
    except ValueError:
        raise ValueError(f"session_id causes path traversal: {session_id!r}")

    counter_dir.mkdir(parents=True, exist_ok=True)
    counter_file = counter_dir / "soft-deny-counter.json"

    # 既存データを読み込む
    if counter_file.exists():
        try:
            data = json.loads(counter_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            data = {"entries": []}
    else:
        data = {"entries": []}

    # エントリ追加
    entry = {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "category": category,
    }
    data["entries"].append(entry)

    # atomic write (mkstemp で一意な tmp ファイルを使用)
    fd, tmp_path = tempfile.mkstemp(dir=counter_dir, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        pathlib.Path(tmp_path).replace(counter_file)
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def count_soft_deny_category(
    observation_dir: str,
    session_id: str,
    category: str,
) -> int:
    """指定カテゴリの soft_deny 検知回数を返す（soft-deny-counter.json から集計）。"""
    if not _validate_session_id(session_id):
        return 0

    obs_root = pathlib.Path(observation_dir).resolve()
    counter_file = obs_root / session_id / "soft-deny-counter.json"

    if not counter_file.exists():
        return 0

    try:
        data = json.loads(counter_file.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return 0

    return sum(1 for e in data.get("entries", []) if e.get("category") == category)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="soft_deny_match: permission UI の応答を soft_deny ルールと照合する",
    )
    parser.add_argument(
        "--prompt-context",
        default=None,
        help="tmux pane から取得した permission UI の文脈テキスト（--count-category 使用時は省略可）",
    )
    parser.add_argument(
        "--rules-path",
        default=None,
        help="soft-deny-rules.md のパス（省略時は SOFT_DENY_RULES_PATH 環境変数または自動探索）",
    )
    parser.add_argument(
        "--session-id",
        default=None,
        help="soft-deny-counter.json 記録用セッション ID",
    )
    parser.add_argument(
        "--observation-dir",
        default=".observation",
        help="soft-deny-counter.json を格納するディレクトリ（default: .observation）",
    )
    parser.add_argument(
        "--count-category",
        default=None,
        help="指定カテゴリの soft_deny 検知回数を stdout に出力して終了（照合は行わない）",
    )
    args = parser.parse_args()

    # --count-category モード: 指定カテゴリの回数を返して終了
    if args.count_category is not None:
        if not args.session_id:
            print("0")
            sys.exit(0)
        count = count_soft_deny_category(
            observation_dir=args.observation_dir,
            session_id=args.session_id,
            category=args.count_category,
        )
        print(str(count))
        sys.exit(0)

    # 照合モード: --prompt-context 必須
    if not args.prompt_context:
        parser.error("--prompt-context is required when not using --count-category")

    # ルール読み込み
    rules_path = _find_rules_file(args.rules_path)
    if not rules_path.exists():
        print("no-match")
        print("warning: soft-deny-rules.md not found, defaulting to no-match", file=sys.stderr)
        sys.exit(0)

    rules = load_rules(rules_path)

    # 照合
    result, matched_rule_id = match_rules(args.prompt_context, rules)

    # 出力
    if result == "no-match":
        print("no-match")
        exit_code = 0
    elif result == "match-confirm":
        print("match-confirm")
        if matched_rule_id:
            print(f"matched_rule: {matched_rule_id}")
        exit_code = 1
    else:  # match-escalate
        print("match-escalate")
        if matched_rule_id:
            print(f"matched_rule: {matched_rule_id}")
        exit_code = 2

    # soft-deny-counter.json への記録（match 時のみ）
    if result != "no-match" and args.session_id and matched_rule_id:
        try:
            record_soft_deny_counter(
                observation_dir=args.observation_dir,
                session_id=args.session_id,
                category=matched_rule_id,
            )
        except (OSError, ValueError) as e:
            print(f"warning: soft-deny-counter.json 記録失敗: {e}", file=sys.stderr)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
