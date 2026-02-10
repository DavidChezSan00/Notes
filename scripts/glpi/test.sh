#!/bin/bash

API_URL="http://vx-qy-cmdb-01.vdp-prod.local/apirest.php"
APP_TOKEN="stO0amtDq3YzNMQ4g52BrhAUMeoZEPIOm1s9sKOK"
LOGIN="viewer"
PASSWORD="Glpi@viewer1"

# Obtener session token
SESSION_TOKEN=$(curl -s -X GET "$API_URL/initSession?login=$LOGIN&password=XXXX" \
  -H "App-Token: XXXX" | jq -r .session_token)

if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" == "null" ]; then
  echo "Error: No se pudo obtener el Session Token"
  exit 1
fi

curl -s -X GET "$API_URL/Computer?expand_dropdowns=true&range=0-999" \
  -H "Content-Type: application/json" \
  -H "Session-Token: XXXX" \
  -H "App-Token: XXXX" \
  | jq --arg name "qy-ortho-222" '.[] | select(.name | ascii_downcase | contains($name | ascii_downcase))'

