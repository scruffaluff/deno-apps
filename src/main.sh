#!/usr/bin/env sh
#
# Wrapper script to setup Deno apps before execution.

# Exit immediately if a command exits with non-zero return code.
#
# Flags:
#   -e: Exit immediately when a command fails.
#   -u: Throw an error when an unset variable is encountered.
set -eu

app="$(dirname "$(realpath "${0}")")/index.ts"
mkdir -p "${HOME}/.local/deno-apps"
cd "${HOME}/.local/deno-apps"
PATH="/usr/local/bin:${PATH}" "${app}"
