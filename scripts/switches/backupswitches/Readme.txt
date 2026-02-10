## Backup Switches – Quincy

Minimal guide to run and extend the switch backup script (`run.py`) using `config.ini`.

### What the script does
- Reads `config.ini` sections (one per switch).
- Connects via Netmiko (`device_type` fs_os or hp_comware) and runs:
  - HPE/Comware: `display current-configuration` (disables paging first).
  - FS: `show running-config`.
- Saves output to `<path>/<SECTION>/<YYYYMMDD-HHMM>.txt`.
- Optional: uploads `/root/devops/switches-config` to S3 (see `local_folder`/`s3_bucket_path` in `run.py`) and deletes the local folder afterward (can skip killing open files with `DISABLE_CLOSE_OPEN_FILES=1`).
- Retries each switch up to 2 times on error. Timeouts use `timing` from `config.ini`.
- Optional Slack notification: set `SLACK_TOKEN` and `SLACK_CHANNEL` (channel name or ID) before running. The script prints to console whether the Slack send succeeds or fails.

### `config.ini` fields (per switch section)
- `[SECTION_NAME]`: also used as folder name under `path`.
- `ip`: switch IP.
- `username` / `password`: SSH creds.
- `path`: base path to store backups (e.g., `/root/devops/switches-config/Quincy`).
- `type`: keep `switch`.
- `device_type`: `fs_os` (FS) or `hp_comware` (HPE). Required for Netmiko.
- `timing`: timeout seconds; also used for per-cycle sleep (minimum across switches).

Commented sections in the file are placeholders; to enable one, uncomment and set `device_type`.

### Running
- All switches: `python3 run.py`
- Single switch by section name: `python3 run.py SW-F25`
- Slack env:
  - A template `slack.env` lives next to `run.py` (empty token, channel devops-test). Fill it with your token and channel, then either `source slack.env` or let `run.py` load it automatically.
  - Keys: `SLACK_TOKEN=<your slack token>`, `SLACK_CHANNEL=<channel name or ID>`.
  - Slack output: one main message with status/S3/success/failed, plus a single thread reply listing Success/Failed with emojis.

### Logs
- `LOGS.py` writes to `Logsswitches-config/Backup_logYYYY_MM_DD.log` and prunes files older than 14 days.

### Notes / safety
- `run.py` will create `path` if missing; ensure the user running it has write perms.
- `cerrar_archivos_abiertos` can terminate processes using the backup folder before deletion; disable with `DISABLE_CLOSE_OPEN_FILES=1` if risky.
- Dependencies: Python 3.8+, `netmiko`, `psutil`, `boto/aws cli` if using S3 upload. Install netmiko: `pip install netmiko`. Ensure the custom `fs_os` driver is present in your Netmiko install if required for FS devices.
