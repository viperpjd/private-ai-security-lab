# infra/spark

Part 2: harden a DGX Spark before any model touches it.

| File | What it does |
|------|--------------|
| `harden-spark.sh` | Idempotent hardening: updates, SSH keys only, default-deny firewall, kernel settings, radios and services, sudo and audit logging, encryption check. Dry run unless `--apply`. |
| `lynis-audit.sh` | Runs a Lynis audit and saves the report to `~/lab-evidence/part-02/` |
| `../../tools/lynis-compare/lynis_compare.py` | Compares two Lynis reports and writes a one-page HTML report |
| `../../scripts/capture.sh` | Records a command and its redacted output for documentation |

## Before you start

1. Finish first boot and connect **NVIDIA Sync**. Sync uses your password once during setup.
2. Copy your SSH key to the Spark: `ssh-copy-id <user>@<spark>.local`
3. Keep a keyboard and monitor nearby the first time.

## Run it

```bash
sudo bash infra/spark/lynis-audit.sh before
sudo bash infra/spark/harden-spark.sh --admin-cidr 10.66.10.0/24              # dry run
sudo bash infra/spark/harden-spark.sh --admin-cidr 10.66.10.0/24 --apply
sudo bash infra/spark/lynis-audit.sh after
python3 tools/lynis-compare/lynis_compare.py \
  ~/lab-evidence/part-02/lynis-before.dat ~/lab-evidence/part-02/lynis-after.dat \
  --html ~/lab-evidence/part-02/hardening-report.html
```

Replace `10.66.10.0/24` with the network your workstation connects from.
In Part 3 this becomes the lab's admin VLAN.

## Options

| Flag | Effect |
|------|--------|
| `--user NAME` | Account allowed to log in over SSH (default: the account running sudo) |
| `--skip-updates` | Skip `apt dist-upgrade` |
| `--disable-wifi` | Turn off Wi-Fi (only once the Spark is on Ethernet) |
| `--keep-bluetooth` | Leave Bluetooth on |
| `--allow-mdns CIDR` | Allow mDNS so NVIDIA Sync can discover the Spark by name |

## Roll back

```bash
sudo bash /var/backups/harden-spark/rollback.sh
```

The rollback restores the original copies of every file the script changed and
removes every file it created. Originals are saved once, so re-running the
script never overwrites them.
