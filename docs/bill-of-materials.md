# Bill of materials

Prices change often. Check current pricing before you buy.

| Item | Qty | Role in the lab | Notes |
|------|-----|-----------------|-------|
| NVIDIA DGX Spark, 128 GB unified memory | 2 | Inference nodes A and B | GB10 Grace Blackwell, ConnectX-7 with 2x QSFP, 10GbE RJ-45. The second unit joins in Part 19 |
| QSFP cable for ConnectX-7 (200GbE) | 1 | Direct Spark-to-Spark link | Short cable; the two units stack. No switch needed |
| Minisforum MS-A2 (Ryzen 9 9955HX, 96 GB DDR5, 2 TB) | 1 | Control plane, SIEM, target range | 2x 10GbE SFP+, 2x 2.5GbE RJ-45 |
| Managed switch with 802.1Q VLANs and 10G ports | 1 | Lab network segmentation | Needs a 10GBASE-T port or SFP+ module for each Spark's RJ-45 |
| SFP+ DAC cable or 10GBASE-T modules | 2-3 | MS-A2 and Spark uplinks | Match to your switch |
| UPS | 1 | Clean shutdown on power loss | Recommended |

## Software

| Component | Where | Part |
|-----------|-------|------|
| DGX OS (Ubuntu 24.04 based) | DGX Sparks | 2 |
| Ubuntu Server 24.04 LTS | MS-A2 | 3 |
| Docker Engine + NVIDIA Container Toolkit | All hosts | 4 |
| Ollama | DGX Sparks | 5 |
| vLLM | DGX Sparks (two-node) | 20 |
| Wazuh, then Elastic (one at a time) | MS-A2 | 10, 11 |
