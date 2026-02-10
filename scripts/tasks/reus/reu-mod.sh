#!/usr/bin/env bash
set -euo pipefail

# Modifica una reunión (tareas con tag +reu). Permite cambiar descripción, fecha y proyecto.

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

read -r -p "ID de la reunión a modificar: " tid
if [[ -z "$tid" || ! "$tid" =~ ^[0-9]+$ ]]; then
  echo "ID inválido." >&2
  exit 1
fi

TASK_INFO=$(LIST_JSON="$list_json" TID="$tid" python3 - <<'PY'
import json, os, sys, datetime
raw = os.environ.get("LIST_JSON") or ""
tid_raw = os.environ.get("TID")
try:
    tid = int(tid_raw)
except Exception:
    sys.exit(2)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)
sel = None
for t in data:
    if t.get("id") == tid:
        sel = t
        break
if not sel:
    sys.exit(3)
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
dt = parse_dt(sel.get("due", "") or "")
iso_local = dt.strftime("%Y-%m-%d") if dt else ""
print(sel.get("description", ""))
print(sel.get("project", ""))
print(iso_local)
PY
)
status=$?
if [[ $status -eq 3 ]]; then
  echo "No se encontró la reunión con ID $tid." >&2
  exit 1
elif [[ $status -ne 0 ]]; then
  echo "No se pudo obtener la reunión $tid." >&2
  exit 1
fi

current_desc=$(printf '%s\n' "$TASK_INFO" | sed -n '1p')
current_proj=$(printf '%s\n' "$TASK_INFO" | sed -n '2p')
default_date=$(printf '%s\n' "$TASK_INFO" | sed -n '3p')

today_day=$(date +%d)
today_month=$(date +%m)
today_year=$(date +%Y)

if [[ -n "$default_date" ]]; then
  def_day=${default_date:8:2}
  def_month=${default_date:5:2}
  def_year=${default_date:0:4}
else
  def_day=$today_day
  def_month=$today_month
  def_year=$today_year
fi

echo "Descripción actual: ${current_desc:-<vacía>}"
read -r -p "Nueva descripción (Enter para dejar igual): " new_desc
echo "Proyecto actual: ${current_proj:-<ninguno>}"
read -r -p "Nuevo proyecto (Enter para dejar igual, '-' para quitar): " new_proj

printf "Fecha actual (por defecto %s/%s/%s)\n" "${def_day#0}" "${def_month#0}" "$def_year"
read -r -p "Día: " day
read -r -p "Mes: " month
read -r -p "Año: " year

day=${day:-$def_day}
month=${month:-$def_month}
year=${year:-$def_year}

if ! new_due=$(date -d "$year-$month-$day" +%Y-%m-%d 2>/dev/null); then
  echo "Fecha inválida: $day/$month/$year" >&2
  exit 1
fi

args=("$tid" modify)
if [[ -n "$new_desc" ]]; then
  args+=("$new_desc")
fi
args+=("due:$new_due" "+meeting" "+reu")
if [[ -n "$new_proj" ]]; then
  if [[ "$new_proj" == "-" ]]; then
    args+=("project:")
  else
    args+=("project:$new_proj")
  fi
else
  # mantener proyecto actual si existe
  if [[ -n "$current_proj" ]]; then
    args+=("project:$current_proj")
  fi
fi

echo "Aplicando cambios..."
task rc.confirmation=off rc.recurrence.confirmation=no rc.hooks=off rc.pager=cat "${args[@]}" 2>&1 | sed '/^Configuration override/d'
