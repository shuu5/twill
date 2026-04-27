#!/usr/bin/env bash
# dispatch-info step entry point — delegates to chain-runner.sh
exec "$(dirname "$0")/../chain-runner.sh" dispatch-info "$@"
