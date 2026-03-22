#!/bin/bash
set -euo pipefail

# ============================================================================
# 01-Install-Splunk.sh — Install Splunk Free on Ubuntu Server
# ============================================================================
#
# Installs and configures Splunk Enterprise (Free license) as the central
# SIEM log collector for the detection lab. Splunk will receive forwarded
# logs from Windows endpoints via Universal Forwarders on port 9997 and
# serve the web search interface on port 8000.
#
# Prerequisites:
#   - Ubuntu Server 22.04 or 24.04 (tested)
#   - Minimum 4 GB RAM (8 GB recommended for lab workloads)
#   - Minimum 20 GB free disk space
#   - Splunk .deb package downloaded from splunk.com (requires free account)
#
# Usage:
#   sudo SPLUNK_ADMIN_PASSWORD='YourPassword123!' bash 01-Install-Splunk.sh
#
#   Or place the .deb in the same directory as this script:
#   sudo SPLUNK_ADMIN_PASSWORD='...' SPLUNK_DEB=./splunk-9.x.x-linux-amd64.deb bash 01-Install-Splunk.sh
#
# Why Splunk Free?
#   Splunk Free allows up to 500 MB/day of indexing, which is more than enough
#   for a home lab with a handful of endpoints. It provides the same search
#   and analytics engine as Splunk Enterprise, minus features like
#   authentication, alerting, and distributed search — none of which are
#   needed for a learning lab.
# ============================================================================

# ── Helper Functions ─────────────────────────────────────────────────────────
# Colored output makes it easy to scan script progress in a terminal.
# Convention: [*] info, [+] success, [!] warning, [-] error — matches the
# PowerShell scripts in the AD-Lab-Setup companion repo.
info()  { echo -e "\033[1;36m[*]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[+]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[!]\033[0m $*"; }
error() { echo -e "\033[1;31m[-]\033[0m $*"; exit 1; }

# ── Configuration ────────────────────────────────────────────────────────────
SPLUNK_HOME="/opt/splunk"
SPLUNK_USER="splunk"

# SPLUNK_DEB — path to the Splunk .deb installer.
# Splunk requires a free account to download, so we can't auto-fetch it.
# The user must download it from https://www.splunk.com/en_us/download.html
# and either place it alongside this script or set the SPLUNK_DEB env var.
SPLUNK_DEB="${SPLUNK_DEB:-}"

# SPLUNK_ADMIN_PASSWORD — the admin password for the Splunk web UI.
# Must be at least 8 characters. Passed via environment variable so it never
# appears in command history or process listings.
SPLUNK_ADMIN_PASSWORD="${SPLUNK_ADMIN_PASSWORD:-}"

# ── Pre-flight Checks ───────────────────────────────────────────────────────
info "Running pre-flight checks..."

# Root/sudo check — Splunk installation requires writing to /opt and creating
# system services. These operations require root privileges.
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Use: sudo bash $0"
fi

# OS check — this script uses apt/dpkg and systemd, which are specific to
# Debian/Ubuntu. Running on CentOS/RHEL would require different commands.
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        warn "This script is designed for Ubuntu. Detected: $ID $VERSION_ID"
        warn "Proceeding anyway, but some commands may not work."
    else
        ok "Operating system: Ubuntu $VERSION_ID"
    fi
else
    warn "Cannot detect OS version. Proceeding anyway."
fi

# RAM check — Splunk's search process (splunkd) is memory-intensive. With less
# than 4 GB, searches will be slow and the system may swap heavily, especially
# when parsing Windows event logs with complex field extractions.
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
if [[ $TOTAL_RAM_MB -lt 3800 ]]; then
    warn "Only ${TOTAL_RAM_MB} MB RAM detected. Splunk recommends at least 4 GB."
    warn "The lab will work but search performance may be degraded."
else
    ok "RAM: ${TOTAL_RAM_MB} MB"
fi

# Disk check — Splunk indexes are stored in $SPLUNK_HOME/var/lib/splunk.
# A single Windows endpoint generating Sysmon, Security, System, and PowerShell
# logs will produce roughly 50-200 MB/day depending on activity. 20 GB gives
# comfortable room for several weeks of lab data plus Splunk's internal indexes.
DISK_FREE_GB=$(df -BG /opt | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ $DISK_FREE_GB -lt 20 ]]; then
    warn "Only ${DISK_FREE_GB} GB free on /opt. Recommend at least 20 GB."
else
    ok "Disk space: ${DISK_FREE_GB} GB free on /opt"
fi

# Admin password — enforcing a minimum length prevents accidentally starting
# Splunk with an empty or trivially short password. Splunk itself requires 8+.
if [[ -z "$SPLUNK_ADMIN_PASSWORD" ]]; then
    error "SPLUNK_ADMIN_PASSWORD is not set. Usage: sudo SPLUNK_ADMIN_PASSWORD='YourPassword' bash $0"
fi

if [[ ${#SPLUNK_ADMIN_PASSWORD} -lt 8 ]]; then
    error "SPLUNK_ADMIN_PASSWORD must be at least 8 characters."
fi

ok "Admin password is set (${#SPLUNK_ADMIN_PASSWORD} characters)"

# ── Idempotency Check ───────────────────────────────────────────────────────
# If Splunk is already installed and running, skip the installation steps.
# This lets the user safely re-run the script without breaking anything —
# important in a lab where you might tweak and re-run setup scripts.
if [[ -x "$SPLUNK_HOME/bin/splunk" ]]; then
    if "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "is running"; then
        ok "Splunk is already installed and running."
        info "Splunk Web: http://$(hostname -I | awk '{print $1}'):8000"
        info "Receiving port: 9997"
        info "To reconfigure, stop Splunk first: $SPLUNK_HOME/bin/splunk stop"
        exit 0
    else
        warn "Splunk is installed but not running. Will attempt to start it."
    fi
fi

# ── Locate Splunk .deb Package ──────────────────────────────────────────────
# Splunk requires a login to download (even the free version), so we can't
# use wget/curl to fetch it automatically. The user must download the .deb
# from splunk.com and provide the path.
if [[ -z "$SPLUNK_DEB" ]]; then
    # Auto-detect: look for a splunk .deb file in the same directory as this script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SPLUNK_DEB=$(find "$SCRIPT_DIR" -maxdepth 1 -name "splunk-*.deb" -type f 2>/dev/null | head -1)
fi

if [[ -z "$SPLUNK_DEB" || ! -f "$SPLUNK_DEB" ]]; then
    error "Splunk .deb package not found.

    Splunk requires a free account to download. Please:
      1. Go to https://www.splunk.com/en_us/download/splunk-enterprise.html
      2. Create a free account (or log in)
      3. Download the .deb package for Linux (64-bit)
      4. Place it in the same directory as this script, or set:
         export SPLUNK_DEB=/path/to/splunk-9.x.x-linux-amd64.deb

    Then re-run this script."
fi

ok "Found Splunk installer: $SPLUNK_DEB"

# ── Install Dependencies ────────────────────────────────────────────────────
# Splunk requires minimal dependencies, but we ensure these are present:
# - wget/curl: for later downloading apps or updates
# - net-tools: for netstat, used to verify listening ports
info "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq net-tools > /dev/null 2>&1
ok "Dependencies installed."

# ── Create Splunk User ──────────────────────────────────────────────────────
# Running Splunk as root is a security risk — if Splunk is compromised, the
# attacker gets root. A dedicated low-privilege user limits the blast radius.
# In a production SOC, this is a mandatory security control.
if ! id "$SPLUNK_USER" &>/dev/null; then
    info "Creating dedicated splunk user..."
    useradd -m -r -s /bin/bash "$SPLUNK_USER"
    ok "Created user: $SPLUNK_USER"
else
    ok "User $SPLUNK_USER already exists."
fi

# ── Install Splunk ──────────────────────────────────────────────────────────
# dpkg installs the .deb package to /opt/splunk. The -i flag means "install".
# Splunk ships as a self-contained package — it doesn't use system Python or
# other shared libraries, which avoids dependency conflicts.
info "Installing Splunk from $SPLUNK_DEB ..."
dpkg -i "$SPLUNK_DEB"
ok "Splunk package installed to $SPLUNK_HOME"

# Set ownership — the splunk user needs to own all files under /opt/splunk
# so it can read configs, write to indexes, and manage its own pid files.
chown -R "$SPLUNK_USER":"$SPLUNK_USER" "$SPLUNK_HOME"

# ── Accept License & Set Admin Credentials ──────────────────────────────────
# --accept-license: Splunk requires explicit license acceptance. Without this
# flag, it prompts interactively, which breaks unattended installs.
#
# --seed-passwd: Sets the admin password on first start. This is the only
# supported way to set the initial password non-interactively. The password
# is written to $SPLUNK_HOME/etc/system/local/user-seed.conf and consumed
# on first boot, then the file is deleted automatically.
#
# --no-prompt: Prevents any interactive prompts during startup.
info "Starting Splunk for the first time (accepting license, setting admin password)..."
sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" start \
    --accept-license \
    --answer-yes \
    --no-prompt \
    --seed-passwd "$SPLUNK_ADMIN_PASSWORD"
ok "Splunk started successfully."

# ── Enable Boot Start ──────────────────────────────────────────────────────
# Creates a systemd unit so Splunk starts automatically on reboot. In a lab,
# this means you don't have to manually start Splunk every time the VM boots.
# -systemd-managed 1: uses systemd (modern) instead of init.d (legacy).
info "Enabling Splunk to start on boot..."
"$SPLUNK_HOME/bin/splunk" enable boot-start -user "$SPLUNK_USER" -systemd-managed 1
ok "Boot-start enabled (systemd)."

# ── Configure Receiving Port (9997) ─────────────────────────────────────────
# Port 9997 is Splunk's default data receiving port. Universal Forwarders on
# Windows endpoints will send their logs to this port using Splunk's
# proprietary S2S (Splunk-to-Splunk) protocol.
#
# Why 9997? It's Splunk's convention — all documentation and default configs
# use it. Using a standard port means less custom configuration on forwarders
# and easier troubleshooting.
info "Enabling receiving on port 9997..."
sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" enable listen 9997 \
    -auth "admin:$SPLUNK_ADMIN_PASSWORD"
ok "Listening on port 9997 for forwarder data."

# ── Configure Firewall ──────────────────────────────────────────────────────
# Open ports for Splunk Web (8000) and forwarder data (9997). If ufw is not
# active, these commands are harmless no-ops.
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    info "Configuring firewall rules..."
    ufw allow 8000/tcp comment "Splunk Web UI"
    ufw allow 9997/tcp comment "Splunk Forwarder Receiving"
    ok "Firewall rules added."
else
    warn "UFW is not active. Ensure ports 8000 and 9997 are accessible."
    warn "If using VirtualBox/VMware, check your VM network adapter settings."
fi

# ── Verify Installation ────────────────────────────────────────────────────
info "Verifying Splunk installation..."

# Check that splunkd is running
if "$SPLUNK_HOME/bin/splunk" status | grep -q "is running"; then
    ok "splunkd is running."
else
    error "splunkd is NOT running. Check logs at $SPLUNK_HOME/var/log/splunk/splunkd.log"
fi

# Verify port 9997 is listening — confirms forwarders can connect
if netstat -tlnp 2>/dev/null | grep -q ":9997"; then
    ok "Port 9997 is listening (forwarder receiving)."
else
    warn "Port 9997 does not appear to be listening. Check Splunk inputs config."
fi

# Verify port 8000 is listening — confirms web UI is accessible
if netstat -tlnp 2>/dev/null | grep -q ":8000"; then
    ok "Port 8000 is listening (web interface)."
else
    warn "Port 8000 does not appear to be listening. Check Splunk web config."
fi

# ── Summary ─────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
info "═══════════════════════════════════════════════════════════════"
info " Splunk Installation Complete"
info "═══════════════════════════════════════════════════════════════"
echo ""
info " Web Interface:     http://${SERVER_IP}:8000"
info " Username:          admin"
info " Receiving Port:    9997 (for Universal Forwarders)"
info " Install Path:      $SPLUNK_HOME"
info " Runs As:           $SPLUNK_USER"
info " Logs:              $SPLUNK_HOME/var/log/splunk/"
echo ""
info " Next Steps:"
info "   1. Open http://${SERVER_IP}:8000 in a browser"
info "   2. Log in with admin / <your password>"
info "   3. Run 02-Configure-Inputs.sh to set up indexes and inputs"
info "   4. Run 03-Deploy-Forwarder.ps1 on Windows endpoints"
echo ""
info "═══════════════════════════════════════════════════════════════"
