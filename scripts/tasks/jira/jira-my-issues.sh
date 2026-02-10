#!/usr/bin/env bash
set -euo pipefail

# Lista issues asignadas al usuario actual en Jira usando API token.
# Requiere variables: JIRA_HOST (https://tuinstancia.atlassian.net), JIRA_EMAIL, JIRA_API_TOKEN.
# Opcional: primer argumento o JIRA_JQL para sobreescribir el JQL; JIRA_MAX_RESULTS para tamaño de página (default 200).

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/jira.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

# Modo JSON (--json) o tabla (por defecto)
JSON_MODE=false
if [[ "${1:-}" == "--json" ]]; then
  JSON_MODE=true
  shift
fi

# JQL por defecto filtrando por accountId concreto (tu usuario).
DEFAULT_JQL="assignee = 6151afc272f6970069e80ae2 AND resolution = Unresolved ORDER BY updated DESC"
JQL_OVERRIDE="${1:-${JIRA_JQL:-}}"
JIRA_HOST=${JIRA_HOST:-}
JIRA_EMAIL=${JIRA_EMAIL:-}
JIRA_API_TOKEN=${JIRA_API_TOKEN:-}
JIRA_MAX_RESULTS=${JIRA_MAX_RESULTS:-200}

if [[ -z "$JIRA_HOST" || -z "$JIRA_EMAIL" || -z "$JIRA_API_TOKEN" ]]; then
  echo "Faltan variables: export JIRA_HOST, JIRA_EMAIL, JIRA_API_TOKEN" >&2
  exit 1
fi

JQL_TO_USE=${JQL_OVERRIDE:-$DEFAULT_JQL}

JIRA_HOST="$JIRA_HOST" JIRA_EMAIL="$JIRA_EMAIL" JIRA_API_TOKEN="$JIRA_API_TOKEN" \
JIRA_JQL="$JQL_TO_USE" JIRA_MAX_RESULTS="$JIRA_MAX_RESULTS" JSON_MODE="$JSON_MODE" python3 - <<'PY'
import base64, json, os, sys, urllib.parse, urllib.request

host = os.environ["JIRA_HOST"].rstrip("/")
email = os.environ["JIRA_EMAIL"]
token = XXXX"JIRA_API_TOKEN"]
jql = os.environ.get("JIRA_JQL") or ""
max_results = os.environ.get("JIRA_MAX_RESULTS") or "50"
json_mode = (os.environ.get("JSON_MODE") or "false").lower() == "true"

if not host.startswith("http://") and not host.startswith("https://"):
    host = "https://" + host

url = f"{host}/rest/api/3/search/jql"
page_size = int(max_results)

basic = base64.b64encode(f"{email}:{token}".encode()).decode()
headers = {
    "Authorization": f"Basic {basic}",
    "Accept": "application/json",
    "Content-Type": "application/json",
}

issues = []
next_token = None
all_labels = set()
while True:
    body = {
        "jql": jql,
        "fields": ["summary", "status", "updated", "project", "labels"],
        "maxResults": page_size,
    }
    if next_token:
        body["nextPageToken"] = next_token
    data_bytes = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read().decode()
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="ignore") if hasattr(e, "read") else ""
        sys.stderr.write(f"Jira devolvió {e.code}: {e.reason}\n{body}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Error al llamar a Jira: {e}\n")
        sys.exit(1)

    try:
        data = json.loads(raw)
    except Exception:
        sys.stderr.write("No se pudo parsear la respuesta JSON de Jira.\n")
        sys.exit(1)

    page_items = data.get("issues", [])
    issues.extend(page_items)
    for issue in page_items:
        fields = issue.get("fields") or {}
        for label in fields.get("labels") or []:
            if label:
                all_labels.add(label)
    next_token = data.get("nextPageToken")
    is_last = data.get("isLast", True)
    if not next_token or is_last:
        break

if json_mode:
    print(json.dumps({"issues": issues, "labels": sorted(all_labels, key=str.lower)}, ensure_ascii=False))
    sys.exit(0)

if not issues:
    print("(sin resultados)")
    sys.exit(0)

print(f"{'KEY':<12} {'STATUS':<20} {'LABELS':<25} SUMMARY")
print("-" * 12, "-" * 20, "-" * 25, "-" * 60)
for issue in issues:
    key = issue.get("key", "")
    fields = issue.get("fields", {})
    status = (fields.get("status", {}) or {}).get("name", "")
    summary = fields.get("summary", "")
    updated = fields.get("updated", "")
    labels = fields.get("labels") or []
    labels_join = ",".join(labels)
    labels_disp = labels_join if len(labels_join) <= 23 else labels_join[:22] + "…"
    status_disp = status[:18] + "…" if len(status) > 19 else status
    summary_disp = summary if len(summary) <= 100 else summary[:97] + "…"
    print(f"{key:<12} {status_disp:<20} {labels_disp:<25} {summary_disp} ({updated})")

if all_labels:
    labels_sorted = sorted(all_labels, key=str.lower)
    print("\nLabels únicos:")
    print(", ".join(labels_sorted))
PY
