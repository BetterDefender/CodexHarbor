#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/CodexHarbor" dist
for item in Package.swift .gitignore README.md README.zh-CN.md LICENSE THIRD_PARTY_NOTICES.md CHANGELOG.md Sources Tests scripts docs windows; do
    cp -R "$item" "$STAGING/CodexHarbor/"
done
rm -rf "$STAGING/CodexHarbor/windows/node_modules" "$STAGING/CodexHarbor/windows/dist" "$STAGING/CodexHarbor/windows/out"
mkdir -p "$STAGING/CodexHarbor/Vendor"
cp -R Vendor/core "$STAGING/CodexHarbor/Vendor/"
COPYFILE_DISABLE=1 tar -czf dist/CodexHarbor-1.0.0-source.tar.gz --exclude='.DS_Store' -C "$STAGING" CodexHarbor
echo "dist/CodexHarbor-1.0.0-source.tar.gz"
