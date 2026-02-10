#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
TAG_FILTER="${1:-}"

# Muestra tareas pendientes (Project + Description) sin anotaciones
# Se usa en ~/.bashrc para mostrar solo una vez al día

# Capturamos la salida de task en JSON; si falla, devolvemos vacío
json_out=$({ task status:pending \
  rc.verbose=nothing \
  rc.color=off \
  rc.hooks=off \
  rc.confirmation=off \
  rc.recurrence.confirmation=no \
  export 2>/dev/null || true; })

export SCRIPT_DIR JSON_OUT="$json_out" TAG_FILTER

python3 - <<'PY'
import sys, json, os, subprocess

raw = os.environ.get("JSON_OUT", "").strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

tag_filter = (os.environ.get("TAG_FILTER") or "").strip().lower().lstrip("+")
script_dir = os.environ.get("SCRIPT_DIR")
if script_dir:
    sys.path.insert(0, script_dir)
import common_task as ct  # type: ignore

# Deduplicate recurring tasks: keep the closest pending instance per parent
all_items = ct.dedupe_best(data)
# Separar reuniones marcadas con tag +reu para no listarlas en tabla principal ni resumen
meetings = [t for t in all_items if "reu" in [(tag or "").lower() for tag in (t.get("tags") or [])]]
items = [t for t in all_items if "reu" not in [(tag or "").lower() for tag in (t.get("tags") or [])]]
if tag_filter:
    items = [t for t in items if tag_filter in [(tag or "").lower() for tag in (t.get("tags") or [])]]
items = sorted(items, key=lambda t: ((t.get('project') or ''), (t.get('description') or ''), ct.sort_key(t)))
if not items and not meetings:
    sys.exit(0)

print(f"{'Project':<12} Description")
print("-" * 12, "-" * 60)
last_proj = None
counts = {}
for t in items:
    proj_raw = t.get('project') or ''
    desc = t.get('description') or ''
    annotations = t.get('annotations') or []
    tw_state = (t.get('tw_state') or '').lower()
    paused = tw_state == 'paused' or any('paused' in (a.get('description') or '').lower() for a in annotations)
    suffix = " [PAUSED]" if paused else ""

    proj_display, desc_color = ct.project_display(proj_raw)
    if last_proj is not None and proj_raw != last_proj:
        print()
    last_proj = proj_raw

    if paused:
        proj_display = f"{ct.ORANGE}{proj_raw}{ct.RESET}"
        desc_display = f"{ct.ORANGE}{desc}{suffix}{ct.RESET}"
    else:
        desc_display = f"{desc_color}{desc}{suffix}{ct.RESET}" if desc_color else f"{desc}{suffix}"

    proj_cell = ct.pad_ansi(proj_display, 12)
    print(f"{proj_cell} {desc_display}")

    proj_key = proj_raw or "Sin proyecto"
    counts[proj_key] = counts.get(proj_key, 0) + 1

if counts:
    parts = []
    # Totales históricos (hechas/creadas) por proyecto, basado en export
    def project_totals():
        try:
            raw_all = subprocess.check_output([
                "task",
                "rc.verbose=nothing",
                "rc.color=off",
                "rc.hooks=off",
                "rc.confirmation=off",
                "rc.recurrence.confirmation=no",
                "export",
            ], text=True)
        except Exception:
            return {}
        try:
            data_all = json.loads(raw_all)
        except Exception:
            return {}
        totals = {}
        done = {}
        seen_total = {}
        seen_done = {}
        for t in data_all:
            tags_lower = [(tag or "").lower() for tag in (t.get("tags") or [])]
            if "reu" in tags_lower:
                continue  # no meter reuniones en resumen
            status = (t.get("status") or "").lower()
            if status == "recurring":
                key = t.get("uuid")
            else:
                key = t.get("parent") or t.get("uuid")
            if not key:
                continue
            proj = t.get("project") or "Sin proyecto"
            proj_seen_total = seen_total.setdefault(proj, set())
            proj_seen_done = seen_done.setdefault(proj, set())
            if key not in proj_seen_total:
                totals[proj] = totals.get(proj, 0) + 1
                proj_seen_total.add(key)
            if status in ("completed", "deleted") and key not in proj_seen_done:
                done[proj] = done.get(proj, 0) + 1
                proj_seen_done.add(key)
        for base_proj in ["Windows"]:
            totals.setdefault(base_proj, 0)
            done.setdefault(base_proj, 0)
        return {k: (done.get(k, 0), v) for k, v in totals.items()}

    totals = project_totals()
    totals.pop("Reunion", None)  # no resumir reuniones
    for proj in sorted(totals or counts):
        proj_disp, _ = ct.project_display(proj)
        done, total = totals.get(proj, (0, counts.get(proj, 0)))
        parts.append(f"{proj_disp} {done}/{total} tareas")
    print("\n" + "    ".join(parts))

# Mostrar reuniones (proyecto Reunion) en formato compacto al final
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

today_iso = datetime.now().strftime("%Y-%m-%d")
if meetings:
    meetings = sorted(meetings, key=lambda t: t.get("due") or t.get("entry") or "")
    meetings_today = []
    for m in meetings:
        raw_due = m.get("due") or ""
        due_dt = parse_date(raw_due)
        if due_dt and due_dt.strftime("%Y-%m-%d") == today_iso:
            meetings_today.append((m.get("description") or "", due_dt.strftime("%d/%m/%Y")))
    if meetings_today:
        print("\nEventos:")
        for desc, due in meetings_today:
            print(f"  {desc} ({due})")
PY
