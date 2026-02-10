#!/bin/bash

glpi() {
  local hostname="$1"
  local API_URL="https://qy-cmdb-001.vdp-prod.local/apirest.php"
  local APP_TOKEN="stO0amtDq3YzNMQ4g52BrhAUMeoZEPIOm1s9sKOK"
  local LOGIN="viewer"
  local PASSWORD="Glpi@viewer1"

  local PAGE_SIZE=500

  # Obtener session token
  local SESSION_TOKEN
  SESSION_TOKEN=$(curl -k -s -X GET "$API_URL/initSession?login=$LOGIN&password=XXXX" \
    -H "App-Token: XXXX" | jq -r .session_token)

  if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" == "null" ]; then
    echo "❌ Error: No se pudo obtener el Session Token"
    return 1
  fi

  api_get() {
    local endpoint="$1"
    curl -k -s -X GET "$API_URL/$endpoint" \
      -H "Content-Type: application/json" \
      -H "Session-Token: XXXX" \
      -H "App-Token: XXXX"
  }

  # Obtener ID del equipo mediante paginación
  local computer_id=""
  local start=0

  while true; do
    local end=$((start + PAGE_SIZE - 1))
    local response
    response=$(api_get "Computer?range=$start-$end")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
      break
    fi

    computer_id=$(echo "$response" | jq --arg hostname "$hostname" -r '
      .[] | select(.name == $hostname) | .id
    ' | head -n1)

    if [ -n "$computer_id" ]; then
      break
    fi

    local count
    count=$(echo "$response" | jq 'length')
    if [ "$count" -lt "$PAGE_SIZE" ]; then
      break
    fi

    start=$((end + 1))
  done

  if [ -z "$computer_id" ]; then
    echo "⚠️  No se encontró equipo con nombre \"$hostname\""
    return 0
  fi

  echo "🖥️  Hostname: $hostname"

  # Obtener racks_id y posición desde Item_Rack (paginando)
  local rack_data=""
  start=0

  while true; do
    local end=$((start + PAGE_SIZE - 1))
    local response
    response=$(api_get "Item_Rack?range=$start-$end")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
      break
    fi

    rack_data=$(echo "$response" | jq --arg id "$computer_id" -r '
      .[] | select(.items_id == ($id | tonumber)) | "\(.racks_id)|\(.position)"
    ' | head -n1)

    if [ -n "$rack_data" ]; then
      break
    fi

    local count
    count=$(echo "$response" | jq 'length')
    if [ "$count" -lt "$PAGE_SIZE" ]; then
      break
    fi

    start=$((end + 1))
  done

  if [ -z "$rack_data" ]; then
    echo "⚠️  No se encontró ubicación en rack para el item \"$hostname\""
    return 0
  fi

  # Extraer ID y posición
  local rack_id=$(echo "$rack_data" | cut -d'|' -f1)
  local position=$(echo "$rack_data" | cut -d'|' -f2)

  # Obtener nombre del rack por ID
  local rack_name
  rack_name=$(curl -k -s -X GET "$API_URL/Rack/$rack_id" \
    -H "Content-Type: application/json" \
    -H "Session-Token: XXXX" \
    -H "App-Token: XXXX" | jq -r '.name')

  echo "🏷️  Rack: $rack_name"
  echo "📍 Posición: $position"
  echo
}

# Ejecutar si se pasa argumento
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [ -n "$1" ]; then
    glpi "$1"
  else
    echo "Uso: $0 <hostname>"
    exit 1
  fi
fi
