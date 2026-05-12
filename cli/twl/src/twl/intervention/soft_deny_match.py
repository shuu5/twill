#!/usr/bin/env python3
"""soft_deny_match: permission UI の応答を soft_deny ルールと照合する。

exit code:
  0 = no-match (Layer 0 Auto 承認)
  1 = match-confirm (Layer 1 Confirm 昇格)
  2 = match-escalate (Layer 2 Escalate 昇格)

Usage:
  python3 -m twl.intervention.soft_deny_match \\
    --prompt-context "<pane text>" \\
    [--session-id <id>] \\
    [--observation-dir <dir>]
"""

import argparse
import datetime
import json
import os
import pathlib
import re
import sys
from typing import Any


# ---------------------------------------------------------------------------
# Rules loading
# ---------------------------------------------------------------------------

def _find_rules_file() -> pathlib.Path:
    """soft-deny-rules.md を探す。SOFT_DENY_RULES_PATH 環境変数を優先する。"""
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
        # PyYAML unavailable: basic fallback (should not happen in production)
        yaml = None  # type: ignore

    text = rules_path.read_text(encoding="utf-8")

    # frontmatter yaml を優先、次に fenced yaml block
    yaml_text = _extract_yaml_from_frontmatter(text) or _extract_yaml_from_fence(text)
    if not yaml_text:
        return []

    if yaml is None:
        # yaml unavailable: parse manually (minimal)
        return []

    data = yaml.safe_load(yaml_text)
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
        if regex and re.search(regex, prompt_context):
            return "match-escalate", rule_id

    for rule in confirm_rules:
        regex = rule.get("regex", "")
        rule_id = rule.get("id", "unknown")
        if regex and re.search(regex, prompt_context):
            return "match-confirm", rule_id

    return "no-match", None


# ---------------------------------------------------------------------------
# soft-deny-counter.json recording
# ---------------------------------------------------------------------------

def record_soft_deny_counter(
    observation_dir: str,
    session_id: str,
    category: str,
) -> None:
    """soft-deny-counter.json に match 記録を append する。

    counter json 形式: {"entries": [{"ts": "iso8601", "category": "rule_id"}]}
    """
    counter_dir = pathlib.Path(observation_dir) / session_id
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

    # atomic write (write + replace)
    tmp_file = counter_file.with_suffix(".tmp")
    tmp_file.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    tmp_file.replace(counter_file)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="soft_deny_match: permission UI の応答を soft_deny ルールと照合する",
    )
    parser.add_argument(
        "--prompt-context",
        required=True,
        help="tmux pane から取得した permission UI の文脈テキスト",
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
    args = parser.parse_args()

    # ルール読み込み
    rules_path = _find_rules_file()
    if not rules_path.exists():
        # ルールファイルが見つからない場合は no-match として扱う
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
        except OSError as e:
            print(f"warning: soft-deny-counter.json 記録失敗: {e}", file=sys.stderr)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
