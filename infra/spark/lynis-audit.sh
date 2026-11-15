#!/usr/bin/env bash
# lynis-audit.sh - run a Lynis audit and keep the report as evidence.
#
#   sudo bash infra/spark/lynis-audit.sh before
#   sudo bash infra/spark/lynis-audit.sh after
#
# Reports go to ~/lab-evidence/part-02/lynis-<label>.dat (and .log).
set -euo pipefail

LABEL="${1:-}"
[[ "$LABEL" =~ ^[a-z0-9-]+$ ]] || { echo "Usage: sudo bash $0 before|after" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

TARGET_USER="${SUDO_USER:-root}"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
EVIDENCE_DIR="${USER_HOME}/lab-evidence/part-02"
mkdir -p "$EVIDENCE_DIR"

if ! command -v lynis >/dev/null 2>&1; then
    echo "Installing Lynis from the Ubuntu archive..."
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install lynis >/dev/null
fi

REPORT="${EVIDENCE_DIR}/lynis-${LABEL}.dat"
LOG="${EVIDENCE_DIR}/lynis-${LABEL}.log"

echo "Running Lynis $(lynis --version) (takes 1-3 minutes)..."
lynis audit system --quiet --no-colors --report-file "$REPORT" --log-file "$LOG" 2>>"${LOG%.log}.stderr" || true
chown -R "$TARGET_USER": "${USER_HOME}/lab-evidence"

value() { grep -m1 "^$1=" "$REPORT" | cut -d= -f2-; }
B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; N=$'\033[0m'
printf '\n%sLynis audit: %s%s\n' "$B" "$LABEL" "$N"
printf '  Hardening index : %s%s%s / 100\n' "$G$B" "$(value hardening_index)" "$N"
printf '  Tests performed : %s\n' "$(value lynis_tests_done)"
printf '  Warnings        : %s%s%s\n' "$Y" "$(grep -c '^warning\[\]=' "$REPORT" || true)" "$N"
printf '  Suggestions     : %s\n' "$(grep -c '^suggestion\[\]=' "$REPORT" || true)"
printf '  Report          : %s\n\n' "$REPORT"
