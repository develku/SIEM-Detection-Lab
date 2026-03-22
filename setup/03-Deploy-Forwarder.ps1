#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures the Splunk Universal Forwarder on Windows endpoints.

.DESCRIPTION
    Deploys the Splunk Universal Forwarder (UF) to send endpoint logs to the
    Splunk SIEM server. The forwarder collects four critical log sources:

    - Sysmon (Operational)    — Process, network, file, and registry telemetry
    - Windows Security        — Authentication, privilege use, audit events
    - Windows System          — Service changes, driver loads, shutdowns
    - PowerShell ScriptBlock  — Full content of every PowerShell script executed

    The script is idempotent: it detects an existing installation and skips
    to configuration/verification if the forwarder is already present.

    NOTE: The Splunk Universal Forwarder MSI is not included in this repository.
    You must download it from https://www.splunk.com/en_us/download/universal-forwarder.html
    (requires a free Splunk account).

.PARAMETER InstallerPath
    Path to the Splunk Universal Forwarder MSI file.
    Defaults to .\splunkforwarder-*.msi in the script directory.

.PARAMETER SplunkServerIP
    IP address or hostname of the Splunk server receiving logs on port 9997.
    This is the Ubuntu server where 01-Install-Splunk.sh was run.

.PARAMETER ReceivingPort
    Port on which the Splunk server receives forwarded data.
    Default: 9997 (Splunk convention).

.PARAMETER AdminPassword
    Password for the local forwarder admin account. This is NOT the Splunk
    server admin password — it's used to manage the forwarder locally.
    Default: "Changeme123!" — change this in production.

.EXAMPLE
    .\03-Deploy-Forwarder.ps1 -SplunkServerIP "192.168.10.10"

.EXAMPLE
    .\03-Deploy-Forwarder.ps1 -SplunkServerIP "192.168.10.10" -InstallerPath "C:\Downloads\splunkforwarder-9.2.0-x64.msi"
#>

# Splunk Universal Forwarder (UF) — a lightweight agent that collects and forwards
# log data to a central Splunk instance. Unlike full Splunk, the UF has no search
# interface and minimal resource usage (~50 MB RAM), making it safe to deploy on
# production endpoints. It reads Windows Event Logs, monitors files, and ships
# everything to Splunk over an encrypted TCP connection (port 9997).

param(
    [Parameter(Mandatory = $false)]
    [string]$InstallerPath = "",

    [Parameter(Mandatory = $true)]
    [string]$SplunkServerIP,

    [Parameter(Mandatory = $false)]
    [int]$ReceivingPort = 9997,

    [Parameter(Mandatory = $false)]
    [string]$AdminPassword = "Changeme123!"
)

# ── Configuration ────────────────────────────────────────────────────────────
$SplunkUFHome = "C:\Program Files\SplunkUniversalForwarder"
$SplunkUFBin  = "$SplunkUFHome\bin\splunk.exe"

# ── Idempotency Check ───────────────────────────────────────────────────────
# Check if the Splunk Universal Forwarder is already installed by looking for
# both the service and the binary. If present, skip installation and proceed
# directly to configuration — this makes the script safe to re-run.
$ServiceExists = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue

if ($ServiceExists -and (Test-Path $SplunkUFBin)) {
    Write-Host "[*] Splunk Universal Forwarder is already installed." -ForegroundColor Cyan
    Write-Host "    Skipping installation, proceeding to configuration..." -ForegroundColor White
}
else {
    # ── Locate Installer ─────────────────────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        # Auto-detect: look for a splunkforwarder MSI in the script directory
        $SearchPath = Join-Path $PSScriptRoot "splunkforwarder-*.msi"
        $FoundMSI = Get-ChildItem -Path $SearchPath -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($FoundMSI) {
            $InstallerPath = $FoundMSI.FullName
        }
    }

    if ([string]::IsNullOrWhiteSpace($InstallerPath) -or -not (Test-Path $InstallerPath)) {
        Write-Host "[-] Splunk Universal Forwarder MSI not found." -ForegroundColor Red
        Write-Host "" -ForegroundColor White
        Write-Host "[i] The Universal Forwarder requires a free Splunk account to download." -ForegroundColor Yellow
        Write-Host "    Download from: https://www.splunk.com/en_us/download/universal-forwarder.html" -ForegroundColor White
        Write-Host "" -ForegroundColor White
        Write-Host "    Steps:" -ForegroundColor Yellow
        Write-Host "      1. Download the Windows 64-bit MSI installer" -ForegroundColor White
        Write-Host "      2. Place it in the same directory as this script, or use -InstallerPath" -ForegroundColor White
        Write-Host "      3. Re-run: .\03-Deploy-Forwarder.ps1 -SplunkServerIP '$SplunkServerIP'" -ForegroundColor White
        Write-Host "" -ForegroundColor White
        exit 1
    }

    Write-Host "[*] Installing Splunk Universal Forwarder..." -ForegroundColor Cyan
    Write-Host "    Installer: $InstallerPath" -ForegroundColor White
    Write-Host "    Target:    $SplunkUFHome" -ForegroundColor White

    # ── Install via MSI ──────────────────────────────────────────────────
    # msiexec /i runs the installer in "install" mode.
    # AGREETOLICENSE=yes    — silently accepts the Splunk EULA
    # RECEIVING_INDEXER      — tells the forwarder where to send data on first start
    # SPLUNKPASSWORD         — sets the local admin password for forwarder management
    # LAUNCHSPLUNK=0         — don't start yet; we configure inputs first
    # SERVICESTARTTYPE=auto  — start on boot; essential for continuous monitoring
    # /quiet                 — no GUI, required for scripted installs
    $MSIArgs = @(
        "/i", "`"$InstallerPath`"",
        "AGREETOLICENSE=yes",
        "RECEIVING_INDEXER=`"${SplunkServerIP}:${ReceivingPort}`"",
        "SPLUNKPASSWORD=`"$AdminPassword`"",
        "LAUNCHSPLUNK=0",
        "SERVICESTARTTYPE=auto",
        "/quiet"
    )

    Write-Host "[*] Running installer (this may take 1-2 minutes)..." -ForegroundColor Cyan
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $MSIArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "[-] Installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        Write-Host "    Check the MSI log: %TEMP%\MSI*.LOG" -ForegroundColor Yellow
        exit 1
    }

    # Verify the binary was installed
    if (-not (Test-Path $SplunkUFBin)) {
        Write-Host "[-] Installation completed but splunk.exe not found at expected path." -ForegroundColor Red
        Write-Host "    Expected: $SplunkUFBin" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[+] Splunk Universal Forwarder installed successfully." -ForegroundColor Green
}

# ── Configure outputs.conf ──────────────────────────────────────────────────
# outputs.conf tells the forwarder WHERE to send data. The [tcpout] stanza
# defines the target Splunk indexer(s). In a production environment, you'd
# have multiple indexers for redundancy — in our lab, it's a single server.
Write-Host "[*] Configuring outputs.conf (forwarding target: ${SplunkServerIP}:${ReceivingPort})..." -ForegroundColor Cyan

$OutputsDir = "$SplunkUFHome\etc\system\local"
if (-not (Test-Path $OutputsDir)) {
    New-Item -ItemType Directory -Path $OutputsDir -Force | Out-Null
}

# defaultGroup — the forwarder will send all data to servers in this group.
# server — the IP:port of the receiving Splunk instance.
# useACK — when enabled, the forwarder waits for the indexer to acknowledge
# receipt before removing data from its internal queue. This prevents data
# loss if the indexer is temporarily unavailable. Critical for reliability.
$OutputsConf = @"
# outputs.conf — Splunk Universal Forwarder output configuration
# Generated by 03-Deploy-Forwarder.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Sends all collected data to the Splunk server for indexing and search.

[tcpout]
defaultGroup = lab-indexer

[tcpout:lab-indexer]
server = ${SplunkServerIP}:${ReceivingPort}

# useACK — indexer acknowledgment. The forwarder keeps data in its retry queue
# until the indexer confirms it was received and written to disk. Without this,
# data could be lost during network interruptions or indexer restarts.
useACK = true
"@

Set-Content -Path "$OutputsDir\outputs.conf" -Value $OutputsConf -Encoding UTF8
Write-Host "[+] outputs.conf configured." -ForegroundColor Green

# ── Configure inputs.conf ───────────────────────────────────────────────────
# inputs.conf tells the forwarder WHAT data to collect. Each [WinEventLog:...]
# stanza subscribes to a Windows Event Log channel. The forwarder reads new
# events as they're written and forwards them to Splunk.
Write-Host "[*] Configuring inputs.conf (log sources)..." -ForegroundColor Cyan

# Why these four log sources?
#
# 1. Sysmon/Operational — the single most valuable log source for threat detection.
#    Provides process creation with command lines (Event ID 1), network connections
#    (ID 3), file creation (ID 11), registry changes (ID 13), DNS queries (ID 22),
#    and process access patterns (ID 10, used to detect LSASS dumping).
#
# 2. Security — Windows authentication and audit events. Includes logon success/
#    failure (4624/4625), account lockout (4740), privilege escalation (4672/4673),
#    security group changes (4728/4732), and audit policy changes (4719).
#    Essential for detecting brute force, lateral movement, and persistence.
#
# 3. System — records service installations (7045), driver loads, and system
#    state changes. Attackers frequently install malicious services for
#    persistence (T1543.003) or load vulnerable drivers for kernel exploitation.
#
# 4. PowerShell ScriptBlock — logs the full deobfuscated content of every
#    PowerShell script that executes (Event ID 4104). This defeats obfuscation
#    techniques like Base64 encoding, string concatenation, and variable
#    substitution — you see the final executed code, not the obfuscated wrapper.
#    Without this, "powershell -enc SQBuAHYAbwBrAGUA..." is opaque to analysts.

$InputsConf = @"
# inputs.conf — Splunk Universal Forwarder input configuration
# Generated by 03-Deploy-Forwarder.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Collects security-relevant Windows Event Logs for SIEM analysis.

# ── Sysmon (System Monitor) ──────────────────────────────────────────────────
# The most critical log source for endpoint detection. Sysmon hooks into the
# Windows kernel and generates high-fidelity telemetry that native logging misses.
# renderXml=true sends the full XML event, which preserves all fields for Splunk
# field extraction — without it, some nested fields are lost.
[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = false
index = sysmon
sourcetype = XmlWinEventLog:Microsoft-Windows-Sysmon/Operational
renderXml = true
# checkpointInterval — how often (in seconds) the forwarder saves its read position.
# If the forwarder restarts, it resumes from the last checkpoint instead of
# re-reading the entire log. 5 seconds balances reliability with disk I/O.
checkpointInterval = 5

# ── Windows Security Log ─────────────────────────────────────────────────────
# Contains authentication events, privilege use, object access, and policy changes.
# This is the log that records who logged in, failed login attempts, and security-
# sensitive operations like password resets and group membership changes.
[WinEventLog://Security]
disabled = false
index = wineventlog
sourcetype = WinEventLog:Security
renderXml = true
checkpointInterval = 5

# ── Windows System Log ───────────────────────────────────────────────────────
# Records service state changes, driver loads, time synchronization, and system
# errors. SOC-relevant events include service installations (7045 — often used
# for persistence) and unexpected shutdowns that may indicate tampering.
[WinEventLog://System]
disabled = false
index = wineventlog
sourcetype = WinEventLog:System
renderXml = true
checkpointInterval = 5

# ── PowerShell ScriptBlock Logging ───────────────────────────────────────────
# Captures the full text of every PowerShell script block that executes on the
# system. This is the deobfuscated/final form of the code, so even heavily
# obfuscated attack scripts are logged in readable plaintext.
#
# Requires GPO/registry: ScriptBlockLogging must be enabled on the endpoint.
# See AD-Lab-Setup/scripts/05-Configure-GPOs.ps1 for the policy configuration.
[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = false
index = powershell
sourcetype = XmlWinEventLog:Microsoft-Windows-PowerShell/Operational
renderXml = true
checkpointInterval = 5

# ── PowerShell Classic Logging (Windows PowerShell channel) ──────────────────
# The legacy PowerShell event log. Captures engine start/stop (Event ID 400/403)
# and pipeline execution (800). Less detailed than ScriptBlock logging but still
# useful for seeing when PowerShell was invoked and with what host application.
[WinEventLog://Windows PowerShell]
disabled = false
index = powershell
sourcetype = WinEventLog:Windows PowerShell
renderXml = true
checkpointInterval = 5
"@

Set-Content -Path "$OutputsDir\inputs.conf" -Value $InputsConf -Encoding UTF8
Write-Host "[+] inputs.conf configured with 5 log sources." -ForegroundColor Green

# ── Start/Restart the Forwarder Service ─────────────────────────────────────
# After changing configs, the forwarder service needs to restart to pick up
# the new inputs.conf and outputs.conf settings.
Write-Host "[*] Starting Splunk Universal Forwarder service..." -ForegroundColor Cyan

$Service = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue
if ($Service) {
    if ($Service.Status -eq "Running") {
        Write-Host "[*] Service is running. Restarting to apply configuration..." -ForegroundColor Cyan
        Restart-Service -Name "SplunkForwarder" -Force
    }
    else {
        Start-Service -Name "SplunkForwarder"
    }

    # Wait for the service to reach Running state
    $timeout = 30
    $elapsed = 0
    while ((Get-Service -Name "SplunkForwarder").Status -ne "Running" -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    $Service = Get-Service -Name "SplunkForwarder"
    if ($Service.Status -eq "Running") {
        Write-Host "[+] SplunkForwarder service is Running." -ForegroundColor Green
    }
    else {
        Write-Host "[-] Service did not start within $timeout seconds. Status: $($Service.Status)" -ForegroundColor Red
        Write-Host "    Check logs at: $SplunkUFHome\var\log\splunk\splunkd.log" -ForegroundColor Yellow
        exit 1
    }
}
else {
    Write-Host "[-] SplunkForwarder service not found. Installation may have failed." -ForegroundColor Red
    exit 1
}

# ── Verify Forwarding ──────────────────────────────────────────────────────
Write-Host "`n[*] Verifying forwarder configuration..." -ForegroundColor Cyan

# Check that the forwarder knows its target server
Write-Host "[*] Forwarding target:" -ForegroundColor Cyan
& $SplunkUFBin list forward-server -auth "admin:$AdminPassword" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] Forward server list retrieved." -ForegroundColor Green
}
else {
    Write-Host "[!] Could not query forward server list (may need a moment to initialize)." -ForegroundColor Yellow
}

# Verify monitored inputs are active
Write-Host "[*] Active inputs:" -ForegroundColor Cyan
& $SplunkUFBin list inputstatus -auth "admin:$AdminPassword" 2>$null | Select-Object -First 30
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Could not query input status." -ForegroundColor Yellow
}

# Quick connectivity test — attempt a TCP connection to the Splunk server
# to verify network reachability before the user has to debug later.
Write-Host "[*] Testing connectivity to ${SplunkServerIP}:${ReceivingPort}..." -ForegroundColor Cyan
$tcpTest = Test-NetConnection -ComputerName $SplunkServerIP -Port $ReceivingPort -WarningAction SilentlyContinue
if ($tcpTest.TcpTestSucceeded) {
    Write-Host "[+] Successfully connected to ${SplunkServerIP}:${ReceivingPort}" -ForegroundColor Green
}
else {
    Write-Host "[!] Cannot reach ${SplunkServerIP}:${ReceivingPort}" -ForegroundColor Yellow
    Write-Host "    Possible causes:" -ForegroundColor Yellow
    Write-Host "      - Splunk server is not running" -ForegroundColor White
    Write-Host "      - Firewall is blocking port $ReceivingPort" -ForegroundColor White
    Write-Host "      - Incorrect IP address" -ForegroundColor White
    Write-Host "    Logs will be queued locally and forwarded when connectivity is restored." -ForegroundColor White
}

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n[*] ═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "[*]  Splunk Universal Forwarder Deployment Complete" -ForegroundColor Cyan
Write-Host "[*] ═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "[*]  Forwarding to:     ${SplunkServerIP}:${ReceivingPort}" -ForegroundColor Cyan
Write-Host "[*]  Install path:      $SplunkUFHome" -ForegroundColor Cyan
Write-Host "[*]  Service:           SplunkForwarder ($((Get-Service SplunkForwarder).Status))" -ForegroundColor Cyan
Write-Host ""
Write-Host "[*]  Log sources configured:" -ForegroundColor Cyan
Write-Host "       - Sysmon/Operational          → index=sysmon" -ForegroundColor White
Write-Host "       - Windows Security             → index=wineventlog" -ForegroundColor White
Write-Host "       - Windows System               → index=wineventlog" -ForegroundColor White
Write-Host "       - PowerShell/Operational        → index=powershell" -ForegroundColor White
Write-Host "       - Windows PowerShell (classic)  → index=powershell" -ForegroundColor White
Write-Host ""
Write-Host "[*]  Verify in Splunk Web:" -ForegroundColor Cyan
Write-Host "       1. Go to Settings → Forwarding and Receiving → Forwarders" -ForegroundColor White
Write-Host "       2. Search: index=sysmon | stats count by host" -ForegroundColor White
Write-Host "       3. Search: index=wineventlog | stats count by source" -ForegroundColor White
Write-Host ""
Write-Host "[*]  Logs:  $SplunkUFHome\var\log\splunk\splunkd.log" -ForegroundColor Cyan
Write-Host "[*] ═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
