#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/CodexHarbor/Localization.swift Sources/CodexHarbor/Theme.swift Sources/CodexHarbor/Backend.swift Tests/main.swift -o "$TEST_DIR/model-tests"
"$TEST_DIR/model-tests"
python3 scripts/smoke.py
swiftc Sources/CodexHarbor/Localization.swift Sources/CodexHarbor/Backend.swift Sources/CodexHarbor/ClientRestart.swift Tests/RestartTests.swift -o "$TEST_DIR/restart-tests"
"$TEST_DIR/restart-tests"
