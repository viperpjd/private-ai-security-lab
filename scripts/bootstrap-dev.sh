#!/usr/bin/env bash
# Creates a local virtual environment with the pinned check tools.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -d .venv ]]; then
    python3 -m venv .venv
fi

.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements-dev.txt
.venv/bin/pre-commit install

echo "Dev tools installed in .venv and the pre-commit hook is active."
