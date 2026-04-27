#!/usr/bin/env bash
# chain-status step entry point — delegates to chain-runner.sh
exec "$(dirname "$0")/../chain-runner.sh" chain-status "$@"
