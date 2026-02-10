#!/usr/bin/env bash
set -euo pipefail

# Lista reuniones (tareas con tag +reu), opcional filtro por proyecto.

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
proj_filter="${1:-}"

json_out=$({ task status:pending +reu \
  rc.verbose=nothing \
  rc.color=off \
  rc.hooks=off \
  rc.confirmation=off \
  rc.recurrence.confirmation=no \
  export 2>/dev/null || true; })

SCRIPT_DIR="$SCRIPT_DIR" PARENT_DIR="$PARENT_DIR" JSON_OUT="$json_out" PROJ_FILTER="$proj_filter" python3 - <<'PY'
import json, os, sys, shutil, textwrap

from datetime import datetime, timezone

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

def fmt_due(val: str) -> str:
    dt = parse_date(val)
    return dt.strftime("%d/%m/%Y") if dt else (val or "")

raw = os.environ.get("JSON_OUT", "").strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

proj_filter = (os.environ.get("PROJ_FILTER") or "").strip().lower()
script_dir = os.environ.get("SCRIPT_DIR")
parent_dir = os.environ.get("PARENT_DIR")
if parent_dir:
    sys.path.insert(0, parent_dir)
if script_dir:
    sys.path.insert(0, script_dir)
import common_task as ct  # type: ignore

items = ct.dedupe_best(data)
# already filtered by +reu in task query; keep only those with tag reu for safety
items = [t for t in items if "reu" in [(tag or "").lower() for tag in (t.get("tags") or [])]]
if proj_filter:
    items = [t for t in items if (t.get("project") or "").strip().lower() == proj_filter]
if not items:
    sys.exit(0)

items = sorted(items, key=lambda t: (t.get("due") or t.get("entry") or "", ct.sort_key(t)))

cols = shutil.get_terminal_size(fallback=(120, 24)).columns
DATE_WIDTH = 12
PROJECT_WIDTH = 12
gap = "    "
desc_width = max(20, cols - (DATE_WIDTH + 1 + PROJECT_WIDTH + 1 + len(gap)))

print(f"{'Date':<{DATE_WIDTH}} {'Project':<{PROJECT_WIDTH}} {'Description':<{desc_width}}")
print("-" * DATE_WIDTH, "-" * PROJECT_WIDTH, "-" * desc_width)

for t in items:
    proj_raw = t.get("project") or ""
    desc = t.get("description") or ""
    annotations = t.get("annotations") or []

    proj_display, desc_color = ct.project_display(proj_raw)
    due_display = fmt_due(t.get("due") or "")

    desc_display = f"{desc_color}{desc}{ct.RESET}" if desc_color else desc
    proj_cell = ct.pad_ansi(proj_display, PROJECT_WIDTH)
    desc_cell = ct.trim_pad_ansi(desc_display, desc_width)
    date_cell = ct.pad_ansi(due_display, DATE_WIDTH)
    print(f"{date_cell} {proj_cell} {desc_cell}")

    for ann in annotations:
        note = ann.get("description") or ""
        if not note:
            continue
        base_indent = " " * (DATE_WIDTH + 1 + PROJECT_WIDTH + 1)
        prefix_first = "- "
        indent_first = base_indent + prefix_first
        indent_cont = base_indent + "  "
        wrap_width = max(20, desc_width - len(prefix_first))
        for i, line in enumerate(textwrap.wrap(note, width=wrap_width)):
            indent = indent_first if i == 0 else indent_cont
            print(f"{indent}{line}")
PY
