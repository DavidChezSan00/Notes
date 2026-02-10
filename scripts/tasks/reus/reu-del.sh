#!/usr/bin/env bash
set -euo pipefail

# Borra una reunión (tareas con tag +reu).

PARENT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"

list_json=$({ task +reu status:pending \
  rc.verbose=nothing rc.color=off rc.hooks=off rc.confirmation=off \
  rc.recurrence.confirmation=no export 2>/dev/null || true; })

if [[ -z "${list_json//[$'\n\r ']/}" || "$list_json" == "[]" ]]; then
  echo "No hay reuniones pendientes."
  exit 0
fi

LIST_JSON="$list_json" PARENT_DIR="$PARENT_DIR" python3 - <<'PY' || exit 1
import json, os, sys, datetime
raw = os.environ.get("LIST_JSON") or ""
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

parent_dir = os.environ.get("PARENT_DIR")
if parent_dir:
    sys.path.insert(0, parent_dir)
import common_task as ct  # type: ignore

def parse_dt(val):
    for fmt in ("%Y%m%dT%H%M%SZ", "%Y-%m-%d", "%Y%m%d"):
        try:
            dt = datetime.datetime.strptime(val, fmt)
            if fmt == "%Y%m%dT%H%M%SZ":
                dt = dt.replace(tzinfo=datetime.timezone.utc).astimezone()
            return dt
        except Exception:
            continue
    return None

def fmt_due(val):
    dt = parse_dt(val)
    return dt.strftime("%d/%m/%Y") if dt else (val or "")

items = sorted(data, key=lambda t: (t.get("due") or t.get("entry") or ""))
print("Reuniones pendientes:")
for t in items:
    tid = t.get("id", "")
    desc = t.get("description") or ""
    due = fmt_due(t.get("due") or "")
    proj_raw = t.get("project") or ""
    proj_disp, desc_color = ct.project_display(proj_raw)
    desc_disp = f"{desc_color}{desc}{ct.RESET}" if desc_color else desc
    suffix = f" ({due})" if due else ""
    print(f"  {tid}: {proj_disp} - {desc_disp}{suffix}")
PY

read -r -p "ID de la reunión a borrar: " tid
if [[ -z "$tid" || ! "$tid" =~ ^[0-9]+$ ]]; then
  echo "ID inválido." >&2
  exit 1
fi

echo "Borrando reunión $tid..."
task rc.confirmation=off rc.recurrence.confirmation=no rc.hooks=off rc.pager=cat "$tid" delete 2>&1 | sed '/^Configuration override/d'
