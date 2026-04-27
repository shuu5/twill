#!/usr/bin/env bash
# arch-ref step entry point — delegates to chain-runner.sh
exec "$(dirname "$0")/../chain-runner.sh" arch-ref "$@"
