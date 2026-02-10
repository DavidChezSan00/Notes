import configparser
import json
import os
import time
from netmiko import ConnectHandler
import subprocess
import shutil
import psutil  # Para verificar procesos abiertos
import sys
import urllib.request
from LOGS import log

# Load slack env file if present
def cargar_entorno_slack():
    env_path = os.path.join(obtener_ruta_script(), "slack.env")
    if not os.path.exists(env_path):
        return
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export "):]
                if "=" not in line:
                    continue
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                if key and key not in os.environ:
                    os.environ[key] = val
    except Exception:
        pass

def obtener_ruta_script():
    return os.path.dirname(os.path.abspath(__file__))

def cargar_configuracion():
    config = configparser.ConfigParser()
    config.read(os.path.join(obtener_ruta_script(), 'config.ini'))
    return config

def cerrar_archivos_abiertos(ruta):
    for proc in psutil.process_iter(['pid', 'open_files']):
        try:
            if proc.info['open_files']:
                for archivo in proc.info['open_files']:
                    if ruta in archivo.path:
                        print(f"Cerrando proceso {proc.pid} que usa {archivo.path}")
                        proc.terminate()
        except Exception:
            continue

def enviar_slack(texto: str, attachments=None, thread_ts: str = None):
    # Define SLACK_TOKEN and SLACK_CHANNEL in slack.env or env before running.
    token = XXXX"SLACK_TOKEN", "").strip()
    channel = os.environ.get("SLACK_CHANNEL", "").strip()
    if not token or not channel:
        msg = "Slack not configured (missing SLACK_TOKEN or SLACK_CHANNEL)."
        log.logs(messages=msg)
        print(msg)
        return None
    payload = {
        "channel": channel,
        "text": texto,
    }
    if attachments:
        payload["attachments"] = attachments
    if thread_ts:
        payload["thread_ts"] = thread_ts
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=data,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp_data = json.loads(resp.read().decode())
            if not resp_data.get("ok"):
                raise RuntimeError(resp_data.get("error", "unknown_error"))
            log.logs(messages=f"Slack notification sent to {channel}.")
            print(f"Slack notification sent to {channel}.")
            return resp_data.get("ts")
    except Exception as e:
        log.logs(messages=f"No se pudo enviar mensaje a Slack: {e}")
        print(f"No se pudo enviar mensaje a Slack: {e}")
        return None

def backup_function(max_cycles=1, only_switch=None):
    config = cargar_configuracion()
    cycle_count = 0
    max_retries = 2  # reintentos por host
    success_hosts = []
    failed_hosts = []
    
    while cycle_count < max_cycles:
        today = time.strftime("%Y%m%d-%H%M", time.localtime())
        cycle_wait = None
        
        for section in config.sections():
            if config[section].get('type') == 'switch':
                if only_switch and section.lower() != only_switch.lower():
                    continue
                switch_path = config[section]['path']
                # Validar ruta base
                try:
                    os.makedirs(switch_path, exist_ok=True)
                except Exception as e:
                    error_msg = f"No se puede preparar la ruta {switch_path} para {section}: {e}"
                    log.logs(messages=error_msg)
                    print(error_msg)
                    continue

                timing_cfg = int(config[section].get('timing', '60'))
                if cycle_wait is None:
                    cycle_wait = timing_cfg
                else:
                    cycle_wait = min(cycle_wait, timing_cfg)
                switch_info = {
                    'device_type': config[section]['device_type'],
                    'ip': config[section]['ip'],
                    'username': config[section]['username'],
                    'password': config[section]['password'],
                    'conn_timeout': timing_cfg,
                    'timeout': timing_cfg,
                    'banner_timeout': timing_cfg,
                    'global_delay_factor': 2,
                }
                
                backup_command = 'display current-configuration' if switch_info['device_type'] == 'hp_comware' else 'show running-config'

                output = None
                for attempt in range(1, max_retries + 1):
                    try:
                        with ConnectHandler(**switch_info) as conn:
                            if switch_info['device_type'] == 'hp_comware':
                                conn.send_command("screen-length disable", expect_string=r"<.*>")
                                time.sleep(1)
                         
                            output = conn.send_command(
                                backup_command,
                                delay_factor=2,
                                read_timeout=timing_cfg,
                            ).strip()
                        break
                    except Exception as e:
                        if attempt >= max_retries:
                            error_msg = f"Error en {section} <{switch_info['ip']}> tras {attempt} intentos: {str(e)}"
                            log.logs(messages=error_msg)
                            print(error_msg)
                            failed_hosts.append(f"{section} ({switch_info['ip']})")
                        else:
                            warn = f"Error en {section} <{switch_info['ip']}> (intento {attempt}), reintentando..."
                            log.logs(messages=warn)
                            print(warn)
                            time.sleep(2)
                if output is None:
                    continue

                # Crear carpeta y archivo de respaldo
                backup_folder = os.path.join(switch_path, section)
                os.makedirs(backup_folder, exist_ok=True)
                backup_file = os.path.join(backup_folder, f'{today}.txt')

                with open(backup_file, "w") as f:
                    f.write(output)
                 
                log.logs(messages=f"Backup exitoso para {section}: {backup_file}")
                print(f"Backup exitoso para {section}: {backup_file}")
                success_hosts.append(section)

        time.sleep(cycle_wait or 60)
        cycle_count += 1

    local_folder = "/root/devops/switches-config"  # Ruta de la carpeta Quincy
    s3_bucket_path = "s3://dcops-backup/backup_switches/"  # Ruta a S3
    s3_status = "S3 upload: not attempted"

    try:
        subprocess.run(["aws", "s3", "cp", local_folder, s3_bucket_path, "--recursive"], check=True)
        print("Subida a S3 completada.")
        log.logs(messages="Subida a S3 completada.")
        s3_status = "S3 upload: OK"
    except subprocess.CalledProcessError as e:
        error_msg = f"Error al subir a S3: {e}"
        print(error_msg)
        log.logs(messages=error_msg)
        s3_status = "S3 upload: FAILED"

    # Eliminar la carpeta local después de subir a S3
    try:
        if os.environ.get("DISABLE_CLOSE_OPEN_FILES", "").lower() not in ("1", "true", "yes"):
            cerrar_archivos_abiertos(local_folder)
            time.sleep(2)  # Espera para asegurarse de que los archivos se cierren
        shutil.rmtree(local_folder)
        print(f"Carpeta {local_folder} eliminada exitosamente.")
        log.logs(messages=f"Carpeta {local_folder} eliminada exitosamente.")
    except Exception as e:
        error_msg = f"Error al eliminar la carpeta {local_folder}: {e}"
        print(error_msg)
        log.logs(messages=error_msg)
        s3_status += " | delete local: FAILED"

    # Enviar resumen a Slack (mensaje principal + 1 hilo)
    try:
        ok = not failed_hosts
        status_text = ("✅ Switch Backups OK" if ok else "⚠️ Switch Backups Issues")
        color = "#2eb886" if ok else "#e01e5a"
        main_attach = [{
            "color": color,
            "fields": [
                {"title": "S3", "value": s3_status, "short": True},
                {"title": "Success", "value": str(len(success_hosts)), "short": True},
                {"title": "Failed", "value": str(len(failed_hosts)), "short": True},
            ],
        }]
        ts = enviar_slack(status_text, attachments=main_attach)
        # Detalles en hilo (una sola respuesta con ambas listas)
        if ts:
            if success_hosts or failed_hosts:
                parts = []
                if success_hosts:
                    parts.append("Success:\n" + "\n".join(f"✅ {h}" for h in success_hosts))
                if failed_hosts:
                    parts.append("Failed:\n" + "\n".join(f"❌ {h}" for h in failed_hosts))
                enviar_slack("\n\n".join(parts), thread_ts=ts)
            else:
                enviar_slack("No hosts processed.", thread_ts=ts)
    except Exception:
        pass

if __name__ == "__main__":
    # Permite pasar opcionalmente el nombre del switch (section) como argumento
    cargar_entorno_slack()
    target = None
    if len(sys.argv) > 1:
        target = sys.argv[1]
    backup_function(max_cycles=1, only_switch=target)
