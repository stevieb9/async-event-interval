#!/bin/sh
# Thin wrapper — delegates to the shared CI scripts in ipc-shareable.
# Usage: ./ci/vm-tests.sh [vm flags] [prove options]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_CI="$(cd "${SCRIPT_DIR}/../../ipc-shareable/ci" && pwd)"
exec "${SHARED_CI}/vm-tests.sh" --project async-event-interval "$@"
