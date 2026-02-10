<# 
Configures pip to use AWS CodeArtifact repositories.
Requires AWS CLI v2 configured with permissions to get a CodeArtifact token.
#>

param(
    [string]$AuthToken
)
$REPOS = @(
    "pypi-store"
    "cda-pypi-repository-releases"
    "cda-pypi-repository-snapshots"
)

$DOMAIN       = "vdp-artifacts"
$DOMAIN_OWNER = "XXXXXXXXXXXX" # AWS Dev account
$REGION       = "us-east-1"

# Debug logging (set to $false to reduce output)
$ENABLE_DEBUG_LOG = $true

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
        return $tmp
    }
    return $Path
}

$AWS_CONFIG_FILE = Resolve-SystemPath $AWS_CONFIG_FILE
$AWS_SHARED_CREDENTIALS_FILE = Resolve-SystemPath $AWS_SHARED_CREDENTIALS_FILE
$AWS_CONFIG_FILE = Normalize-AwsConfigProfile $AWS_CONFIG_FILE

# Set process-level env vars for this run
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
    }
}

# Fetch CodeArtifact token (prefer explicit param, then shared env var)
$AUTH_TOKEN = $AuthToken
if (-not $AUTH_TOKEN) {
    $AUTH_TOKEN = $env:CODEARTIFACT_AUTH_TOKEN
}
if (-not $AUTH_TOKEN) {
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
        Write-Warning "aws CLI not found (v2 path missing and not in PATH); skipping token fetch."
    } else {
        if ($AWS_CONFIG_FILE) { Set-Item -Path "env:AWS_CONFIG_FILE" -Value $AWS_CONFIG_FILE }
        if ($AWS_SHARED_CREDENTIALS_FILE) { Set-Item -Path "env:AWS_SHARED_CREDENTIALS_FILE" -Value $AWS_SHARED_CREDENTIALS_FILE }
        Set-Item -Path "env:AWS_PROFILE" -Value $AWS_PROFILE
        Set-Item -Path "env:AWS_DEFAULT_PROFILE" -Value $AWS_PROFILE
        $AUTH_TOKEN = & $awsCmd codeartifact get-authorization-token `
        --domain $DOMAIN `
        --domain-owner $DOMAIN_OWNER `
        --region $REGION `
        --query authorizationToken `
        --output text
    }
}

if (-not $AUTH_TOKEN) {
    Write-Warning "Could not obtain CodeArtifact token; skipping pip configuration."
} elseif ($REPOS.Count -lt 1) {
    Write-Warning "No repos defined in REPOS; skipping pip configuration."
} else {
    if ($ENABLE_DEBUG_LOG) {
        $pipCmd = Get-Command pip -ErrorAction SilentlyContinue
        if ($pipCmd) {
            Write-Host "pip path: $($pipCmd.Source)"
            Write-Host "pip version: $(pip --version 2>$null)"
        } else {
            Write-Host "pip not found in PATH."
        }
        Write-Host "pip config debug (global):"
        pip config debug | Select-String -Pattern "global","global\.config","site","site\.config","env","env\.var"
    }

    $MAIN_REPO = $REPOS[0]
    $MAIN_URL  = "https://aws:$AUTH_TOKEN@$DOMAIN-$DOMAIN_OWNER.d.codeartifact.$REGION.amazonaws.com/pypi/$MAIN_REPO/simple/"

    # Build extra-index with the remaining repos (if any)
    $EXTRA_URLS = @()
    if ($REPOS.Count -gt 1) {
        foreach ($REPO in $REPOS[1..($REPOS.Count - 1)]) {
            $EXTRA_URLS += "https://aws:$AUTH_TOKEN@$DOMAIN-$DOMAIN_OWNER.d.codeartifact.$REGION.amazonaws.com/pypi/$REPO/simple/"
        }
    }

    Write-Host "Updating pip config..."
    pip config set --global global.index-url $MAIN_URL | Out-Null
    if ($EXTRA_URLS.Count -gt 0) {
        $extraValue = $EXTRA_URLS -join "`n"
        pip config set --global global.extra-index-url $extraValue | Out-Null
    } else {
        pip config unset --global global.extra-index-url | Out-Null
    }
    Write-Host "pip configured with repos: $($REPOS -join ', ')"

    if ($ENABLE_DEBUG_LOG) {
        Write-Host "pip config list --global:"
        pip config list --global
    }

    # Validate that the global pip.ini was updated
    $globalConfigPath = "C:\ProgramData\pip\pip.ini"
    if (Test-Path $globalConfigPath) {
        $content = Get-Content -Path $globalConfigPath -Raw
        if ($content -match [Regex]::Escape($DOMAIN)) {
            Write-Host "Global pip.ini updated: $globalConfigPath"
        } else {
            Write-Warning "Global pip.ini missing CodeArtifact URLs: $globalConfigPath"
        }
    } else {
        Write-Warning "Global pip.ini not found at $globalConfigPath"
    }
}
