# Threat model

Version 1 (Part 1). Revisited in Part 8 (guardrails) and Part 24 (red-teaming our own tools).

## What we protect

| Asset | Why it matters |
|-------|----------------|
| Security telemetry: logs, alerts, scan results | Reveals internal hosts, users and weaknesses |
| Prompts, model outputs and case notes | Contain the same sensitive data, summarized |
| Model weights and container images | Tampered weights or images compromise every tool |
| Credentials and API keys | Give access to the lab and to the SIEMs |
| The target range | Intentionally vulnerable, so it must stay contained |
| The DGX Sparks and MS-A2 | Expensive hardware and the root of trust for the lab |

## Trust boundaries

1. Analyst workstation to the MS-A2 control plane (TLS, authenticated)
2. Control plane to the DGX Spark inference nodes (TLS API, lab VLAN only)
3. Spark A to Spark B (dedicated QSFP link, unrouted)
4. Control plane to the target range (scoped, approved scans only)
5. The lab to the internet (no egress outside controlled update windows)

## Threats and mitigations

Mapped to the OWASP Top 10 for LLM Applications 2026 where they apply.

| ID | Threat | Category | Mitigation | Built in |
|----|--------|----------|------------|----------|
| T01 | Instructions hidden in logs, tickets or documents steer a model | LLM01 Prompt Injection | Treat content as data, guard model, tool allowlists | Parts 8, 24 |
| T02 | Sensitive data leaves the lab in prompts or outputs | LLM02 Sensitive Information Disclosure | No egress, redaction, audit log | Parts 3, 8 |
| T03 | An agent takes a destructive or out-of-scope action | LLM03 Excessive Agency | Command allowlists, sandboxing, human approval | Parts 18, 23 |
| T04 | Tampered model weights or container images | LLM04 Supply Chain | Trusted sources, recorded hashes, pinned digests | Parts 4, 5 |
| T05 | Poisoned threat-intel or RAG data | LLM05 Data and Model Poisoning | Source allowlist, provenance, signed feeds | Part 12 |
| T06 | Runaway requests exhaust GPU memory or time | LLM06 Unbounded Consumption | Rate limits, quotas, timeouts | Parts 5, 7 |
| T07 | Hallucinated findings drive a wrong decision | LLM07 Misinformation | Citations, evals, human review | Parts 6, 18 |
| T08 | Secrets or internal context exposed through prompts | LLM08 Hidden Context Exposure | No secrets in prompts, vault-backed credentials | Part 8 |
| T09 | Retrieval returns data the requester should not see | LLM09 Vector and Embedding Weaknesses | Per-collection access control | Part 12 |
| T10 | Generated scripts or JSON executed without checks | LLM10 Improper Output Handling | Schema validation, linting, review, approval | Parts 8, 9 |
| T11 | Inference endpoints exposed without authentication | Infrastructure | Localhost bind, TLS reverse proxy, API keys | Parts 5, 22 |
| T12 | A compromised range host reaches the lab | Infrastructure | Isolated VLAN, no routing, firewall | Parts 3, 14 |
| T13 | Scans reach systems outside the authorized scope | Legal and ethical | Signed scope file, target allowlist | Parts 14, 15 |
| T14 | Secrets committed to the repository | Repository | detect-secrets in pre-commit and CI | Part 1 |

## Out of scope for this lab

- Building malware, weaponized exploits or phishing content
- Testing any system not listed in a signed scope file
- Autonomous actions without human approval
