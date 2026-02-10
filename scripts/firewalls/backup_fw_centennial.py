import os
import subprocess
from datetime import datetime

import requests

DATE = datetime.now().strftime("%d%m%Y")
LOCATION = "Centennial"
API_URL_BACKUP = "https://X.X.X.X:12443/api/v2/monitor/system/config/backup?scope=global"
DEFAULT_ENV_PATH = os.path.join(os.path.dirname(__file__), "firewalls.env")
ENV_PATH = os.getenv("FIREWALLS_ENV_PATH", DEFAULT_ENV_PATH)


def load_token(env_path: str, location: str) -> str | None:
    token_key = f"{location.upper()}_TOKEN"
    try:
        with open(env_path, "r", encoding="utf-8") as file:
            for line in file:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key.strip() == token_key:
                    return value.strip().strip("\"'")
    except FileNotFoundError:
        return None
    return None


API_TOKEN = load_token(ENV_PATH, LOCATION) or os.getenv("FW_API_TOKEN")

BASE_DIR = "/root/devops/scripts/firewalls"
LOCAL_DIR = os.path.join(BASE_DIR, "backup-config", LOCATION)
OUTPUT_FILE = os.path.join(LOCAL_DIR, f"backup_config_{LOCATION}_{DATE}.conf")
S3_DEST = f"s3://dcops-backup/backup_fw/{LOCATION}/{os.path.basename(OUTPUT_FILE)}"

if not API_TOKEN:
    raise SystemExit(
        "Falta el token. Define FW_API_TOKEN o "
        f"crea {ENV_PATH} con {LOCATION.upper()}_TOKEN=..."
    )

HEADERS = {"Authorization": f"Bearer {API_TOKEN}"}


requests.packages.urllib3.disable_warnings()


def fetch_backup() -> str:
    response = requests.get(API_URL_BACKUP, headers=HEADERS, verify=False, timeout=60)
    if response.status_code != 200:
        raise RuntimeError(
            f"Error al obtener el respaldo. "
            f"Código: {response.status_code}. Respuesta: {response.text}"
        )
    return response.text


def write_backup(content: str) -> None:
    os.makedirs(LOCAL_DIR, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        file.write(content)


def upload_to_s3() -> None:
    subprocess.run(["aws", "s3", "cp", OUTPUT_FILE, S3_DEST], check=True)


def main() -> int:
    try:
        backup_content = fetch_backup()
        write_backup(backup_content)
        print(f"Respaldo guardado correctamente en {OUTPUT_FILE}")
    except Exception as exc:
        print(f"Error al guardar el archivo de respaldo: {exc}")
        return 1

    try:
        upload_to_s3()
        print("Subida a S3 completada.")
    except subprocess.CalledProcessError as exc:
        print(f"Error al subir a S3: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
