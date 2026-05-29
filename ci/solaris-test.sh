#!/bin/sh
# Thin wrapper — delegates to the shared CI scripts in ipc-shareable.
# Usage: ./ci/solaris-test.sh [prove options]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_CI="$(cd "${SCRIPT_DIR}/../../ipc-shareable/ci" && pwd)"
exec "${SHARED_CI}/solaris-test.sh" --project async-event-interval "$@"
