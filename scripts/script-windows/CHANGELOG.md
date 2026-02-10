# Changelog (CodeArtifact Windows setup)

This log summarizes the troubleshooting steps, errors encountered, and fixes applied so the context can be restored later.

## 2026-01-27

### Initial errors
- Permission denied writing `C:\devops\scripts\refresh-codeartifact-token.log`.
- `SetEnvironmentVariable(..., "Machine")` failed due to registry access.
- `pip config set --global` failed to write `C:\ProgramData\pip\pip.ini`.

### Root causes
- Script was not running as Admin/SYSTEM.
- AWS CLI for SYSTEM had no config.
- Token expired in `pip.ini`, causing 401s.
- `aws-cli` v1 was used; Role Anywhere `credential_process` worked only with v2.
- 32-bit PowerShell redirected `System32` to `SysWOW64` (needed Sysnative).
- `GetTokenAWS.ps1` used stale token instead of the fresh one from refresh.

### Fixes applied
- Scheduled task set to run as SYSTEM with highest privileges:
  - `schtasks /Create /TN "RefreshCodeArtifactToken" /SC HOURLY /MO 11 /RU "SYSTEM" /RL HIGHEST /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\devops\scripts\RefreshTokenAWS.ps1"`
- AWS Role Anywhere env vars added at Machine scope:
  - `AWS_REGION`, `AWS_ROLE_ARN`, `AWS_ROLE_SESSION_NAME`
  - `AWS_ROLE_ANYWHERE_PROFILE_ARN`, `AWS_ROLE_ANYWHERE_TRUST_ANCHOR_ARN`
  - `AWS_ROLE_ANYWHERE_CERTIFICATE`, `AWS_ROLE_ANYWHERE_PRIVATE_KEY`
  - `AWS_PROFILE`, `AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`, `AWS_SDK_LOAD_CONFIG`
- AWS config for SYSTEM stored at:
  - `C:\Windows\System32\config\systemprofile\.aws\config`
- AWS CLI v2 forced in scripts:
  - `C:\Program Files\Amazon\AWSCLIV2\aws.exe`
- 32-bit System32 redirection handled:
  - When 32-bit PowerShell, uses `C:\Windows\Sysnative\...` for existence checks.
- `GetTokenAWS.ps1` now accepts `-AuthToken`:
  - Refresh script passes fresh token directly to avoid stale env var.
- `PIP_CONFIG_FILE` set at Machine scope so all users use global config:
  - `C:\ProgramData\pip\pip.ini`
- Added validation and logging:
  - `pip config list --global` before/after refresh.
  - Verified `C:\ProgramData\pip\pip.ini` contains CodeArtifact URLs.

### Key behavior confirmed
- Running AWS CLI v2 manually with:
  - `AWS_CONFIG_FILE=C:\Windows\System32\config\systemprofile\.aws\config`
  - `AWS_SHARED_CREDENTIALS_FILE=C:\Windows\System32\config\systemprofile\.aws\credentials`
  returns a token successfully.
- Token refresh now updates `pip.ini` correctly when `GetTokenAWS.ps1` receives `-AuthToken`.

### Final settings (important)
- CodeArtifact domain owner that works: `XXXXXXXXXXXX` (not `XXXXXXXXXXXX`).
- Domain: `vdp-artifacts`
- Region: `us-east-1`
- Repos:
  - `pypi-store`
  - `cda-pypi-repository-releases`
  - `cda-pypi-repository-snapshots`

### Common 401 cause
- Token expired in `pip.ini`. Refresh must run every 11 hours.

### Files changed
- `C:\devops\scripts\RefreshTokenAWS.ps1`
- `C:\devops\scripts\GetTokenAWS.ps1`
- `C:\ProgramData\pip\pip.ini`

