#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_DOMAIN='vdp-prod'
DEFAULT_USER='adm-david'
DEFAULT_REMOTE_COMMAND='choco --version'
DEFAULT_IMPACKET_WMI="$HOME/Documentos/repos/impacket/examples/wmiexec.py"

HOSTS=(
  qy-frontend-01
  qy-frontend-02
  qy-frontend-03
  qy-frontend-04
  qy-frontend-05
  qy-frontend-06
  qy-frontend-07
  qy-frontend-08
  qy-frontend-09
  qy-frontend-10
  qy-frontend-11
  qy-frontend-12
  qy-frontend-13
  qy-frontend-14
  qy-frontend-15
  qy-frontend-16
  qy-frontend-17
  qy-frontend-18
  qy-frontend-19
  qy-frontend-20
  qy-frontend-21
  qy-frontend-22
  qy-frontend-23
  qy-frontend-24
  qy-frontend-25
  qy-frontend-26
  qy-frontend-27
  qy-frontend-28
  qy-frontend-29
  qy-frontend-30
  qy-frontend-31
  qy-frontend-32
  vx-quincy-1
  vx-quincy-2
)

AD_DOMAIN=${AD_DOMAIN:-$DEFAULT_DOMAIN}
AD_USER=${AD_USER:-$DEFAULT_USER}
IMPACKET_WMI=${IMPACKET_WMI:-$DEFAULT_IMPACKET_WMI}
DEBUG=${DEBUG:-false}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-0}

usage() {
  cat <<'USAGE'
Uso:
  execute_remote_commands.sh [opciones] [--] [comando]

Opciones principales:
  -H, --host HOST        Añade un host (puedes repetir la opción).
      --hosts LISTA      Lista de hosts separados por espacios tras la opción.
  -f, --host-file PATH   Lee hosts de un archivo (uno por línea).
  -d, --domain DOMINIO   Cambia el dominio (defecto: vdp-prod).
  -u, --user USUARIO     Cambia el usuario (defecto: adm-david).
  -w, --wmiexec RUTA     Ruta a wmiexec.py.
  -t, --timeout SEG      Finaliza tras SEG segundos (0 = sin límite).
  -v, --debug            Traza adicional.
  -h, --help             Muestra esta ayuda.

Si no pasas comando se usa "choco --version". Exporta PASSWORD para evitar el prompt.
USAGE
}

log() {
  local level="$1"; shift
  [[ "$DEBUG" == true ]] || [[ "$level" != DEBUG ]] || printf '[%s] %s\n' "$level" "$*" >&2
  [[ "$level" != DEBUG ]] && printf '[%s] %s\n' "$level" "$*" >&2
}

log_debug() {
  if [[ "$DEBUG" == true ]]; then
    printf '[DEBUG] %s\n' "$*" >&2
  fi
}

trim() {
  local value="$1"
  value=${value//$'\r'/}
  value="${value##+([[:space:]])}"
  value="${value%%+([[:space:]])}"
  printf '%s' "$value"
}

resolve_impacket_command() {
  local candidate="$1"
  if [[ -f "$candidate" ]]; then
    echo "python3 $candidate"
    return
  fi
  if command -v "$candidate" >/dev/null 2>&1; then
    command -v "$candidate"
    return
  fi
  if command -v wmiexec.py >/dev/null 2>&1; then
    command -v wmiexec.py
    return
  fi
  if python3 -c 'import impacket.examples.wmiexec' >/dev/null 2>&1; then
    echo "python3 -m impacket.examples.wmiexec"
    return
  fi
  printf 'ERROR: No encuentro wmiexec.py; usa -w/IMPACKET_WMI\n' >&2
  exit 1
}

HOST_MAP_FILE=$(mktemp)
trap 'rm -f "$HOST_MAP_FILE"' EXIT
printf '%s\n' "${HOSTS[@]}" >"$HOST_MAP_FILE"

valid_host() {
  grep -Fxq "$1" "$HOST_MAP_FILE"
}

REMOTE_COMMAND=""
SELECTED_HOSTS=()

while (($#)); do
  case "$1" in
    -H|--host)
      (($# >= 2)) || { printf 'Falta valor para %s\n' "$1" >&2; exit 1; }
      SELECTED_HOSTS+=("$2")
      shift 2
      ;;
    --hosts)
      shift
      [[ $# -ge 1 ]] || { printf 'Falta lista para --hosts\n' >&2; exit 1; }
      while (($#)) && [[ "$1" != --* ]]; do
        SELECTED_HOSTS+=("$1")
        shift
      done
      ;;
    -f|--host-file)
      (($# >= 2)) || { printf 'Falta valor para %s\n' "$1" >&2; exit 1; }
      [[ -f "$2" ]] || { printf 'Archivo no encontrado: %s\n' "$2" >&2; exit 1; }
      while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(trim "$line")
        [[ -z "$line" || ${line:0:1} == '#' ]] && continue
        SELECTED_HOSTS+=("$line")
      done <"$2"
      shift 2
      ;;
    -d|--domain)
      (($# >= 2)) || { printf 'Falta valor para %s\n' "$1" >&2; exit 1; }
      AD_DOMAIN="$2"
      shift 2
      ;;
    -u|--user)
      (($# >= 2)) || { printf 'Falta valor para %s\n' "$1" >&2; exit 1; }
      AD_USER="$2"
      shift 2
      ;;
    -w|--wmiexec)
      (($# >= 2)) || { printf 'Falta valor para %s\n' "$1" >&2; exit 1; }
      IMPACKET_WMI="$2"
      shift 2
      ;;
    -t|--timeout)
      (($# >= 2)) || { printf 'Falta valor para %s\n' "$1" >&2; exit 1; }
      [[ "$2" =~ ^[0-9]+$ ]] || { printf 'Timeout inválido\n' >&2; exit 1; }
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    -v|--debug)
      DEBUG=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      REMOTE_COMMAND="$*"
      break
      ;;
    -* )
      printf 'Opción desconocida: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      REMOTE_COMMAND="$*"
      break
      ;;
  esac
done

if [[ -z "$REMOTE_COMMAND" ]]; then
  read -rp "Comando remoto [${DEFAULT_REMOTE_COMMAND}]: " REMOTE_COMMAND
  REMOTE_COMMAND=${REMOTE_COMMAND:-$DEFAULT_REMOTE_COMMAND}
fi

[[ -n "$REMOTE_COMMAND" ]] || { printf 'Comando vacío\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'python3 es obligatorio\n' >&2; exit 1; }
IMPACKET_CMD_STR=$(resolve_impacket_command "$IMPACKET_WMI")
read -r -a IMPACKET_CMD <<<"$IMPACKET_CMD_STR"

if [[ -z "${PASSWORD:XXXX" ]]; then
  read -rs -p "Contraseña de ${AD_DOMAIN}\\${AD_USER}: " PASSWORD
  echo
fi

if ((${#SELECTED_HOSTS[@]} == 0)); then
  SELECTED_HOSTS=("${HOSTS[@]}")
fi

TARGET_HOSTS=()
declare -A seen=()
for host in "${SELECTED_HOSTS[@]}"; do
  host=$(trim "$host")
  [[ -z "$host" ]] && continue
  valid_host "$host" || { printf 'Host no permitido: %s\n' "$host" >&2; exit 1; }
  [[ -n "${seen[$host]:-}" ]] && continue
  seen[$host]=1
  TARGET_HOSTS+=("$host")
done

run_command() {
  local host="$1"
  echo "==================================================================="
  printf 'Host: %s\n' "$host"
  printf 'Comando: %s\n' "$REMOTE_COMMAND"
  echo "-------------------------------------------------------------------"

  local exec=("${IMPACKET_CMD[@]}" "${AD_DOMAIN}/${AD_USER}:${PASSWORD}@${host}" "$REMOTE_COMMAND")
  local status
  set +e
  if [[ "$TIMEOUT_SECONDS" -gt 0 ]]; then
    timeout "$TIMEOUT_SECONDS" "${exec[@]}"
    status=$?
  else
    "${exec[@]}"
    status=$?
  fi
  set -e

  if ((status == 0)); then
    echo "--- Resultado OK (${status}) ---"
  elif ((status == 124)); then
    echo "✗ Timeout tras ${TIMEOUT_SECONDS}s (host $host)"
  else
    echo "✗ Error (${status}) ejecutando en $host"
  fi
  echo
}

for host in "${TARGET_HOSTS[@]}"; do
  run_command "$host"
done
