#!/usr/bin/env bash
# harden-spark.sh - Part 2 of "The Private AI Security Lab"
#
# Brings a DGX Spark (DGX OS 7, Ubuntu 24.04 based) to a hardened baseline.
# Safe by default: without --apply it only prints what it would change.
#
#   sudo bash infra/spark/harden-spark.sh --admin-cidr 10.66.10.0/24            # dry run
#   sudo bash infra/spark/harden-spark.sh --admin-cidr 10.66.10.0/24 --apply    # make changes
#
# Every file it changes is backed up first, and a rollback script is written
# next to the backups.
set -euo pipefail

VERSION="1.0.0"

# ---------- defaults (override with flags) ----------
APPLY=0
ADMIN_CIDR=""
TARGET_USER="${SUDO_USER:-}"
SKIP_UPDATES=0
DISABLE_WIFI=0
KEEP_BLUETOOTH=0
ALLOW_MDNS_CIDR=""

usage() {
    cat <<EOF
harden-spark.sh ${VERSION}

Usage: sudo bash $0 --admin-cidr CIDR [options]

Required:
  --admin-cidr CIDR      Network allowed to SSH in, e.g. 10.66.10.0/24

Options:
  --apply                Make the changes (default is a dry run)
  --user NAME            Account allowed to log in over SSH (default: \$SUDO_USER)
  --skip-updates         Skip apt dist-upgrade
  --disable-wifi         Turn off the Wi-Fi radio (only if the Spark is on Ethernet)
  --keep-bluetooth       Leave Bluetooth enabled
  --allow-mdns CIDR      Allow mDNS (UDP 5353) from CIDR so NVIDIA Sync can discover the Spark
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --admin-cidr) ADMIN_CIDR="${2:?}"; shift ;;
        --user) TARGET_USER="${2:?}"; shift ;;
        --skip-updates) SKIP_UPDATES=1 ;;
        --disable-wifi) DISABLE_WIFI=1 ;;
        --keep-bluetooth) KEEP_BLUETOOTH=1 ;;
        --allow-mdns) ALLOW_MDNS_CIDR="${2:?}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

# ---------- output helpers ----------
if [[ -t 1 ]]; then
    B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else
    B=""; G=""; Y=""; R=""; C=""; N=""
fi
section() { printf '\n%s==> %s%s\n' "$B$C" "$1" "$N"; }
ok()      { printf '  %s✔%s %s\n' "$G" "$N" "$1"; }
plan()    { printf '  %s→%s %s\n' "$Y" "$N" "$1"; }
warn()    { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }
die()     { printf '%s✘ %s%s\n' "$R" "$1" "$N" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
# Persistent across runs: originals are saved once, so re-running the script
# never overwrites the true pre-hardening copies.
BACKUP_DIR="/var/backups/harden-spark"
ORIGINALS="${BACKUP_DIR}/originals"
CREATED_LIST="${BACKUP_DIR}/created.list"

# Run a command with its output sent to the evidence log, or describe it in dry-run mode.
run_quiet() {
    if (( APPLY )); then
        printf '  %s…%s %s\n' "$C" "$N" "$*"
        "$@" >> "${EVIDENCE_DIR}/apt-${STAMP}.log" 2>&1 || die "failed: $* (see ${EVIDENCE_DIR}/apt-${STAMP}.log)"
    else
        plan "would run: $*"
    fi
}

# Run a command, or describe it in dry-run mode.
run() {
    if (( APPLY )); then
        "$@" >/dev/null
        ok "$*"
    else
        plan "would run: $*"
    fi
}

was_created_by_us() { [[ -f "$CREATED_LIST" ]] && grep -qxF "$1" "$CREATED_LIST"; }

# Save the pre-hardening copy of a file, once.
backup() {
    local f="$1"
    if [[ -e "$f" && ! -e "${ORIGINALS}${f}" ]] && ! was_created_by_us "$f"; then
        mkdir -p "${ORIGINALS}$(dirname "$f")"
        cp -a "$f" "${ORIGINALS}${f}"
    fi
}

# Write a file only if its content differs. Backs up any existing version.
put_file() {
    local path="$1" mode="$2" content="$3"
    if [[ -f "$path" ]] && [[ "$(cat "$path")" == "$content" ]]; then
        ok "$path already in place"
        return 0
    fi
    if (( APPLY )); then
        if [[ -e "$path" ]]; then backup "$path"; else echo "$path" >> "$CREATED_LIST"; fi
        mkdir -p "$(dirname "$path")"
        printf '%s\n' "$content" > "$path"
        chmod "$mode" "$path"
        ok "wrote $path"
    else
        plan "would write $path"
    fi
}

cidr_valid() {
    python3 - "$1" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_network(sys.argv[1], strict=False)
except ValueError:
    sys.exit(1)
PY
}

ip_in_cidr() {
    python3 - "$1" "$2" <<'PY'
import ipaddress, sys
sys.exit(0 if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2], strict=False) else 1)
PY
}

unit_exists() { systemctl list-unit-files "$1" >/dev/null 2>&1 && systemctl list-unit-files "$1" | grep -q "^$1"; }

# ---------- 0. preflight ----------
section "Preflight"
[[ $EUID -eq 0 ]] || die "Run with sudo."
[[ -n "$ADMIN_CIDR" ]] || { usage; die "--admin-cidr is required."; }
cidr_valid "$ADMIN_CIDR" || die "Not a valid CIDR: $ADMIN_CIDR"
[[ -z "$ALLOW_MDNS_CIDR" ]] || cidr_valid "$ALLOW_MDNS_CIDR" || die "Not a valid CIDR: $ALLOW_MDNS_CIDR"
if [[ -z "$TARGET_USER" ]] || ! id "$TARGET_USER" >/dev/null 2>&1; then
    die "Unknown user '${TARGET_USER}'. Use --user."
fi

if [[ -f /etc/dgx-release ]]; then
    ok "DGX OS detected: $(grep -m1 DGX_SWBUILD_VERSION /etc/dgx-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo unknown)"
else
    warn "/etc/dgx-release not found. This does not look like DGX OS; continuing as plain Ubuntu."
fi
ok "mode: $( (( APPLY )) && echo "${R}APPLY${N}" || echo "dry run (add --apply to make changes)")"
ok "SSH user: ${TARGET_USER}   admin network: ${ADMIN_CIDR}"

# Lockout guard 1: the SSH user must already have a key installed.
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
AUTH_KEYS="${USER_HOME}/.ssh/authorized_keys"
if [[ -s "$AUTH_KEYS" ]] && grep -Eq '^(ssh-|ecdsa-|sk-)' "$AUTH_KEYS"; then
    ok "found $(grep -Ec '^(ssh-|ecdsa-|sk-)' "$AUTH_KEYS") SSH key(s) for ${TARGET_USER}"
else
    die "No SSH key in ${AUTH_KEYS}. Run ssh-copy-id from your workstation first, or you will be locked out."
fi

# Lockout guard 2: every live SSH session must come from inside the admin network.
# (sudo strips SSH_CONNECTION, so we read the sessions from the socket table instead.)
SSH_PEERS="$(ss -tnH state established '( sport = :22 )' 2>/dev/null \
    | awk '{print $4}' | sed -E 's/:[0-9]+$//; s/^\[//; s/\]$//; s/^::ffff://' | sort -u)"
if [[ -z "$SSH_PEERS" ]]; then
    ok "no live SSH sessions (running from the console)"
else
    for peer in $SSH_PEERS; do
        if ip_in_cidr "$peer" "$ADMIN_CIDR"; then
            ok "SSH session from ${peer} is inside ${ADMIN_CIDR}"
        else
            die "SSH session from ${peer} is outside ${ADMIN_CIDR}. The firewall would cut it off."
        fi
    done
fi

EVIDENCE_DIR="${USER_HOME}/lab-evidence/part-02"
if (( APPLY )); then
    mkdir -p "$EVIDENCE_DIR" "$BACKUP_DIR"
    ss -tulpnH > "${EVIDENCE_DIR}/listening-before-${STAMP}.txt" 2>/dev/null || true
fi

# ---------- 1. updates ----------
section "1. Updates"
if (( SKIP_UPDATES )); then
    warn "skipping apt dist-upgrade (--skip-updates)"
else
    run_quiet apt-get update
    run_quiet env DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade
fi
run_quiet env DEBIAN_FRONTEND=noninteractive apt-get -y install unattended-upgrades auditd ufw
put_file /etc/apt/apt.conf.d/20auto-upgrades 0644 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
# shellcheck disable=SC2016  # ${distro_id} is expanded by apt, not bash
put_file /etc/apt/apt.conf.d/52harden-spark 0644 '// Security updates only, and never reboot on our behalf:
// a reboot mid-job kills long model runs.
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";'
plan "firmware: update through DGX Dashboard, or run 'fwupdmgr refresh && fwupdmgr upgrade' in a maintenance window"

# ---------- 2. SSH ----------
section "2. SSH: keys only, one user, no root"
SSHD_DROPIN="/etc/ssh/sshd_config.d/10-harden-spark.conf"
put_file "$SSHD_DROPIN" 0644 "# Managed by harden-spark.sh. Files in sshd_config.d are read in order and the
# first value wins, so the 10- prefix takes precedence over 50-cloud-init.conf.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers ${TARGET_USER}
MaxAuthTries 3
LoginGraceTime 30
MaxSessions 4
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowAgentForwarding no
# 'local' keeps 'ssh -L 11000:localhost:11000' working for DGX Dashboard.
AllowTcpForwarding local
PermitTunnel no
Banner /etc/issue.net
LogLevel VERBOSE"
BANNER='Authorized use only. This system is part of a private security lab.
All activity is logged and reviewed.'
put_file /etc/issue.net 0644 "$BANNER"
put_file /etc/issue 0644 "$BANNER"
if (( APPLY )); then
    if sshd -t; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd
        ok "sshd config valid and reloaded (existing sessions stay open)"
    else
        rm -f "$SSHD_DROPIN"
        die "sshd -t rejected the new config; removed it. Nothing else in this section changed."
    fi
fi

# ---------- 3. firewall ----------
section "3. Firewall: deny inbound by default"
run ufw --force reset
run ufw default deny incoming
run ufw default allow outgoing
run ufw limit from "$ADMIN_CIDR" to any port 22 proto tcp comment 'SSH from admin network'
if [[ -n "$ALLOW_MDNS_CIDR" ]]; then
    run ufw allow from "$ALLOW_MDNS_CIDR" to any port 5353 proto udp comment 'mDNS for NVIDIA Sync'
fi
run ufw logging low
run ufw --force enable
if (( APPLY )); then ufw status verbose | sed 's/^/      /'; fi
plan "outbound stays open for now; Part 3 moves egress control to the lab network"

# ---------- 4. kernel ----------
section "4. Kernel and network settings"
put_file /etc/sysctl.d/60-harden-spark.conf 0644 '# Managed by harden-spark.sh
# Leave net.ipv4.ip_forward alone: Docker needs it.
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.sysrq = 0
fs.suid_dumpable = 0
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0'
run sysctl -q -e --system
put_file /etc/modprobe.d/60-harden-spark.conf 0644 '# Rarely used network protocols with a history of kernel bugs
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false'
put_file /etc/security/limits.d/60-harden-spark.conf 0644 '# No core dumps: they can contain model prompts and secrets
* hard core 0'

# ---------- 5. radios and services ----------
section "5. Radios and unused services"
if (( KEEP_BLUETOOTH )); then
    warn "keeping Bluetooth (--keep-bluetooth)"
elif unit_exists bluetooth.service; then
    run systemctl disable --now bluetooth.service
    if command -v rfkill >/dev/null 2>&1; then run rfkill block bluetooth; fi
else
    ok "Bluetooth service not present"
fi
if (( DISABLE_WIFI )); then
    run nmcli radio wifi off
else
    warn "Wi-Fi radio left on. Use --disable-wifi once the Spark is on Ethernet."
fi
for unit in cups.service cups-browsed.service ModemManager.service; do
    if unit_exists "$unit"; then run systemctl disable --now "$unit"; else ok "${unit} not present"; fi
done
if command -v docker >/dev/null 2>&1; then
    published="$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -- '->' || true)"
    if [[ -n "$published" ]]; then
        warn "containers publish ports, and Docker bypasses ufw for them (fixed in Part 4):"
        printf '%s\n' "$published" | sed 's/^/      /'
    else
        ok "no containers publishing ports"
    fi
fi

# ---------- 6. accounts and sudo ----------
section "6. Accounts and sudo"
put_file /etc/sudoers.d/60-harden-spark 0440 'Defaults use_pty
Defaults logfile="/var/log/sudo.log"
Defaults timestamp_timeout=5'
if (( APPLY )); then
    visudo -cf /etc/sudoers.d/60-harden-spark >/dev/null || { rm -f /etc/sudoers.d/60-harden-spark; die "visudo rejected the sudoers file; removed it."; }
fi
if grep -qE '^UMASK[[:space:]]+027' /etc/login.defs; then
    ok "login.defs UMASK already 027"
elif (( APPLY )); then
    backup /etc/login.defs
    sed -i -E 's/^UMASK[[:space:]]+[0-9]+/UMASK\t\t027/' /etc/login.defs
    ok "login.defs UMASK set to 027"
else
    plan "would set UMASK 027 in /etc/login.defs"
fi
run passwd -l root

# ---------- 7. audit logging ----------
section "7. Audit logging"
put_file /etc/audit/rules.d/60-harden-spark.rules 0640 '## Managed by harden-spark.sh
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k privilege
-w /etc/sudoers.d/ -p wa -k privilege
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/ssh/sshd_config.d/ -p wa -k sshd
-w /etc/docker/ -p wa -k docker
-w /etc/ufw/ -p wa -k firewall
-w /usr/bin/sudo -p x -k privilege
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules'
run systemctl enable --now auditd
run augenrules --load
put_file /etc/systemd/journald.conf.d/60-harden-spark.conf 0644 '[Journal]
Storage=persistent
SystemMaxUse=2G'
run systemctl restart systemd-journald

# ---------- 8. encryption check (report only) ----------
section "8. Encryption at rest (report only)"
if lsblk -no FSTYPE 2>/dev/null | grep -q crypto_LUKS; then
    ok "LUKS-encrypted volume found"
else
    warn "no LUKS volume found. The Spark's NVMe drive is self-encrypting, but software"
    warn "full-disk encryption needs a reinstall. See the article for the options."
fi

# ---------- done ----------
section "Done"
if (( APPLY )); then
    ss -tulpnH > "${EVIDENCE_DIR}/listening-after-${STAMP}.txt" 2>/dev/null || true
    {
        echo '#!/usr/bin/env bash'
        echo "# Rollback for harden-spark.sh (regenerated on every run; last run ${STAMP})"
        echo "# Restores the pre-hardening originals and removes every file the script created."
        echo 'set -euo pipefail'
        echo "if [[ -d '${ORIGINALS}' ]]; then cp -a '${ORIGINALS}/.' /; fi"
        if [[ -f "$CREATED_LIST" ]]; then
            sort -u "$CREATED_LIST" | while read -r f; do echo "rm -f '$f'"; done
        fi
        echo "rm -f '${CREATED_LIST}'"
        echo 'ufw --force disable'
        echo 'sysctl -q -e --system'
        echo 'augenrules --load || true'
        echo 'systemctl restart systemd-journald'
        echo 'systemctl reload ssh 2>/dev/null || systemctl reload sshd'
        echo 'echo "Rolled back. Re-enable Bluetooth/Wi-Fi manually if needed."'
    } > "${BACKUP_DIR}/rollback.sh"
    chmod 700 "${BACKUP_DIR}/rollback.sh"
    chown -R "$TARGET_USER": "${USER_HOME}/lab-evidence"
    ok "backups and rollback script: ${BACKUP_DIR}"
    ok "evidence: ${EVIDENCE_DIR}"
    warn "keep this SSH session open and test a NEW login before you log out"
else
    ok "dry run complete. Nothing was changed. Re-run with --apply."
fi
