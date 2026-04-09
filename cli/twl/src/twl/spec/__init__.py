"""twl spec - Spec Management subcommands (port of deltaspec bash CLI)."""

import argparse
import sys


def main(argv: list[str] | None = None) -> None:
    if argv is None:
        argv = sys.argv[2:]  # skip 'twl' and 'spec'

    parser = argparse.ArgumentParser(
        prog="twl spec",
        description="Manage delta specs (deltaspec/changes/)",
    )
    sub = parser.add_subparsers(dest="subcmd", metavar="<command>")

    # new
    p_new = sub.add_parser("new", help="Create a new change directory")
    p_new.add_argument("name", help="Change name (kebab-case)")

    # status
    p_status = sub.add_parser("status", help="Show artifact completion status")
    p_status.add_argument("name", help="Change name")
    p_status.add_argument("--json", action="store_true", help="JSON output")

    # list
    p_list = sub.add_parser("list", help="List all changes")
    p_list.add_argument("--json", action="store_true", help="JSON output")
    p_list.add_argument("--sort", choices=["recent", "name"], default="recent")

    # archive
    p_archive = sub.add_parser("archive", help="Archive a completed change")
    p_archive.add_argument("name", help="Change name")
    p_archive.add_argument("-y", "--yes", action="store_true", help="Skip confirmation")
    p_archive.add_argument("--skip-specs", action="store_true", help="Skip spec integration")

    # validate
    p_validate = sub.add_parser("validate", help="Validate spec syntax")
    p_validate.add_argument("name", nargs="?", help="Change name (omit for --all)")
    p_validate.add_argument("--all", action="store_true", help="Validate all changes")
    p_validate.add_argument("--json", action="store_true", help="JSON output")
    p_validate.add_argument("--coverage", action="store_true", help="Check invariant coverage against deltaspec/specs/")

    # instructions
    p_instructions = sub.add_parser("instructions", help="Get artifact build instructions")
    p_instructions.add_argument("artifact", help="Artifact ID (proposal/design/specs/tasks/apply)")
    p_instructions.add_argument("name", help="Change name")
    p_instructions.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args(argv)

    if args.subcmd is None:
        parser.print_help()
        sys.exit(1)

    if args.subcmd == "new":
        from .new import cmd_new
        sys.exit(cmd_new(args.name))
    elif args.subcmd == "status":
        from .status import cmd_status
        sys.exit(cmd_status(args.name, json_mode=args.json))
    elif args.subcmd == "list":
        from .list import cmd_list
        sys.exit(cmd_list(json_mode=args.json, sort_order=args.sort))
    elif args.subcmd == "archive":
        from .archive import cmd_archive
        sys.exit(cmd_archive(args.name, yes=args.yes, skip_specs=args.skip_specs))
    elif args.subcmd == "validate":
        from .validate import cmd_coverage, cmd_validate
        if args.coverage:
            sys.exit(cmd_coverage())
        sys.exit(cmd_validate(args.name, validate_all=args.all, json_mode=args.json))
    elif args.subcmd == "instructions":
        from .instructions import cmd_instructions
        sys.exit(cmd_instructions(args.artifact, args.name, json_mode=args.json))
