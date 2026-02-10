#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
SUGGEST_FILE="$SCRIPT_DIR/jira/label-suggestions.txt"

get_projects() {
  local projs
  projs=$(task _projects 2>/dev/null | sed '/^$/d') || projs=""
  # Asegurar que proyectos base aparecen aunque no tengan tareas activas
  for base in Windows Synology Network Ansible Chocolatey AWS; do
    if ! printf '%s\n' "$projs" | grep -qx "$base"; then
      projs=$(printf '%s\n%s' "$projs" "$base")
    fi
  done
  printf '%s\n' "$projs" | sed '/^$/d' | awk '!seen[$0]++'
}

show_projects() {
  echo "Proyectos activos:"
  proj_list=$(get_projects)
  PROJ_LIST="$proj_list" SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import os, sys
proj_raw = os.environ.get("PROJ_LIST", "")
items = [p.strip() for p in proj_raw.splitlines() if p.strip()]
seen = set()
unique = []
for p in items:
    if p not in seen:
        unique.append(p)
        seen.add(p)

script_dir = os.environ.get("SCRIPT_DIR")
if script_dir:
    sys.path.insert(0, script_dir)
import common_task as ct  # type: ignore

colored = []
for p in unique:
    disp, _ = ct.project_display(p)
    colored.append(disp or p)

if not colored:
    print("(ninguno)")
else:
    print("[ " + " | ".join(colored) + " ]")
PY
  echo
}

create_task() {
  local project_arg="${1:-}"
  read -r -p "Descripción de la tarea: " desc
  if [[ -z "$desc" ]]; then
    echo "La descripción no puede estar vacía." >&2
    exit 1
  fi
  read -r -p "Nota (opcional, Enter para omitir): " note_initial

  project=""
  if [[ -n "$project_arg" ]]; then
    project="$project_arg"
  else
    show_projects
    proj_list=$(get_projects)
    while true; do
      read -r -p "Proyecto (dejar vacío para ninguno): " project
      if [[ -z "$project" ]]; then
        break
      fi
      match_exact=""
      matches=()
      while IFS= read -r p; do
        if [[ "${p,,}" == "${project,,}" ]]; then
          match_exact="$p"
          break
        fi
        if [[ "${p,,}" == "${project,,}"* ]]; then
          matches+=("$p")
        fi
      done <<< "$proj_list"
      if [[ -n "$match_exact" ]]; then
        project="$match_exact"
        break
      fi
      if [[ ${#matches[@]} -eq 1 ]]; then
        project="${matches[0]}"
        echo "Autocompletado a: $project"
        break
      fi
      if [[ ${#matches[@]} -gt 1 ]]; then
        echo "Coincidencias: ${matches[*]}"
        continue
      fi
      echo "Proyecto no reconocido. Pulsa Enter para dejar vacío o prueba de nuevo."
    done
  fi

  # Construir comando task
  args=(add "$desc")
  if [[ -n "$project" ]]; then
    args+=("project:$project")
  fi

  echo "Creando tarea..."
  create_out=$(task "${args[@]}" 2>&1 | sed '/^Configuration override/d')
  echo "$create_out"

  # Generar sugerencias de labels en base al título
  mkdir -p "$(dirname "$SUGGEST_FILE")"
  DESC_TEXT="$desc" PROJECT_INPUT="$project" SUGGEST_FILE="$SUGGEST_FILE" python3 - <<'PY' || true
import os, datetime, re

desc = os.environ.get("DESC_TEXT", "")
proj = (os.environ.get("PROJECT_INPUT") or "").strip()
out_path = os.environ.get("SUGGEST_FILE")
if not out_path or not desc:
    raise SystemExit

lower = desc.lower()

patterns = {
    "Ansible": [r"\bansible\b", r"\bplaybook\b"],
    "Firewall": [r"\bfirewall\b", r"\bforti"],
    "FirewallCentennial": [r"\bcentennial\b"],
    "FirewallGraz": [r"\bgraz\b"],
    "FirewallMadrid": [r"\bmadrid\b"],
    "FirewallQuincy": [r"\bquincy\b"],
    "SSLVPN": [r"\bssl ?vpn\b"],
    "EMS": [r"\bems\b"],
    "FortiClient": [r"\bforti ?client\b"],
    "Windows": [r"\bwindows\b"],
    "Linux": [r"\blinux\b", r"\bulnix\b"],
    "MacOS": [r"\bmac ?os\b", r"\bmac\b"],
    "Python": [r"\bpython\b"],
    "Chocolatey": [r"\bchocolatey\b", r"\bchoco\b"],
    "Network": [r"\bnetwork\b", r"\bred\b", r"\bnetbox\b"],
    "Frontends": [r"\bfrontend(s)?\b"],
    "Users": [r"\buser\b", r"\busuario\b", r"\baccount\b"],
    "Switches": [r"\bswitch(es)?\b"],
    "Storage": [r"\bstorage\b", r"\bsynology\b", r"\bnas\b"],
    "Backup": [r"\bbackup\b"],
    "Certificate": [r"\bcertificate\b", r"\bcert\b", r"\bossl\b"],
    "RolesAnyWhere": [r"roles ?anywhere"],
}

suggested = []
# si hay proyecto, proponerlo como label base
if proj:
    suggested.append(proj)

for label, pats in patterns.items():
    if any(re.search(p, lower) for p in pats):
        suggested.append(label)

# si nada coincidió, proponer Misc como comodín
if not suggested:
    suggested.append("Misc")

timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
line = f"[{timestamp}] {desc} -> {', '.join(suggested)}\n"
try:
    with open(out_path, "a", encoding="utf-8") as fh:
        fh.write(line)
    print(f"Sugerencias de labels guardadas en {out_path}: {', '.join(suggested)}")
except PermissionError:
    print(f"No se pudieron guardar las sugerencias en {out_path} (permisos)")
PY

  # Si es recurrente, TW crea plantilla y ocurrencia; usamos la última creada (ocurrencia)
  tid=$(printf '%s\n' "$create_out" | sed -n 's/^Created task \\([0-9]\\+\\).*/\\1/p' | tail -n1)
  if [[ -z "$tid" ]]; then
    tid=$(task +LATEST rc.verbose=nothing rc.defaultwidth=0 _ids 2>/dev/null | head -n1 || true)
  fi
  if [[ -n "$tid" && -n "$note_initial" ]]; then
    task "$tid" annotate "$note_initial" 2>&1 | sed '/^Configuration override/d'
  fi
}

list_pending() {
  proj_filter="${1:-}"
  tag_filter="${2:-}"
  show_notes="${3:-yes}"
  json_out=$({ task status:pending \
    rc.verbose=nothing \
    rc.color=off \
    rc.hooks=off \
    rc.confirmation=off \
    rc.recurrence.confirmation=no \
    export 2>/dev/null || true; })
  SCRIPT_DIR="$SCRIPT_DIR" PROJ_FILTER="$proj_filter" TAG_FILTER="$tag_filter" SHOW_NOTES="$show_notes" JSON_OUT="$json_out" python3 - <<'PY'
import json, os, sys, shutil, textwrap, subprocess

raw = os.environ.get("JSON_OUT", "").strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

proj_filter = (os.environ.get("PROJ_FILTER") or "").strip().lower()
tag_filter = (os.environ.get("TAG_FILTER") or "").strip().lower().lstrip("+")
show_notes = (os.environ.get("SHOW_NOTES") or "yes").lower() != "no"
script_dir = os.environ.get("SCRIPT_DIR")
if script_dir:
    sys.path.insert(0, script_dir)
import common_task as ct  # type: ignore

items = ct.dedupe_best(data)
# Ocultar reuniones (+reu y proyecto Reunion) de los listados de tareas
items = [
    t for t in items
    if "reu" not in [(tag or "").lower() for tag in (t.get("tags") or [])]
    and (t.get("project") or "").strip().lower() != "reunion"
]
if not items:
    sys.exit(0)

if proj_filter:
    items = [t for t in items if (t.get("project") or "").strip().lower() == proj_filter]
if tag_filter:
    items = [
        t
        for t in items
        if tag_filter in [(tag or "").lower() for tag in (t.get("tags") or [])]
    ]
    if not items:
        sys.exit(0)

items = sorted(items, key=lambda t: (t.get("project") or "", ct.sort_key(t)))

cols = shutil.get_terminal_size(fallback=(120, 24)).columns
ID_WIDTH = 4
PROJECT_WIDTH = 12
STATE_WIDTH = 8
gap = "        "
desc_width = max(20, cols - (ID_WIDTH + 1 + PROJECT_WIDTH + 1 + len(gap) + STATE_WIDTH))

print(f"{'ID':>{ID_WIDTH}} {'Project':<{PROJECT_WIDTH}} {'Description':<{desc_width}}{gap}{'State':<{STATE_WIDTH}}")
print("-" * ID_WIDTH, "-" * PROJECT_WIDTH, "-" * desc_width, " " * len(gap), "-" * STATE_WIDTH)

for t in items:
    tid = t.get("id", "")
    proj_raw = t.get("project") or ""
    desc = t.get("description") or ""
    annotations = t.get("annotations") or []
    tw_state = (t.get("tw_state") or "").lower()
    paused = tw_state == "paused" or any("paused" in (a.get("description") or "").lower() for a in annotations)

    proj_display, desc_color = ct.project_display(proj_raw)

    state = (tw_state if tw_state else "open").upper()
    if tw_state == "paused":
        state_display = f"{ct.ORANGE}{state}{ct.RESET}"
    else:
        state_display = f"{ct.GREEN_STATE}{state}{ct.RESET}"

    suffix = " [PAUSED]" if paused else ""
    if paused:
        desc_display = f"{ct.ORANGE}{desc}{suffix}{ct.RESET}"
    else:
        desc_display = f"{desc_color}{desc}{suffix}{ct.RESET}" if desc_color else f"{desc}{suffix}"

    proj_cell = ct.pad_ansi(proj_display, PROJECT_WIDTH)
    desc_cell = ct.trim_pad_ansi(desc_display, desc_width)
    state_cell = ct.pad_ansi(state_display, STATE_WIDTH)
    print(f"{tid:>{ID_WIDTH}} {proj_cell} {desc_cell}{gap}{state_cell}")
    if show_notes:
        for ann in annotations:
            note = ann.get("description") or ""
            if not note:
                continue
            base_indent = " " * (ID_WIDTH + 1 + PROJECT_WIDTH + 1)
            prefix_first = "- "
            indent_first = base_indent + prefix_first
            indent_cont = base_indent + "  "
            wrap_width = max(20, desc_width - len(prefix_first))
            for i, line in enumerate(textwrap.wrap(note, width=wrap_width)):
                indent = indent_first if i == 0 else indent_cont
                print(f"{indent}{line}")

# Resumen por proyecto
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
        status = (t.get("status") or "").lower()
        if status == "recurring":
            key = t.get("uuid")
        else:
            key = t.get("parent") or t.get("uuid")
        if not key:
            continue
        proj = t.get("project") or "Sin proyecto"
        if str(proj).strip().lower() == "reunion":
            continue
        proj_seen_total = seen_total.setdefault(proj, set())
        proj_seen_done = seen_done.setdefault(proj, set())
        if key not in proj_seen_total:
            totals[proj] = totals.get(proj, 0) + 1
            proj_seen_total.add(key)
        if status in ("completed", "deleted") and key not in proj_seen_done:
            done[proj] = done.get(proj, 0) + 1
            proj_seen_done.add(key)
    # Baseline para proyectos fijos aunque estén en 0
    for base_proj in ["Windows"]:
        totals.setdefault(base_proj, 0)
        done.setdefault(base_proj, 0)
    return {k: (done.get(k, 0), v) for k, v in totals.items()}

totals = project_totals()
if totals:
    parts = []
    for proj in sorted(totals):
        proj_disp, _ = ct.project_display(proj)
        done, total = totals[proj]
        parts.append(f"{proj_disp} {done}/{total} tareas")
    print("\n" + "    ".join(parts))
PY
}

list_closed() {
  proj_filter="${1:-}"
  tag_filter="${2:-}"
  show_notes="${3:-yes}"
  json_out=$({ task status:completed or status:deleted \
    rc.verbose=nothing \
    rc.color=off \
    rc.hooks=off \
    rc.confirmation=off \
    rc.recurrence.confirmation=no \
    export 2>/dev/null || true; })
  SCRIPT_DIR="$SCRIPT_DIR" PROJ_FILTER="$proj_filter" TAG_FILTER="$tag_filter" SHOW_NOTES="$show_notes" JSON_OUT="$json_out" python3 - <<'PY'
import json, os, sys, shutil, textwrap

raw = os.environ.get("JSON_OUT", "").strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

proj_filter = (os.environ.get("PROJ_FILTER") or "").strip().lower()
tag_filter = (os.environ.get("TAG_FILTER") or "").strip().lower().lstrip("+")
show_notes = (os.environ.get("SHOW_NOTES") or "yes").lower() != "no"
script_dir = os.environ.get("SCRIPT_DIR")
if script_dir:
    sys.path.insert(0, script_dir)
import common_task as ct  # type: ignore

items = data
# Ocultar reuniones (+reu y proyecto Reunion) de los listados de tareas
items = [
    t for t in items
    if "reu" not in [(tag or "").lower() for tag in (t.get("tags") or [])]
    and (t.get("project") or "").strip().lower() != "reunion"
]
if not items:
    sys.exit(0)

if proj_filter:
    items = [t for t in items if (t.get("project") or "").strip().lower() == proj_filter]
if tag_filter:
    items = [
        t
        for t in items
        if tag_filter in [(tag or "").lower() for tag in (t.get("tags") or [])]
    ]
    if not items:
        sys.exit(0)

def _end_key(t):
    return t.get("end") or t.get("modified") or t.get("entry") or ""

items = sorted(items, key=lambda t: _end_key(t))

cols = shutil.get_terminal_size(fallback=(120, 24)).columns
ID_WIDTH = 4
PROJECT_WIDTH = 12
STATE_WIDTH = 10
gap = "        "
desc_width = max(20, cols - (ID_WIDTH + 1 + PROJECT_WIDTH + 1 + len(gap) + STATE_WIDTH))

print(f"{'ID':>{ID_WIDTH}} {'Project':<{PROJECT_WIDTH}} {'Description':<{desc_width}}{gap}{'State':<{STATE_WIDTH}}")
print("-" * ID_WIDTH, "-" * PROJECT_WIDTH, "-" * desc_width, " " * len(gap), "-" * STATE_WIDTH)

for t in items:
    tid = t.get("id", "")
    proj_raw = t.get("project") or ""
    desc = t.get("description") or ""
    annotations = t.get("annotations") or []
    status = (t.get("status") or "").lower()

    proj_display, desc_color = ct.project_display(proj_raw)

    if status == "completed":
        state_display = f"{ct.GREEN_STATE}COMPLETED{ct.RESET}"
    elif status == "deleted":
        state_display = f"{ct.ORANGE}DELETED{ct.RESET}"
    else:
        state_display = f"{ct.GREEN_STATE}{status.upper()}{ct.RESET}" if status else ""

    desc_display = f"{desc_color}{desc}{ct.RESET}" if desc_color else desc

    proj_cell = ct.pad_ansi(proj_display, PROJECT_WIDTH)
    desc_cell = ct.trim_pad_ansi(desc_display, desc_width)
    state_cell = ct.pad_ansi(state_display, STATE_WIDTH)
    print(f"{tid:>{ID_WIDTH}} {proj_cell} {desc_cell}{gap}{state_cell}")
    if show_notes:
        for ann in annotations:
            note = ann.get("description") or ""
            if not note:
                continue
            base_indent = " " * (ID_WIDTH + 1 + PROJECT_WIDTH + 1)
            prefix_first = "- "
            indent_first = base_indent + prefix_first
            indent_cont = base_indent + "  "
            wrap_width = max(20, desc_width - len(prefix_first))
            for i, line in enumerate(textwrap.wrap(note, width=wrap_width)):
                indent = indent_first if i == 0 else indent_cont
                print(f"{indent}{line}")
PY
}

delete_task() {
  echo "Tareas activas:"
  list_pending "" "" no || true
  echo
  read -r -p "ID de la tarea a borrar: " tid
  if [[ -z "$tid" || ! "$tid" =~ ^[0-9]+$ ]]; then
    echo "ID inválido." >&2
    exit 1
  fi

  task_json=$(task rc.verbose=nothing rc.hooks=off rc.confirmation=off rc.recurrence.confirmation=no rc.pager=cat "$tid" export 2>/dev/null || true)
  if [[ -z "$task_json" || "$task_json" == "[]" ]]; then
    echo "No se encontró la tarea $tid." >&2
    exit 1
  fi

  parent_uuid=$(TASK_JSON="$task_json" python3 - <<'PY' || true
import json, os
raw = os.environ.get("TASK_JSON", "")
try:
    data = json.loads(raw)
    task = data[0] if isinstance(data, list) and data else {}
except Exception:
    task = {}
print(task.get("parent", "") or "")
PY
)

  if [[ -n "$parent_uuid" ]]; then
    echo "Tarea recurrente detectada; eliminando plantilla y todas las ocurrencias..."
    task rc.confirmation=off rc.bulk=0 rc.recurrence.confirmation=no rc.hooks=off rc.pager=cat status:pending "parent:$parent_uuid" delete 2>&1 | sed '/^Configuration override/d' || true
    task rc.confirmation=off rc.bulk=0 rc.recurrence.confirmation=no rc.hooks=off rc.pager=cat status:waiting "parent:$parent_uuid" delete 2>&1 | sed '/^Configuration override/d' || true
    task rc.confirmation=off rc.bulk=0 rc.recurrence.confirmation=no rc.hooks=off rc.pager=cat "$parent_uuid" delete 2>&1 | sed '/^Configuration override/d' || true
  else
    echo "Borrando tarea $tid..."
    task rc.confirmation=off rc.bulk=0 rc.recurrence.confirmation=no rc.hooks=off rc.pager=cat "$tid" delete 2>&1 | sed '/^Configuration override/d'
  fi
}

modify_task() {
  echo "Tareas activas:"
  list_pending "" "" no || true
  echo
  read -r -p "ID de la tarea a modificar: " tid
  if [[ -z "$tid" || ! "$tid" =~ ^[0-9]+$ ]]; then
    echo "ID inválido." >&2
    exit 1
  fi

  read -r -p "Nueva descripción (Enter para dejar igual): " new_desc
  read -r -p "Nuevo proyecto (Enter para dejar igual, '-' para quitar): " new_proj
  read -r -p "Nuevo estado (open/paused, Enter para dejar igual, '-' para quitar): " new_state
  read -r -p "Añadir nota (Enter para omitir): " note_add
  read -r -p "Quitar notas que contengan (patrón, Enter para omitir): " note_del

  args=("$tid" modify)

  if [[ -n "$new_desc" ]]; then
    args+=("$new_desc")
  fi
  if [[ -n "$new_proj" ]]; then
    if [[ "$new_proj" == "-" ]]; then
      args+=("project:")
    else
      args+=("project:$new_proj")
    fi
  fi
  if [[ -n "$new_state" ]]; then
    if [[ "$new_state" == "-" ]]; then
      args+=("tw_state:")
    elif [[ "$new_state" == "open" || "$new_state" == "paused" ]]; then
      args+=("tw_state:$new_state")
    else
      echo "Estado inválido (solo open|paused)." >&2
      exit 1
    fi
  fi

  changed=false

  if [[ ${#args[@]} -gt 2 ]]; then
    echo "Aplicando cambios..."
    task rc.confirmation=off rc.recurrence.confirmation=no rc.pager=cat "${args[@]}" 2>&1 | sed '/^Configuration override/d'
    changed=true
  fi

  if [[ -n "$note_add" ]]; then
    task rc.confirmation=off rc.recurrence.confirmation=no rc.pager=cat "$tid" annotate "$note_add" 2>&1 | sed '/^Configuration override/d'
    changed=true
  fi

  if [[ -n "$note_del" ]]; then
    task rc.confirmation=off rc.recurrence.confirmation=no rc.pager=cat "$tid" denotate "$note_del" 2>&1 | sed '/^Configuration override/d'
    changed=true
  fi

  if [[ "$changed" = false ]]; then
    echo "No se especificaron cambios." >&2
  fi
}

case "${1:-}" in
  create)
    create_task "${2:-}"
    ;;
  list)
    proj_arg=""
    tag_arg=""
    if [[ "${2:-}" == +* ]]; then
      tag_arg="${2#+}"
    elif [[ -n "${2:-}" ]]; then
      proj_arg="${2:-}"
    fi
    if [[ "${3:-}" == +* ]]; then
      tag_arg="${3#+}"
    fi
    if [[ -z "$proj_arg" && -z "$tag_arg" ]]; then
      list_pending "" "" no
    else
      list_pending "$proj_arg" "$tag_arg" yes
    fi
    ;;
  closed)
    proj_arg=""
    tag_arg=""
    if [[ "${2:-}" == +* ]]; then
      tag_arg="${2#+}"
    elif [[ -n "${2:-}" ]]; then
      proj_arg="${2:-}"
    fi
    if [[ "${3:-}" == +* ]]; then
      tag_arg="${3#+}"
    fi
    if [[ -z "$proj_arg" && -z "$tag_arg" ]]; then
      list_closed "" "" no
    else
      list_closed "$proj_arg" "$tag_arg" yes
    fi
    ;;
  delete)
    delete_task
    ;;
  modify)
    modify_task
    ;;
  *)
    echo "Uso: $0 {create|list|closed|delete|modify} [project]" >&2
    exit 1
    ;;
esac
