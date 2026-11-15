# The Private AI Security Lab

Companion repository for the Medium series **"The Private AI Security Lab: Building Secure AI
Cybersecurity Tools on NVIDIA DGX Spark."**

Every model runs on hardware you own. Nothing leaves the lab. Every tool is built, tested and
hardened like production software.

> **Authorized use only.** Everything in this repository is for defending systems you own or are
> explicitly authorized to assess. Scans and agents only run against the isolated lab range
> defined in `docs/scope.example.yaml`.

## Lab hardware

| Role | Hardware |
|------|----------|
| Inference node A | NVIDIA DGX Spark, 128 GB unified memory |
| Inference node B (Part 19+) | NVIDIA DGX Spark, 128 GB, linked over QSFP 200GbE |
| Control plane, SIEM, target range | Minisforum MS-A2, Ryzen 9 9955HX, 96 GB DDR5, 2 TB |

## Quick start

```bash
git clone https://github.com/viperpjd/private-ai-security-lab.git
cd private-ai-security-lab
make bootstrap   # creates .venv and installs the check tools
make check       # runs every security check CI runs
```

## Repository layout

| Path | Filled in by | Purpose |
|------|--------------|---------|
| `docs/` | Part 1 | Threat model, bill of materials, architecture, scope |
| `infra/` | Parts 2-4, 19, 22 | Host hardening, network, cluster setup |
| `compose/` | Parts 4-5, 7, 10-11, 20 | Docker Compose stacks |
| `models/` | Parts 5-6 | Model manifests with hashes and licenses |
| `evals/` | Part 6 | Security eval set and scoring harness |
| `tools/` | Parts 9-18 | Triage, intel, scan analysis, review, compliance |
| `agents/` | Part 23 | Supervised assessment agent and MCP tools |
| `lab-range/` | Part 14 | Isolated, intentionally vulnerable target range |
| `redteam/` | Part 24 | Tests that attack our own AI tools |

Each article has a git tag (`article-01` ... `article-25`) so you can check out the exact state.

## License

MIT. See `LICENSE`.
