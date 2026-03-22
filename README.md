# SIEM Detection Lab

Splunk-based SIEM infrastructure for security monitoring. Automated deployment with Docker Compose, scripted forwarder setup, and a complete log ingestion pipeline from Windows endpoints.

Integrates with [AD-Lab-Setup](https://github.com/develku/AD-Lab-Setup) for endpoint infrastructure. Detection rules and attack scenarios are in their own repos — see [Related Projects](#related-projects).

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     AD-Lab Infrastructure                     │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │  Windows DC   │    │  Windows 10  │    │  Windows 10  │   │
│  │ (Server 2022) │    │  (Target 1)  │    │  (Target 2)  │   │
│  │  + Sysmon     │    │  + Sysmon    │    │  + Sysmon    │   │
│  │  + Splunk UF  │    │  + Splunk UF │    │  + Splunk UF │   │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘   │
│         │    TCP:9997       │                    │            │
│         └───────────────────┼────────────────────┘            │
│                             │                                │
└─────────────────────────────┼────────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Splunk Server   │
                    │   (Ubuntu VM)     │
                    │                   │
                    │  • Indexer        │
                    │  • Search Head    │
                    │  • Alert Pipeline │
                    └───────────────────┘
```

## What This Demonstrates

| Skill | Implementation |
|---|---|
| **SIEM Deployment** | Splunk Free with automated setup scripts, Docker Compose, index configuration |
| **Log Pipeline** | Universal Forwarder deployment, Sysmon + Windows Security + PowerShell log collection |
| **Log Analysis** | Windows Security, Sysmon, PowerShell, System logs — 30+ event IDs ingested |
| **Infrastructure as Code** | Docker Compose for repeatable Splunk deployment, scripted forwarder install |

## Quick Start

### Prerequisites

- [AD-Lab-Setup](https://github.com/develku/AD-Lab-Setup) deployed (DC + workstations with Sysmon)
- **Docker Compose** (recommended) or **Ubuntu Server VM** for Splunk — see [Setup Guide](docs/01-Splunk-Setup.md)

### Step 1: Deploy Splunk Server

**Option A: Docker Compose (recommended — works on any OS/architecture)**
```bash
cp .env.example .env          # Edit .env to set your password
docker compose up -d           # Start Splunk (1 command, ~2 minutes)
```

**Option B: Manual Install (Ubuntu Server)**
```bash
sudo SPLUNK_ADMIN_PASSWORD='YourPassword' ./setup/01-Install-Splunk.sh
sudo ./setup/02-Configure-Inputs.sh
```

See [01-Splunk-Setup.md](docs/01-Splunk-Setup.md) for detailed instructions on both methods.

### Step 2: Deploy Forwarders on Windows Endpoints

```powershell
# On each Windows VM in the AD-Lab (run as Administrator)
.\setup\03-Deploy-Forwarder.ps1 -SplunkServerIP "192.168.10.10" -InstallerPath ".\splunkforwarder.msi"
```

### Step 3: Verify Log Ingestion

1. Open Splunk Web at `http://localhost:8000` (Docker) or `http://<splunk-server>:8000` (manual)
2. Run `index=sysmon | stats count by Computer` to verify endpoints are reporting
3. Check [Log Sources](docs/02-Log-Sources.md) for verification queries per log type

### Next Steps

Once the infrastructure is running:
- Load detection rules from [Detection-Engineering-Lab](https://github.com/develku/Detection-Engineering-Lab)
- Run attack scenarios from [Attack-Simulation-Lab](https://github.com/develku/Attack-Simulation-Lab)

## Study Path (For Learners)

```
Step 1          Step 2          Step 3           Step 4          Step 5
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ Learn    │──▶│ Build    │──▶│ Detect   │──▶│ Attack   │──▶│ Tune     │
│ Concepts │   │ the Lab  │   │ Threats  │   │ & Hunt   │   │ & Report │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
```

| Step | What To Do | Guide |
|---|---|---|
| 1 | **Learn the concepts** — Understand what a SIEM is, how Sysmon works, what MITRE ATT&CK means | [Learning Guide](docs/00-Learning-Guide.md) + [Glossary](docs/GLOSSARY.md) |
| 2 | **Build the lab** — Deploy Splunk, configure forwarders, verify log ingestion | [Splunk Setup](docs/01-Splunk-Setup.md) |
| 3 | **Understand your data** — Study each log source, learn critical Event IDs | [Log Sources](docs/02-Log-Sources.md) |
| 4 | **Study detection rules** — Read each rule, understand SPL syntax and what it catches | [Detection-Engineering-Lab](https://github.com/develku/Detection-Engineering-Lab) |
| 5 | **Run attack simulations** — Execute scenarios, watch alerts fire, practice investigation | [Attack-Simulation-Lab](https://github.com/develku/Attack-Simulation-Lab) |
| 6 | **Practice tuning** — Read tuning reports, understand false positives, learn noise reduction | [Detection-Engineering-Lab — Tuning](https://github.com/develku/Detection-Engineering-Lab/tree/main/tuning) |
| 7 | **Challenge yourself** — Write your own detection rule for a technique not yet covered | [MITRE ATT&CK](https://attack.mitre.org/) |

## Documentation

| Guide | Description |
|---|---|
| [Learning Guide](docs/00-Learning-Guide.md) | Start here — foundational concepts explained for beginners |
| [Glossary](docs/GLOSSARY.md) | SOC/SIEM terminology reference |
| [Splunk Setup](docs/01-Splunk-Setup.md) | Server installation, configuration, and troubleshooting |
| [Log Sources](docs/02-Log-Sources.md) | What logs are ingested, critical event IDs, verification queries |

## Project Structure

```
SIEM-Detection-Lab/
├── README.md                           # This file
├── docker-compose.yml                  # Splunk Docker deployment
├── .env.example                        # Environment variable template
├── configs/                            # Splunk configuration files
│   ├── outputs.conf                    # Forwarder output config
│   └── siem-lab/                       # Splunk app configs
│       └── local/
│           ├── indexes.conf            # Custom index definitions
│           ├── inputs.conf             # Data input configuration
│           ├── props.conf              # Field extraction rules
│           └── transforms.conf         # Field transformation rules
├── setup/                              # Deployment scripts
│   ├── 01-Install-Splunk.sh           # Splunk server setup (Ubuntu)
│   ├── 02-Configure-Inputs.sh         # Index and input configuration
│   └── 03-Deploy-Forwarder.ps1        # Splunk UF for Windows endpoints
└── docs/                               # Setup guides and methodology
    ├── 00-Learning-Guide.md
    ├── 01-Splunk-Setup.md
    ├── 02-Log-Sources.md
    └── GLOSSARY.md
```

## Related Projects

This lab is part of a multi-project SOC environment:

| Project | Purpose |
|---|---|
| [AD-Lab-Setup](https://github.com/develku/AD-Lab-Setup) | Windows Active Directory infrastructure |
| **SIEM-Detection-Lab** (this repo) | Splunk SIEM deployment and log collection |
| [Detection-Engineering-Lab](https://github.com/develku/Detection-Engineering-Lab) | Detection rules, dashboards, and tuning |
| [Attack-Simulation-Lab](https://github.com/develku/Attack-Simulation-Lab) | Adversary emulation and attack validation |
