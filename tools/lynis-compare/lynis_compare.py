#!/usr/bin/env python3
"""Compare two Lynis report files and summarize what hardening changed.

    python3 tools/lynis-compare/lynis_compare.py before.dat after.dat
    python3 tools/lynis-compare/lynis_compare.py before.dat after.dat --html report.html

Reads the key=value report.dat files Lynis writes with --report-file.
Standard library only, so it runs on a fresh DGX OS install.
"""
from __future__ import annotations

import argparse
import html
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Report:
    path: Path
    values: dict[str, str] = field(default_factory=dict)
    warnings: dict[str, str] = field(default_factory=dict)
    suggestions: dict[str, str] = field(default_factory=dict)

    @property
    def index(self) -> int:
        return int(self.values.get("hardening_index", "0") or 0)

    @property
    def tests(self) -> int:
        return int(self.values.get("lynis_tests_done", "0") or 0)


def parse(path: Path) -> Report:
    report = Report(path)
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        if key in ("warning[]", "suggestion[]"):
            parts = value.split("|")
            test_id, text = parts[0], (parts[1] if len(parts) > 1 else "")
            target = report.warnings if key == "warning[]" else report.suggestions
            target[f"{test_id}|{text}"] = f"{test_id}: {text}"
        else:
            report.values.setdefault(key, value)
    return report


def diff(before: dict[str, str], after: dict[str, str]) -> tuple[list[str], list[str], list[str]]:
    fixed = [before[k] for k in sorted(before.keys() - after.keys())]
    remaining = [after[k] for k in sorted(after.keys() & before.keys())]
    new = [after[k] for k in sorted(after.keys() - before.keys())]
    return fixed, remaining, new


def terminal_summary(b: Report, a: Report) -> str:
    bold, green, yellow, dim, reset = "\033[1m", "\033[32m", "\033[33m", "\033[2m", "\033[0m"
    if not sys.stdout.isatty():
        bold = green = yellow = dim = reset = ""
    wf, wr, wn = diff(b.warnings, a.warnings)
    sf, sr, sn = diff(b.suggestions, a.suggestions)
    delta = a.index - b.index
    lines = [
        f"{bold}Lynis before vs after{reset}",
        "",
        f"  Hardening index   {b.index:>3}  ->  {green}{bold}{a.index:>3}{reset}   ({'+' if delta >= 0 else ''}{delta})",
        f"  Warnings          {len(b.warnings):>3}  ->  {yellow}{len(a.warnings):>3}{reset}   fixed {len(wf)}, new {len(wn)}",
        f"  Suggestions       {len(b.suggestions):>3}  ->  {len(a.suggestions):>3}   fixed {len(sf)}, new {len(sn)}",
        f"  Tests performed   {b.tests:>3}  ->  {a.tests:>3}",
        "",
    ]
    if wr or wn:
        lines.append(f"{bold}Warnings still open{reset}")
        lines += [f"  {yellow}!{reset} {w}" for w in wr + wn]
        lines.append("")
    lines.append(f"{dim}Top remaining suggestions:{reset}")
    lines += [f"  - {s}" for s in (sr + sn)[:8]]
    return "\n".join(lines)


def html_report(b: Report, a: Report) -> str:
    wf, wr, wn = diff(b.warnings, a.warnings)
    sf, sr, sn = diff(b.suggestions, a.suggestions)
    esc = html.escape

    def items(rows: list[str], cls: str) -> str:
        if not rows:
            return '<p class="none">None</p>'
        return "<ul>" + "".join(f'<li class="{cls}">{esc(r)}</li>' for r in rows) + "</ul>"

    delta = a.index - b.index
    os_name = esc(a.values.get("os_fullname") or a.values.get("os_name", ""))
    version = esc(a.values.get("lynis_version", ""))
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>Lynis hardening report</title>
<style>
body{{margin:0;background:#fff;font-family:Inter,'DejaVu Sans',Arial,sans-serif;color:#1f2937}}
.card{{width:1040px;padding:32px 36px}}
h1{{font-size:26px;margin:0 0 4px}} .sub{{color:#6b7280;font-size:14px;margin-bottom:22px}}
.kpis{{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:26px}}
.kpi{{border:1px solid #e5e7eb;border-radius:10px;padding:16px 18px}}
.kpi .label{{font-size:13px;color:#6b7280;text-transform:uppercase;letter-spacing:.06em}}
.kpi .val{{font-size:30px;font-weight:700;margin-top:6px}} .kpi .from{{font-size:15px;color:#6b7280;font-weight:400}}
.up{{color:#4d7c0f}} .warn{{color:#b45309}}
h2{{font-size:17px;margin:22px 0 8px}} ul{{margin:0;padding-left:20px;font-size:14px;line-height:1.55}}
li.fixed{{color:#4d7c0f}} li.open{{color:#b45309}} li.sugg{{color:#374151}} .none{{color:#6b7280;font-size:14px;margin:0}}
.cols{{display:grid;grid-template-columns:1fr 1fr;gap:28px}}
.foot{{margin-top:22px;font-size:12px;color:#9ca3af;font-family:'DejaVu Sans Mono',monospace}}
</style></head><body><div class="card">
<h1>Hardening report: DGX Spark</h1>
<div class="sub">Lynis {version} &middot; {os_name} &middot; before vs after harden-spark.sh</div>
<div class="kpis">
 <div class="kpi"><div class="label">Hardening index</div><div class="val up">{a.index} <span class="from">from {b.index} ({'+' if delta >= 0 else ''}{delta})</span></div></div>
 <div class="kpi"><div class="label">Warnings</div><div class="val warn">{len(a.warnings)} <span class="from">from {len(b.warnings)}</span></div></div>
 <div class="kpi"><div class="label">Suggestions</div><div class="val">{len(a.suggestions)} <span class="from">from {len(b.suggestions)}</span></div></div>
</div>
<div class="cols"><div>
<h2>Warnings fixed ({len(wf)})</h2>{items(wf, "fixed")}
<h2>Warnings still open ({len(wr) + len(wn)})</h2>{items(wr + wn, "open")}
</div><div>
<h2>Suggestions resolved ({len(sf)})</h2>{items(sf[:14], "fixed")}
<h2>Top remaining suggestions</h2>{items((sr + sn)[:10], "sugg")}
</div></div>
<div class="foot">source: {esc(b.path.name)} vs {esc(a.path.name)} &middot; tests performed {b.tests} / {a.tests}</div>
</div></body></html>"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("before", type=Path)
    ap.add_argument("after", type=Path)
    ap.add_argument("--html", type=Path, help="also write a one-page HTML report")
    args = ap.parse_args()
    b, a = parse(args.before), parse(args.after)
    print(terminal_summary(b, a))
    if args.html:
        args.html.write_text(html_report(b, a), encoding="utf-8")
        print(f"\nHTML report: {args.html}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
