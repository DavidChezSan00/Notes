#!/usr/bin/env bash
set -euo pipefail

# Compara tareas en Taskwarrior (pendientes) con las asignadas en Jira.
# Muestra las tareas locales que no tienen match en Jira y sugiere labels.
# Pensado para correr en el reporte de los viernes a las 10:00.

SCRIPT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/jira/jira.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

JIRA_HOST=${JIRA_HOST:-}
JIRA_EMAIL=${JIRA_EMAIL:-}
JIRA_API_TOKEN=${JIRA_API_TOKEN:-}
JIRA_PAGE_SIZE=${JIRA_MAX_RESULTS:-200}
MATCH_THRESHOLD=${JIRA_MATCH_THRESHOLD:-0.65}

if [[ -z "$JIRA_HOST" || -z "$JIRA_EMAIL" || -z "$JIRA_API_TOKEN" ]]; then
  echo "Faltan variables: export JIRA_HOST, JIRA_EMAIL, JIRA_API_TOKEN" >&2
  exit 1
fi

# Export de Taskwarrior pendiente
TW_JSON=$({ task status:pending rc.verbose=nothing rc.color=off rc.hooks=off rc.confirmation=off rc.recurrence.confirmation=no export 2>/dev/null || true; })
TW_CLOSED_JSON=$({ task end.after:today-7days end.before:tomorrow status:completed,deleted rc.verbose=nothing rc.color=off rc.hooks=off rc.confirmation=off rc.recurrence.confirmation=no export 2>/dev/null || true; })

JIRA_HOST="$JIRA_HOST" JIRA_EMAIL="$JIRA_EMAIL" JIRA_API_TOKEN="$JIRA_API_TOKEN" \
JIRA_PAGE_SIZE="$JIRA_PAGE_SIZE" MATCH_THRESHOLD="$MATCH_THRESHOLD" SCRIPT_DIR="$SCRIPT_DIR" TW_JSON="$TW_JSON" TW_CLOSED_JSON="$TW_CLOSED_JSON" python3 - <<'PY'
import base64, json, os, re, sys, unicodedata, urllib.request
from difflib import SequenceMatcher

script_dir = os.environ.get("SCRIPT_DIR")
if script_dir:
    sys.path.insert(0, script_dir)
try:
    import common_task as ct  # type: ignore
except Exception:
    ct = None

def normalize(text: str) -> str:
    text_nfkd = unicodedata.normalize("NFKD", text)
    text_ascii = "".join(c for c in text_nfkd if not unicodedata.combining(c))
    text_clean = re.sub(r"[^a-zA-Z0-9]+", " ", text_ascii).lower()
    return " ".join(text_clean.split())

def translate_spanish_to_en(text: str) -> str:
    mapping = {
        "crear": "create",
        "crea": "create",
        "creacion": "create",
        "configurar": "configure",
        "configura": "configure",
        "configuracion": "configure",
        "problema": "issue",
        "problemas": "issues",
        "issue": "issue",
        "limitacion": "limitation",
        "limite": "limit",
        "usuario": "user",
        "usuarios": "users",
        "account": "account",
        "frontend": "frontend",
        "frontends": "frontends",
        "backend": "backend",
        "servidor": "server",
        "servidores": "servers",
        "tarea": "task",
        "nota": "note",
        "script": "script",
        "windows": "windows",
        "linux": "linux",
        "mac": "mac",
        "macos": "macos",
        "certificado": "certificate",
        "cert": "certificate",
        "firewall": "firewall",
        "switch": "switch",
        "switches": "switches",
        "backup": "backup",
        "respaldar": "backup",
        "actualizar": "update",
        "instalar": "install",
        "paquete": "package",
        "chocolatey": "chocolatey",
        "python": "python",
        "dns": "dns",
        "correo": "email",
        "reunion": "meeting",
        "reuniones": "meetings",
        "probar": "test",
        "prueba": "test",
        "investigar": "research",
        "documentarse": "research",
        "estudiar": "research",
        "seguridad": "security",
        "almacenamiento": "storage",
        "sinologia": "synology",
        "synology": "synology",
        "lan": "lan",
        "lag": "lag",
        "automatico": "automatic",
        "automatica": "automatic",
        "automaticamente": "automatic",
        "automatizar": "automate",
    }
    stopwords = {
        "el",
        "la",
        "los",
        "las",
        "de",
        "del",
        "para",
        "por",
        "un",
        "una",
        "en",
        "y",
        "con",
        "al",
        "lo",
        "que",
        "se",
    }
    words = re.findall(r"[\w']+", text.lower())
    translated = []
    for w in words:
        if w in stopwords:
            continue
        translated.append(mapping.get(w, w))
    return " ".join(translated)

def similarity(a: str, b: str) -> float:
    seq = SequenceMatcher(None, a, b).ratio()
    set_a = set(a.split())
    set_b = set(b.split())
    token_score = 0.0
    if set_a and set_b:
        token_score = len(set_a & set_b) / float(max(len(set_a), len(set_b)))
    return max(seq, token_score)

SINGULAR_MAP = {
    "switches": "switch",
    "frontends": "frontend",
    "backups": "backup",
    "tasks": "task",
    "certificates": "certificate",
    "users": "user",
}

def canonical_tokens(text: str) -> list[str]:
    stop = {"the", "and", "with", "in", "to", "of", "for", "a", "an", "on"}
    toks = []
    for t in text.split():
        if not t or t in stop:
            continue
        t = SINGULAR_MAP.get(t, t.rstrip("s")) if len(t) > 3 else t
        toks.append(t)
    return toks

def suggest_labels(desc: str, project: str) -> list[str]:
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
        "Linux": [r"\blinux\b"],
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
    suggested: list[str] = []
    if project:
        suggested.append(project)
    for label, pats in patterns.items():
        if any(re.search(p, lower) for p in pats):
            suggested.append(label)
    if not suggested:
        suggested.append("Misc")
    seen = set()
    unique: list[str] = []
    for l in suggested:
        if l not in seen:
            unique.append(l)
            seen.add(l)
    return unique

# Parse Taskwarrior
raw_tw = os.environ.get("TW_JSON", "").strip()
if raw_tw:
    try:
        data_tw = json.loads(raw_tw)
    except Exception:
        data_tw = []
else:
    data_tw = []
if ct:
    data_tw = ct.dedupe_best(data_tw)
tw_tasks = [t for t in data_tw if "reu" not in [(tag or "").lower() for tag in (t.get("tags") or [])]]
raw_tw_closed = os.environ.get("TW_CLOSED_JSON", "").strip()
if raw_tw_closed:
    try:
        data_tw_closed = json.loads(raw_tw_closed)
    except Exception:
        data_tw_closed = []
else:
    data_tw_closed = []

# Fetch Jira issues with pagination
def fetch_jira():
    host = os.environ["JIRA_HOST"].rstrip("/")
    email = os.environ["JIRA_EMAIL"]
    token = XXXX"JIRA_API_TOKEN"]
    page_size = int(os.environ.get("JIRA_PAGE_SIZE", "200") or "200")
    jql = "assignee = currentUser() order by updated desc"

    url = f"{host}/rest/api/3/search/jql"
    basic = base64.b64encode(f"{email}:{token}".encode()).decode()
    headers = {
        "Authorization": f"Basic {basic}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    issues = []
    next_token = None
    while True:
        body = {
            "jql": jql,
            "fields": ["summary", "status", "labels"],
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
        data = json.loads(raw)
        issues.extend(data.get("issues", []))
        next_token = data.get("nextPageToken")
        if not next_token or data.get("isLast", True):
            break
    return issues

jira_issues = fetch_jira()
jira_labels = set()
for iss in jira_issues:
    summary = (iss.get("fields") or {}).get("summary", "")
    labels_issue = (iss.get("fields") or {}).get("labels") or []
    for l in labels_issue:
        if l:
            jira_labels.add(l)
    iss["_norm"] = normalize(summary)
for iss in jira_issues:
    summary = (iss.get("fields") or {}).get("summary", "")
    iss["_norm"] = normalize(summary)

threshold = float(os.environ.get("MATCH_THRESHOLD", "0.65"))
missing = []

for t in tw_tasks:
    desc = t.get("description") or ""
    project = t.get("project") or ""
    translated = translate_spanish_to_en(desc)
    norm_desc = normalize(translated or desc)
    best_ratio = 0.0
    best_overlap = 0
    best_issue = None
    for iss in jira_issues:
        norm_issue = iss.get("_norm", "")
        ratio = similarity(norm_desc, norm_issue)
        overlap = len(set(canonical_tokens(norm_desc)) & set(canonical_tokens(norm_issue)))
        if ratio > best_ratio or (abs(ratio - best_ratio) < 1e-6 and overlap > best_overlap):
            best_ratio = ratio
            best_issue = iss
            best_overlap = overlap
    match_hard = best_ratio >= threshold
    match_overlap = best_overlap >= 2 and best_ratio >= (threshold - 0.1)
    if match_hard or match_overlap:
        continue
    labels_base = suggest_labels(translated or desc, project)
    if jira_labels:
        labels = [l for l in labels_base if l in jira_labels] or labels_base
    else:
        labels = labels_base
    notes = []
    for ann in t.get("annotations") or []:
        note_raw = ann.get("description") or ""
        if note_raw:
            notes.append(translate_spanish_to_en(note_raw))
    missing.append({
        "tw_desc": desc,
        "suggested_summary": translated or desc,
        "labels": labels,
        "notes": notes,
        "best_ratio": best_ratio,
        "best_issue_key": best_issue.get("key") if best_issue else "",
    })

if not missing:
    print("Todas las tareas locales tienen match en Jira (>= umbral).")
else:
    print("Tareas en Taskwarrior sin match en Jira (sugerencias para crear):")
    for item in missing:
        print(f"- TW: {item['tw_desc']}")
        print(f"  Propuesta summary EN: {item['suggested_summary']}")
        if item["notes"]:
            print(f"  Notas EN: {' | '.join(item['notes'])}")
        print(f"  Labels sugeridas: {', '.join(item['labels'])}")
        if item["best_issue_key"]:
            print(f"  Mejor match Jira (score {item['best_ratio']:.2f}): {item['best_issue_key']}")
        else:
            print(f"  Mejor match Jira (score {item['best_ratio']:.2f}): ninguno")

# Resumen de labels existentes en Jira
if jira_labels:
    print("\nLabels existentes en tus issues Jira:")
    print(", ".join(sorted(jira_labels, key=str.lower)))

# Resumen de tareas cerradas en Taskwarrior (últimos 7 días)
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

closed_items = []
for t in data_tw_closed:
    end_raw = t.get("end") or ""
    end_dt = parse_date(end_raw)
    if not end_dt:
        continue
    desc = t.get("description") or ""
    proj = t.get("project") or "Sin proyecto"
    status = (t.get("status") or "").lower()
    closed_items.append((end_dt, proj, desc, status))

if closed_items:
    closed_items.sort(key=lambda x: x[0], reverse=True)
    print("\nTareas cerradas en Taskwarrior (últimos 7 días):")
    for end_dt, proj, desc, status in closed_items:
        when = end_dt.strftime("%Y-%m-%d")
        print(f"- {when} [{proj}] {desc} ({status})")
PY
