#!/usr/bin/env bash
# llm-delegate step entry point — delegates to chain-runner.sh
exec "$(dirname "$0")/../chain-runner.sh" llm-delegate "$@"
