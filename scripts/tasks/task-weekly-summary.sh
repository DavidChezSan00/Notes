#!/usr/bin/env bash
set -euo pipefail

# Reporte ondemand de tareas cerradas en los últimos N días (default: 7).
# Incluye estados completed y deleted porque en este entorno se usan borrados.

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
DAYS="${1:-7}"

json_out=$({ task "end.after:today-${DAYS}days" end.before:tomorrow \
  rc.verbose=nothing \
  rc.color=off \
  rc.hooks=off \
  rc.confirmation=off \
  rc.recurrence.confirmation=no \
  export 2>/dev/null || true; })

export SCRIPT_DIR JSON_OUT="$json_out" DAYS

python3 - <<'PY'
import json, os, sys
from datetime import datetime, timezone

raw = os.environ.get("JSON_OUT", "").strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

script_dir = os.environ.get("SCRIPT_DIR")
if script_dir:
    sys.path.insert(0, script_dir)
import common_task as ct  # type: ignore

def parse_date(val: str):
    for fmt in ("%Y%m%dT%H%M%SZ", "%Y-%m-%d", "%Y%m%d"):
        try:
            dt = datetime.strptime(val, fmt)
            if fmt == "%Y%m%dT%H%M%SZ":
                dt = dt.replace(tzinfo=timezone.utc).astimezone()
            return dt
        except Exception:
            continue
    return None

items = []
for t in data:
    end_raw = t.get("end") or ""
    end_dt = parse_date(end_raw)
    if not end_dt:
        continue
    desc = t.get("description") or ""
    proj_raw = t.get("project") or "Sin proyecto"
    status = (t.get("status") or "").lower()
    if status not in ("completed", "deleted"):
        continue
    tags_lower = [(tag or "").lower() for tag in (t.get("tags") or [])]
    suffix_parts = []
    if "reu" in tags_lower:
        suffix_parts.append("REUNIÓN")
    if status == "deleted":
        suffix_parts.append("deleted")
    suffix = " ".join(f"[{p}]" for p in suffix_parts)
    items.append((end_dt, proj_raw, desc, suffix))

if not items:
    print(f"No hay tareas cerradas en los últimos {os.environ.get('DAYS', '7')} días.")
    sys.exit(0)

items.sort(key=lambda x: x[0], reverse=True)

print(f"Tareas cerradas en los últimos {os.environ.get('DAYS', '7')} días:")
for end_dt, proj_raw, desc, suffix in items:
    proj_disp, desc_color = ct.project_display(proj_raw)
    when = end_dt.strftime("%Y-%m-%d %H:%M %Z")
    desc_disp = f"{desc_color}{desc}{ct.RESET}" if desc_color else desc
    if suffix:
        desc_disp = f"{desc_disp} {suffix}"
    proj_cell = ct.pad_ansi(proj_disp, 12)
    print(f"- {when} — {proj_cell} {desc_disp}")

# Totales por proyecto
counts = {}
for _, proj_raw, _, _ in items:
    counts[proj_raw] = counts.get(proj_raw, 0) + 1
print("\nTotales por proyecto:")
for proj in sorted(counts):
    proj_disp, _ = ct.project_display(proj)
    print(f"- {proj_disp}: {counts[proj]}")
PY
