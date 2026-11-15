#!/usr/bin/env bash
# Runs every security and quality check. CI runs this exact script.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# Prefer tools from the local virtual environment when it exists.
if [[ -d .venv/bin ]]; then
    export PATH="$PWD/.venv/bin:$PATH"
fi

GREEN=$'\033[32m'; RED=$'\033[31m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
failures=0

run_check() {
    local name="$1"; shift
    local output
    if output="$("$@" 2>&1)"; then
        printf '  %s✔ PASS%s  %s\n' "$GREEN" "$RESET" "$name"
    else
        printf '  %s✘ FAIL%s  %s\n' "$RED" "$RESET" "$name"
        printf '%s\n' "$output" | sed "s/^/          ${DIM}/; s/\$/${RESET}/"
        failures=$((failures + 1))
    fi
}

check_required_files() {
    local missing=0
    for f in README.md SECURITY.md LICENSE docs/threat-model.md docs/scope.example.yaml; do
        [[ -f "$f" ]] || { echo "missing: $f"; missing=1; }
    done
    return "$missing"
}

check_no_env_files() {
    local found
    found="$(git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v '\.env\.example$' || true)"
    [[ -z "$found" ]] || { echo "tracked env file: $found"; return 1; }
}

check_secrets() {
    git ls-files -z | xargs -0 detect-secrets-hook --baseline .secrets.baseline
}

check_shell() {
    git ls-files -z '*.sh' | xargs -0 --no-run-if-empty shellcheck
}

check_yaml() {
    yamllint --strict .
}

printf '\n%sPrivate AI Security Lab · checks%s\n\n' "$BOLD" "$RESET"
run_check "Required files present"          check_required_files
run_check "No .env files tracked"           check_no_env_files
run_check "No secrets (detect-secrets)"     check_secrets
run_check "Shell scripts (shellcheck)"      check_shell
run_check "YAML (yamllint --strict)"        check_yaml
echo

if (( failures > 0 )); then
    printf '%s%d check(s) failed.%s\n\n' "$RED$BOLD" "$failures" "$RESET"
    exit 1
fi
printf '%sAll checks passed.%s\n\n' "$GREEN$BOLD" "$RESET"
