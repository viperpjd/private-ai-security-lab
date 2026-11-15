#!/usr/bin/env bash
# capture.sh - record a command and its output for the article screenshots.
#
#   bash scripts/capture.sh 02-nvidia-smi -- nvidia-smi
#   bash scripts/capture.sh 05-harden-apply -- sudo bash infra/spark/harden-spark.sh --admin-cidr 10.66.10.0/24 --apply
#   bash scripts/capture.sh --bundle          # zip every capture to send for rendering
#
# Output keeps colors and goes to ~/lab-evidence/captures/<name>.txt.
# By default it redacts hostnames, your username, MAC addresses, key fingerprints,
# serial numbers, and any IP address outside the lab's documented 10.66.0.0/16 range.
set -euo pipefail

CAPTURE_DIR="${CAPTURE_DIR:-$HOME/lab-evidence/captures}"
HOST_ALIAS="${CAPTURE_HOST_ALIAS:-spark-a}"
USER_ALIAS="${CAPTURE_USER_ALIAS:-analyst}"
KEEP_NET="${CAPTURE_KEEP_NET:-10.66.0.0/16}"

usage() {
    echo "Usage: $0 NAME [--no-redact] -- COMMAND [ARGS...]"
    echo "       $0 --bundle"
}

if [[ "${1:-}" == "--bundle" ]]; then
    out="$HOME/lab-evidence/captures-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$out" -C "$(dirname "$CAPTURE_DIR")" "$(basename "$CAPTURE_DIR")"
    echo "Bundle: $out"
    exit 0
fi

NAME="${1:-}"; shift || true
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { usage; exit 2; }
REDACT=1
if [[ "${1:-}" == "--no-redact" ]]; then REDACT=0; shift; fi
[[ "${1:-}" == "--" ]] || { usage; exit 2; }
shift
(( $# > 0 )) || { usage; exit 2; }

mkdir -p "$CAPTURE_DIR"
chmod 700 "$CAPTURE_DIR"
RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

# Quote the command so 'script' runs exactly what was passed.
CMD="$(printf '%q ' "$@")"
CMD="${CMD% }"

# 'script' gives the command a real terminal, so tools keep their colors.
set +e
if script --version 2>&1 | grep -q util-linux; then
    script -q -e -c "$CMD" /dev/null | tee "$RAW"          # Linux (util-linux)
else
    script -q /dev/null bash -c "$CMD" | tee "$RAW"        # macOS / BSD
fi
STATUS=${PIPESTATUS[0]}
set -e

OUT="${CAPTURE_DIR}/${NAME}.txt"
python3 - "$RAW" "$OUT" "$*" "$STATUS" "$REDACT" "$HOST_ALIAS" "$USER_ALIAS" "$KEEP_NET" <<'PY'
import ipaddress, json, os, re, socket, sys, getpass, datetime
raw, out, cmd, status, redact, host_alias, user_alias, keep_net = sys.argv[1:9]
text = open(raw, encoding="utf-8", errors="replace").read().replace("\r\n", "\n").replace("\r", "")
text = re.sub(r"\x1b\[\?[0-9;]*[a-zA-Z]|\x1b[=>]", "", text)   # drop pager/cursor codes, keep colors

def scrub(s):
    keep = ipaddress.ip_network(keep_net)
    host = socket.gethostname()
    names = sorted({host, host.split(".")[0], socket.getfqdn()}, key=len, reverse=True)
    for n in names:
        if n and n not in ("localhost",):
            s = re.sub(rf"(?<![\w.-]){re.escape(n)}(?![\w-])", host_alias, s)
    user = os.environ.get("SUDO_USER") or getpass.getuser()
    if user not in ("root",):
        s = re.sub(rf"\b{re.escape(user)}\b", user_alias, s)
    ipmap = {}
    def ip4(m):
        ip = m.group(0)
        try:
            a = ipaddress.ip_address(ip)
        except ValueError:
            return ip
        if a.is_loopback or a.is_unspecified or a in keep or a.is_multicast or ip.endswith(".255"):
            return ip
        ipmap.setdefault(ip, f"192.0.2.{len(ipmap) + 10}")
        return ipmap[ip]
    s = re.sub(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])", ip4, s)
    macs = {}
    s = re.sub(r"\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b",
               lambda m: macs.setdefault(m.group(0).lower(), f"02:00:00:00:00:{len(macs) + 1:02x}"), s)
    s = re.sub(r"\b(?:fe80|2[0-9a-f]{3}):[0-9a-fA-F:]{4,}\b", "2001:db8::1", s)
    s = re.sub(r"SHA256:[A-Za-z0-9+/=]{20,}", "SHA256:<redacted>", s)
    s = re.sub(r"(?i)(serial(?: number)?\s*[:=]\s*)\S+", r"\1<redacted>", s)
    return s

if redact == "1":
    text = scrub(text)
    cmd = scrub(cmd)
header = json.dumps({"command": cmd, "exit": int(status), "redacted": redact == "1",
                     "captured": datetime.datetime.now().isoformat(timespec="seconds")})
with open(out, "w", encoding="utf-8") as f:
    f.write("#capture " + header + "\n" + text)
PY
chmod 600 "$OUT"
echo
echo "Saved ${OUT} (exit ${STATUS}). Check it before you share it: $([[ $REDACT == 1 ]] && echo 'redacted' || echo 'NOT redacted')."
exit "$STATUS"
