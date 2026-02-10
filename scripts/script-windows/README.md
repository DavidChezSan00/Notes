# CodeArtifact pip setup (Windows)

This folder contains PowerShell scripts to configure pip to use AWS CodeArtifact and to refresh the auth token on a schedule.

## Files

- GetTokenAWS.ps1
  - Configures pip global indexes to use CodeArtifact repositories.
  - Uses CODEARTIFACT_AUTH_TOKEN if present; otherwise fetches a token via AWS CLI.
  - Accepts `-AuthToken` to force a specific token (used by RefreshTokenAWS.ps1).
  - Validates that `C:\ProgramData\pip\pip.ini` was updated.
- RefreshTokenAWS.ps1
  - Refreshes the CodeArtifact token, stores it as a system env var, and then runs GetTokenAWS.ps1.
  - Writes a log file and validates pip global config.
- refresh-codeartifact-token.log
  - Log file written by RefreshTokenAWS.ps1 (rotated when it reaches 1 MB).

## Prerequisites

- AWS CLI v2 installed (preferred). Script forces v2 path if present:
  - `C:\Program Files\Amazon\AWSCLIV2\aws.exe`
- AWS credentials that can call codeartifact:GetAuthorizationToken.
- Administrator permissions to write global pip config.

## Paths and locations

- Scripts live on Windows at C:\devops\scripts\
- Global pip config is written to C:\ProgramData\pip\pip.ini
- System env var used: CODEARTIFACT_AUTH_TOKEN
- Machine env var forced: PIP_CONFIG_FILE = C:\ProgramData\pip\pip.ini

## How it works

1) RefreshTokenAWS.ps1 fetches a new CodeArtifact token via AWS CLI.
2) The token is saved as a machine-level environment variable.
3) GetTokenAWS.ps1 updates pip global index URLs using that token (via -AuthToken).
4) A scheduled task refreshes the token every 11 hours.

## What was changed

1) Added support for CODEARTIFACT_AUTH_TOKEN in GetTokenAWS.ps1 (configure-pip-codeartifact.ps1).
2) Set pip configuration with --global (writes to C:\ProgramData\pip\pip.ini).
3) Created RefreshTokenAWS.ps1 to refresh the token, update the system env var, and reconfigure pip.
4) Added log rotation and token last-4 logging for verification.
5) Scheduled task to refresh the token every 11 hours.
6) Role Anywhere env vars set at Machine scope (AWS_ROLE_*, AWS_REGION, AWS_PROFILE, etc.).
7) AWS CLI v2 forced if present to avoid CLI v1 limitations.
8) 32-bit System32 redirection handled; uses Sysnative when needed.
9) PIP_CONFIG_FILE set at Machine scope to force all users to use global pip.ini.

## Scripts

### GetTokenAWS.ps1

- Requires AWS CLI v2 in PATH (unless CODEARTIFACT_AUTH_TOKEN is already set).
- Requires Administrator permissions for --global pip config.
- Accepts `-AuthToken` (used by RefreshTokenAWS.ps1).
- Writes to `C:\ProgramData\pip\pip.ini` and validates the file.

### RefreshTokenAWS.ps1

- Requires AWS CLI v2 in PATH.
- Must run as Administrator or SYSTEM.
- Logs to refresh-codeartifact-token.log with rotation (keeps .1 and .2).
- Logs the last 4 characters of the new token for verification.
- Validates pip global config by checking for CodeArtifact URLs.
- Sets `PIP_CONFIG_FILE` at Machine scope so all users use global pip.ini.

## Scheduled tasks

Run these in an elevated PowerShell:

Every 11 hours:

    schtasks /Create /TN "RefreshCodeArtifactToken" /SC HOURLY /MO 11 /RU "SYSTEM" /RL HIGHEST /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\devops\scripts\RefreshTokenAWS.ps1"

## Manual checks

Run these to verify:

- Current machine token:

    XXXX"CODEARTIFACT_AUTH_TOKEN", "Machine")

- pip global config:

    pip config list --global

- pip config file used by all users (forced):

    [Environment]::GetEnvironmentVariable("PIP_CONFIG_FILE", "Machine")

- Log tail:

    Get-Content C:\devops\scripts\refresh-codeartifact-token.log -Tail 50

## Troubleshooting

- "Permission denied" writing pip.ini: run PowerShell as Administrator.
- "aws CLI not found": ensure aws.exe is in PATH for SYSTEM.
- AccessDenied on GetAuthorizationToken: check AWS credentials and policies.
- pip not using CodeArtifact: rerun RefreshTokenAWS.ps1 and check pip config list --global.

## Validation details

- Confirm the scheduled task runs as SYSTEM:

    schtasks /Query /TN "RefreshCodeArtifactToken" /V /FO LIST

- Confirm aws CLI is available for SYSTEM:

    where.exe aws

- Confirm the token changes (last 4 logged):

    Get-Content C:\devops\scripts\refresh-codeartifact-token.log -Tail 50

## AWS credentials notes (SYSTEM)

- The scheduled task runs as SYSTEM, so it does not use your user profile.
- If aws CLI cannot find credentials, place them in C:\Windows\System32\config\systemprofile\.aws\credentials and C:\Windows\System32\config\systemprofile\.aws\config, or set machine-level AWS_* environment variables.
- If you rely on a named profile, set a machine-level AWS_PROFILE so SYSTEM can use it.

## Rollback

- Remove the scheduled task:

    schtasks /Delete /TN "RefreshCodeArtifactToken" /F

- Remove the system token:

    XXXX"CODEARTIFACT_AUTH_TOKEN", $null, "Machine")

- Remove pip global config:

    pip config unset --global global.index-url
    pip config unset --global global.extra-index-url

## Notes

- The CodeArtifact token expires every 12 hours, so refresh every 11 hours.
- Do not share the full token in chat or logs; use last 4 only if needed.
 - If installs still return 401, ensure DOMAIN_OWNER matches the CodeArtifact account (XXXXXXXXXXXX here).
