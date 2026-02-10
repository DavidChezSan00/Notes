<#
Refreshes the AWS CodeArtifact auth token, stores it as a system env var,iene 
then updates global pip config using configure-pip-codeartifact.ps1.
Run as Administrator or SYSTEM.
#>

$DOMAIN       = "vdp-artifacts"
$DOMAIN_OWNER = "XXXXXXXXXXXX"
$REGION       = "us-east-1"

# Optional AWS Role Anywhere env vars (set to "" to skip)
$AWS_REGION                      = "us-east-1"
$AWS_ROLE_ARN                    = "arn:aws:iam::XXXXXXXXXXXX:role/onprem/onprem-winfarm-01"
$AWS_ROLE_SESSION_NAME           = "onprem-winfarm-01"
$AWS_ROLE_ANYWHERE_PROFILE_ARN   = "arn:aws:rolesanywhere:us-east-1:XXXXXXXXXXXX:profile/edb51850-2911-488b-ac40-474b1569a0c5"
$AWS_ROLE_ANYWHERE_TRUST_ANCHOR_ARN = "arn:aws:rolesanywhere:us-east-1:XXXXXXXXXXXX:trust-anchor/297cf44d-61ff-4b82-9a9f-ca941ccb35d6"
$AWS_ROLE_ANYWHERE_CERTIFICATE   = "C:\devops\certs\aws-onprem-winfarm.pem"
$AWS_ROLE_ANYWHERE_PRIVATE_KEY   = "C:\devops\certs\aws-onprem-winfarm.key"
$AWS_PROFILE                     = "default"
$AWS_CONFIG_FILE                 = "C:\Windows\System32\config\systemprofile\.aws\config"
$AWS_SHARED_CREDENTIALS_FILE     = "C:\Windows\System32\config\systemprofile\.aws\credentials"
$AWS_SDK_LOAD_CONFIG             = "1"
$AWS_CLI_V2_PATH                 = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

$AWS_CONFIG_FILE_RAW = $AWS_CONFIG_FILE
$AWS_SHARED_CREDENTIALS_FILE_RAW = $AWS_SHARED_CREDENTIALS_FILE

function Resolve-SystemPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    # If running 32-bit PowerShell on 64-bit Windows, System32 is redirected to SysWOW64.
    if ($env:PROCESSOR_ARCHITEW6432 -and ($Path -match '^[A-Za-z]:\\Windows\\System32\\')) {
        return ($Path -replace '\\Windows\\System32\\', '\Windows\Sysnative\')
    }
    return $Path
}

function Normalize-AwsConfigProfile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $Path }
    $content = Get-Content -Path $Path -Raw
    if ($content -match '(?m)^\s*\[default\]\s*$') { return $Path }
    if ($content -match '(?m)^\s*\[profile\s+default\]\s*$') {
        $tmp = Join-Path $env:TEMP ("aws-config-default-{0}.ini" -f $PID)
        $content = $content -replace '(?m)^\s*\[profile\s+default\]\s*$', '[default]'
        Set-Content -Path $tmp -Value $content -Encoding UTF8
        Write-Log "AWS config normalized to use [default] at $tmp."
        return $tmp
    }
    return $Path
}

$AWS_CONFIG_FILE = Resolve-SystemPath $AWS_CONFIG_FILE
$AWS_SHARED_CREDENTIALS_FILE = Resolve-SystemPath $AWS_SHARED_CREDENTIALS_FILE

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$CONFIG_SCRIPT = Join-Path $SCRIPT_DIR "GetTokenAWS.ps1"
$LOG_PATH = Join-Path $SCRIPT_DIR "refresh-codeartifact-token.log"
$LOG_ROTATE_BYTES = 1048576

function Rotate-LogIfNeeded {
    if (Test-Path $LOG_PATH) {
        $logSize = (Get-Item $LOG_PATH).Length
        if ($logSize -ge $LOG_ROTATE_BYTES) {
            $backup1 = "$LOG_PATH.1"
            $backup2 = "$LOG_PATH.2"
            if (Test-Path $backup2) { Remove-Item $backup2 -Force }
            if (Test-Path $backup1) { Move-Item $backup1 $backup2 }
            Move-Item $LOG_PATH $backup1
        }
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LOG_PATH -Value "[$timestamp] [$Level] $Message"
}

Rotate-LogIfNeeded
Write-Log "Starting token refresh."

if ($AWS_CONFIG_FILE -ne $AWS_CONFIG_FILE_RAW) {
    Write-Log "AWS_CONFIG_FILE redirected to '$AWS_CONFIG_FILE' (32-bit System32 redirection)."
}
if ($AWS_SHARED_CREDENTIALS_FILE -ne $AWS_SHARED_CREDENTIALS_FILE_RAW) {
    Write-Log "AWS_SHARED_CREDENTIALS_FILE redirected to '$AWS_SHARED_CREDENTIALS_FILE' (32-bit System32 redirection)."
}

# Log current pip global config before refresh (if pip exists)
$pipCmdPre = Get-Command pip -ErrorAction SilentlyContinue
if ($pipCmdPre) {
    Write-Log "pip path: $($pipCmdPre.Source)"
    Write-Log "pip --version: $(pip --version 2>$null)"
    $pipConfigBefore = pip config list --global 2>$null
    if ($pipConfigBefore) {
        Write-Log "pip global config (before refresh):"
        Add-Content -Path $LOG_PATH -Value $pipConfigBefore
    } else {
        Write-Log "pip global config (before refresh) is empty or unreadable." "WARN"
    }
} else {
    Write-Log "pip not found in PATH (before refresh)." "WARN"
}

# Set machine-level env vars for AWS Role Anywhere (if provided)
$awsEnvMap = @{
    "AWS_REGION"                        = $AWS_REGION
    "AWS_DEFAULT_REGION"                = $AWS_REGION
    "AWS_ROLE_ARN"                      = $AWS_ROLE_ARN
    "AWS_ROLE_SESSION_NAME"             = $AWS_ROLE_SESSION_NAME
    "AWS_ROLE_ANYWHERE_PROFILE_ARN"     = $AWS_ROLE_ANYWHERE_PROFILE_ARN
    "AWS_ROLE_ANYWHERE_TRUST_ANCHOR_ARN"= $AWS_ROLE_ANYWHERE_TRUST_ANCHOR_ARN
    "AWS_ROLE_ANYWHERE_CERTIFICATE"     = $AWS_ROLE_ANYWHERE_CERTIFICATE
    "AWS_ROLE_ANYWHERE_PRIVATE_KEY"     = $AWS_ROLE_ANYWHERE_PRIVATE_KEY
    "AWS_PROFILE"                       = $AWS_PROFILE
    "AWS_CONFIG_FILE"                   = $AWS_CONFIG_FILE
    "AWS_SHARED_CREDENTIALS_FILE"       = $AWS_SHARED_CREDENTIALS_FILE
    "AWS_SDK_LOAD_CONFIG"               = $AWS_SDK_LOAD_CONFIG
}

foreach ($kv in $awsEnvMap.GetEnumerator()) {
    if ($kv.Value -and $kv.Value.Trim() -ne "") {
        [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Machine")
        Set-Item -Path ("env:{0}" -f $kv.Key) -Value $kv.Value
        Write-Log "Set machine env $($kv.Key)."
    }
}

$awsCmd = $null
if (Test-Path $AWS_CLI_V2_PATH) {
    $awsCmd = $AWS_CLI_V2_PATH
    # AWS CLI v2 is 64-bit; use System32 paths to avoid Sysnative issues.
    $AWS_CONFIG_FILE = $AWS_CONFIG_FILE_RAW
    $AWS_SHARED_CREDENTIALS_FILE = $AWS_SHARED_CREDENTIALS_FILE_RAW
} else {
    $awsCmd = (Get-Command aws -ErrorAction SilentlyContinue).Source
    $AWS_CONFIG_FILE = Resolve-SystemPath $AWS_CONFIG_FILE_RAW
    $AWS_SHARED_CREDENTIALS_FILE = Resolve-SystemPath $AWS_SHARED_CREDENTIALS_FILE_RAW
}
if (-not $awsCmd) {
    Write-Log "aws CLI not found (v2 path missing and not in PATH)." "ERROR"
    exit 1
}
Write-Log "Using aws CLI at $awsCmd."

# Ensure AWS config for SYSTEM is available
if ($AWS_CONFIG_FILE) {
    $AWS_CONFIG_FILE = $AWS_CONFIG_FILE.Trim()
    Write-Log "AWS_CONFIG_FILE resolved to '$AWS_CONFIG_FILE'."
    # Test-Path can be redirected in 32-bit PowerShell; check via Sysnative when needed.
    $testPath = Resolve-SystemPath $AWS_CONFIG_FILE_RAW
    if (-not (Test-Path $testPath)) {
        Write-Log "AWS config file not found at $testPath (profile=$AWS_PROFILE)." "ERROR"
        exit 1
    }
    if ($AWS_CONFIG_FILE -ne $testPath) {
        Write-Log "AWS config file exists at '$testPath' (redirected path)."
    }
    $AWS_CONFIG_FILE = Normalize-AwsConfigProfile $AWS_CONFIG_FILE
}

# Ensure the process env vars match the resolved paths before calling aws
if ($AWS_CONFIG_FILE) {
    Set-Item -Path "env:AWS_CONFIG_FILE" -Value $AWS_CONFIG_FILE
}
if ($AWS_SHARED_CREDENTIALS_FILE) {
    Set-Item -Path "env:AWS_SHARED_CREDENTIALS_FILE" -Value $AWS_SHARED_CREDENTIALS_FILE
}
Set-Item -Path "env:AWS_PROFILE" -Value $AWS_PROFILE
Set-Item -Path "env:AWS_DEFAULT_PROFILE" -Value $AWS_PROFILE

# Capture current token (if any) before refresh
$OLD_TOKEN = [Environment]::GetEnvironmentVariable("CODEARTIFACT_AUTH_TOKEN", "Machine")

# Get a fresh token
$AUTH_TOKEN = & $awsCmd codeartifact get-authorization-token `
    --domain $DOMAIN `
    --domain-owner $DOMAIN_OWNER `
    --region $REGION `
    --query authorizationToken `
    --output text

if (-not $AUTH_TOKEN) {
    Write-Log "Failed to obtain CodeArtifact token." "ERROR"
    exit 1
}

# Persist system environment variable
[Environment]::SetEnvironmentVariable("CODEARTIFACT_AUTH_TOKEN", $AUTH_TOKEN, "Machine")
$tokenLast4 = $AUTH_TOKEN.Substring([Math]::Max(0, $AUTH_TOKEN.Length - 4))
Write-Log "Updated CODEARTIFACT_AUTH_TOKEN at Machine scope (last4=$tokenLast4)."

# Validate token update
if ($OLD_TOKEN -and ($OLD_TOKEN -eq $AUTH_TOKEN)) {
    Write-Log "CODEARTIFACT_AUTH_TOKEN did not change after refresh (last4=$tokenLast4)." "WARN"
} else {
    Write-Log "CODEARTIFACT_AUTH_TOKEN updated successfully (last4=$tokenLast4)."
}

# Update pip global config
& $CONFIG_SCRIPT -AuthToken $AUTH_TOKEN
Write-Log "Ran GetTokenAWS.ps1."

$pipCmd = Get-Command pip -ErrorAction SilentlyContinue
if (-not $pipCmd) {
    Write-Log "pip not found in PATH; skipping validation." "WARN"
    exit 0
}

$pipConfig = pip config list --global 2>$null
if ($pipConfig -and ($pipConfig -match "codeartifact")) {
    Write-Log "pip global config validation passed."
} else {
    Write-Log "pip global config validation failed or missing CodeArtifact URLs." "WARN"
}

# Log pip global config after refresh
if ($pipConfig) {
    Write-Log "pip global config (after refresh):"
    Add-Content -Path $LOG_PATH -Value $pipConfig
}

# Force all users to use the global pip.ini
[Environment]::SetEnvironmentVariable("PIP_CONFIG_FILE", "C:\ProgramData\pip\pip.ini", "Machine")
Write-Log "Set machine env PIP_CONFIG_FILE to C:\ProgramData\pip\pip.ini."
