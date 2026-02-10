#!/usr/bin/env bash
set -euo pipefail

# Crea un evento/reunión en Taskwarrior (proyecto: Reunion)

today_day=$(date +%d)
today_month=$(date +%m)
today_year=$(date +%Y)

read -r -p "Título/Descripción: " desc
if [[ -z "$desc" ]]; then
  echo "La descripción no puede estar vacía." >&2
  exit 1
fi

read -r -p "Día (por defecto ${today_day#0}): " day
read -r -p "Mes (por defecto ${today_month#0}): " month
read -r -p "Año (por defecto ${today_year}): " year
read -r -p "Proyecto (Enter para 'Reunion'): " project_input
read -r -p "Nota (opcional, Enter para omitir): " note_initial

day=${day:-$today_day}
month=${month:-$today_month}
year=${year:-$today_year}
project=${project_input:-Reunion}

if ! due_date=$(date -d "$year-$month-$day" +%Y-%m-%d 2>/dev/null); then
  echo "Fecha inválida: $day/$month/$year" >&2
  exit 1
fi

echo "Creando reunión..."
args=(add "due:$due_date" "+meeting" "+reu" "$desc")
if [[ -n "$project" ]]; then
  args+=("project:$project")
fi
create_out=$(task "${args[@]}" 2>&1 | sed '/^Configuration override/d')
echo "$create_out"

# Tomar ID recién creado
tid=$(printf '%s\n' "$create_out" | sed -n 's/^Created task \([0-9]\+\).*/\1/p' | tail -n1)
if [[ -z "$tid" ]]; then
  tid=$(task +LATEST rc.verbose=nothing rc.defaultwidth=0 _ids 2>/dev/null | head -n1 || true)
fi

if [[ -n "$tid" && -n "$note_initial" ]]; then
  task "$tid" annotate "$note_initial" 2>&1 | sed '/^Configuration override/d'
fi
