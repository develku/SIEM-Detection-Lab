#!/bin/bash
set -euo pipefail

# ============================================================================
# 02-Configure-Inputs.sh — Configure Splunk Indexes and Input Processing
# ============================================================================
#
# Deploys the Splunk configuration files (inputs.conf, props.conf,
# transforms.conf) that tell Splunk how to receive, parse, and route
# incoming log data from Windows endpoints.
#
# This script creates three custom indexes:
#   - sysmon:      Sysmon process/network/file telemetry (Event IDs 1-26)
#   - wineventlog: Windows Security, System, and Application logs
#   - powershell:  PowerShell ScriptBlock and Module logging
#
# Why separate indexes?
#   Indexes are Splunk's primary data containers. Separating log types into
#   dedicated indexes provides three benefits:
#   1. Search performance — "index=sysmon" scans only Sysmon data, not all logs
#   2. Retention control — keep Sysmon data for 90 days but Security logs for 30
#   3. Access control — in enterprise Splunk, you can restrict who sees what
#
# Prerequisites:
#   - 01-Install-Splunk.sh has been run successfully
#   - Splunk is running
#
# Usage:
#   sudo bash 02-Configure-Inputs.sh
# ============================================================================

# ── Helper Functions ─────────────────────────────────────────────────────────
info()  { echo -e "\033[1;36m[*]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[+]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[!]\033[0m $*"; }
error() { echo -e "\033[1;31m[-]\033[0m $*"; exit 1; }

# ── Configuration ────────────────────────────────────────────────────────────
SPLUNK_HOME="/opt/splunk"
SPLUNK_USER="splunk"

# Path to the config files shipped with this repository.
# These are maintained in configs/ at the repository root and contain the
# parsing rules, field extractions, and routing logic for our lab's log sources.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$REPO_ROOT/configs"

# Splunk reads configs from a priority chain. "system/local" is the highest
# priority location that persists across upgrades. We deploy there so our
# configs always win over defaults and aren't overwritten by Splunk updates.
SPLUNK_SYSTEM_LOCAL="$SPLUNK_HOME/etc/system/local"

# SPLUNK_ADMIN_PASSWORD — needed for CLI commands that require authentication.
SPLUNK_ADMIN_PASSWORD="${SPLUNK_ADMIN_PASSWORD:-}"

# ── Pre-flight Checks ───────────────────────────────────────────────────────
info "Running pre-flight checks..."

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Use: sudo bash $0"
fi

if [[ ! -x "$SPLUNK_HOME/bin/splunk" ]]; then
    error "Splunk is not installed at $SPLUNK_HOME. Run 01-Install-Splunk.sh first."
fi

if ! "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "is running"; then
    error "Splunk is not running. Start it with: $SPLUNK_HOME/bin/splunk start"
fi

ok "Splunk is installed and running."

# Prompt for password if not set via environment variable
if [[ -z "$SPLUNK_ADMIN_PASSWORD" ]]; then
    read -s -p "[*] Enter Splunk admin password: " SPLUNK_ADMIN_PASSWORD
    echo ""
    if [[ -z "$SPLUNK_ADMIN_PASSWORD" ]]; then
        error "Password cannot be empty."
    fi
fi

# Verify the config source files exist
for conf_file in inputs.conf props.conf transforms.conf; do
    if [[ ! -f "$CONFIGS_DIR/$conf_file" ]]; then
        error "Config file not found: $CONFIGS_DIR/$conf_file"
    fi
done
ok "All configuration files found in $CONFIGS_DIR"

# ── Create Custom Indexes ───────────────────────────────────────────────────
# Each index is a separate data store on disk. Splunk creates the directories,
# database files, and metadata automatically. We set practical retention
# limits so the lab VM's disk doesn't fill up.
info "Creating custom indexes..."

create_index() {
    local index_name="$1"
    local max_size_mb="${2:-10240}"  # Default 10 GB max per index

    # Check if the index already exists (idempotent)
    if sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" list index \
        -auth "admin:$SPLUNK_ADMIN_PASSWORD" 2>/dev/null | grep -q "^$index_name\b"; then
        ok "Index '$index_name' already exists."
    else
        sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" add index "$index_name" \
            -maxTotalDataSizeMB "$max_size_mb" \
            -auth "admin:$SPLUNK_ADMIN_PASSWORD"
        ok "Created index: $index_name (max ${max_size_mb} MB)"
    fi
}

# sysmon — stores Sysmon event logs (Event IDs 1-26). Sysmon is the highest-value
# log source for threat detection because it captures process creation with full
# command lines, network connections, file creation timestamps, and more.
create_index "sysmon" 10240

# wineventlog — stores Windows Security (4624, 4625, 4688, etc.), System, and
# Application event logs. These are the bread-and-butter logs for authentication
# monitoring, account lockout investigation, and service change tracking.
create_index "wineventlog" 10240

# powershell — stores PowerShell ScriptBlock logging (Event ID 4104) and Module
# logging. PowerShell is the most common attack tool on Windows — attackers use
# it for downloading payloads, lateral movement, and credential theft. Logging
# the actual script content (not just "powershell.exe ran") is critical for
# forensic analysis.
create_index "powershell" 5120

# ── Deploy Configuration Files ──────────────────────────────────────────────
# These config files work together as a pipeline:
#   1. inputs.conf — defines what data Splunk accepts and on which ports
#   2. props.conf  — defines how to parse incoming data (sourcetype rules)
#   3. transforms.conf — routes parsed data to the correct index
info "Deploying configuration files..."

# Back up any existing configs before overwriting. In a lab this is extra
# cautious, but it's a good habit to carry into production work.
BACKUP_DIR="$SPLUNK_HOME/etc/system/local/backup_$(date +%Y%m%d_%H%M%S)"
BACKED_UP=false
for conf_file in inputs.conf props.conf transforms.conf; do
    if [[ -f "$SPLUNK_SYSTEM_LOCAL/$conf_file" ]]; then
        if [[ "$BACKED_UP" == false ]]; then
            mkdir -p "$BACKUP_DIR"
            BACKED_UP=true
            info "Backing up existing configs to $BACKUP_DIR"
        fi
        cp "$SPLUNK_SYSTEM_LOCAL/$conf_file" "$BACKUP_DIR/$conf_file"
        ok "Backed up: $conf_file"
    fi
done

# Copy each config file into Splunk's system/local directory
for conf_file in inputs.conf props.conf transforms.conf; do
    cp "$CONFIGS_DIR/$conf_file" "$SPLUNK_SYSTEM_LOCAL/$conf_file"
    ok "Deployed: $conf_file → $SPLUNK_SYSTEM_LOCAL/$conf_file"
done

# Fix ownership — Splunk reads configs as the splunk user, so these files
# must be owned by that user or splunkd won't be able to read them.
chown -R "$SPLUNK_USER":"$SPLUNK_USER" "$SPLUNK_SYSTEM_LOCAL"
ok "File ownership set to $SPLUNK_USER."

# ── Restart Splunk ──────────────────────────────────────────────────────────
# Splunk reads most config files at startup. Changes to inputs.conf,
# props.conf, and transforms.conf require a restart to take effect.
# (Some changes can be applied with "splunk reload", but a full restart
# is more reliable and ensures all config changes are picked up.)
info "Restarting Splunk to apply configuration changes..."
sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" restart
ok "Splunk restarted."

# ── Verify Configuration ───────────────────────────────────────────────────
info "Verifying configuration..."

# Verify indexes exist and are searchable
for idx in sysmon wineventlog powershell; do
    if sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" list index \
        -auth "admin:$SPLUNK_ADMIN_PASSWORD" 2>/dev/null | grep -q "^${idx}\b"; then
        ok "Index verified: $idx"
    else
        warn "Index not found: $idx — check $SPLUNK_HOME/var/log/splunk/splunkd.log"
    fi
done

# Verify the receiving port is still active after restart
if netstat -tlnp 2>/dev/null | grep -q ":9997"; then
    ok "Port 9997 is listening (forwarder receiving)."
else
    warn "Port 9997 is not listening. Check inputs.conf configuration."
fi

# List active inputs so the user can confirm what Splunk is accepting
info "Active inputs:"
sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" list forward-server \
    -auth "admin:$SPLUNK_ADMIN_PASSWORD" 2>/dev/null || true
sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" list inputstatus \
    -auth "admin:$SPLUNK_ADMIN_PASSWORD" 2>/dev/null | head -20 || true

# ── Summary ─────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
info "═══════════════════════════════════════════════════════════════"
info " Splunk Input Configuration Complete"
info "═══════════════════════════════════════════════════════════════"
echo ""
info " Indexes created:"
info "   - sysmon       → Sysmon endpoint telemetry"
info "   - wineventlog  → Windows Security/System/Application logs"
info "   - powershell   → PowerShell ScriptBlock and Module logs"
echo ""
info " Configs deployed:"
info "   - inputs.conf     → Data receiving on port 9997"
info "   - props.conf      → Field extraction and parsing rules"
info "   - transforms.conf → Log routing to correct indexes"
echo ""
info " Verify in Splunk Web:"
info "   1. Go to http://${SERVER_IP}:8000"
info "   2. Settings → Indexes — confirm sysmon, wineventlog, powershell exist"
info "   3. Settings → Forwarding and Receiving → Receive data → confirm 9997"
echo ""
info " Next Step:"
info "   Run 03-Deploy-Forwarder.ps1 on each Windows endpoint"
echo ""
info "═══════════════════════════════════════════════════════════════"
