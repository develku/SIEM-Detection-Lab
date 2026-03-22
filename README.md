# SIEM Detection Lab

SIEM-based security monitoring and detection engineering lab built on Splunk Free. Integrates with [AD-Lab-Setup](https://github.com/develku/AD-Lab-Setup) to provide full-stack visibility — from endpoint telemetry through SIEM detection to incident investigation.

13 detection rules mapped to MITRE ATT&CK, 5 operational dashboards, 3 attack simulation scenarios with playbooks, and documented alert tuning with quantified results.

## Architecture

<!-- TODO: Replace with actual diagram after running /excalidraw-diagram-skill -->
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
                    │  • 5 Dashboards   │
                    │  • 13 Detections  │
                    │  • Alert Pipeline │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Kali Linux      │
                    │   (Attacker VM)   │
                    │                   │
                    │  • Atomic Red Team│
                    │  • Attack Scripts │
                    └───────────────────┘
```

## What This Demonstrates

### SOC Analyst & Detection Engineering

| Skill | Implementation |
|---|---|
| **SIEM Deployment** | Splunk Free with automated setup scripts, forwarder deployment, index configuration |
| **Detection Engineering** | 13 rules across 5 ATT&CK tactics — SPL queries + Sigma YAML for portability |
| **Log Analysis** | Windows Security, Sysmon, PowerShell, System logs — 30+ event IDs monitored |
| **Dashboard Design** | 5 operational dashboards: authentication, process activity, network, persistence, alert summary |
| **Threat Simulation** | 3 attack scenarios using Atomic Red Team with documented detection validation |
| **Alert Tuning** | Quantified false positive reduction (65-87%) with preserved detection capability |
| **MITRE ATT&CK** | Full technique mapping: T1003, T1021, T1047, T1053, T1055, T1070, T1078, T1543, T1547, T1570 |
| **Incident Response** | Investigation workflows with SPL queries, timeline reconstruction, containment steps |

## Detection Rules

13 rules organised by ATT&CK tactic, each in SPL and Sigma format:

| Tactic | Detection | ATT&CK | Severity | Log Source |
|---|---|---|---|---|
| **Credential Access** | LSASS Memory Dump | T1003.001 | Critical | Sysmon 10 |
| | comsvcs DLL Dump | T1003.001 | Critical | Sysmon 1 |
| | DCSync | T1003.006 | Critical | Security 4662 |
| | NTDS Shadow Copy | T1003.003 | High | Sysmon 1 |
| **Lateral Movement** | PsExec Execution | T1570 | High | Sysmon 1 + Security 4624 |
| | RDP Lateral Movement | T1021.001 | Medium | Security 4624 |
| | WMI Remote Execution | T1047 | High | Sysmon 1 |
| **Persistence** | New Service Created | T1543.003 | Medium | System 7045 |
| | Registry Run Key | T1547.001 | Medium | Sysmon 13 |
| **Privilege Escalation** | Admin Group Modification | T1078.002 | High | Security 4728/4732/4756 |
| | Scheduled Task Created | T1053.005 | Medium | Sysmon 1 |
| **Defense Evasion** | Event Log Cleared | T1070.001 | Critical | Security 1102 / System 104 |
| | Process Injection | T1055 | High | Sysmon 8 |

All rules are in [`detections/`](detections/) (SPL) and [`sigma/`](sigma/) (YAML).

## Dashboards

| Dashboard | Purpose | Key Panels |
|---|---|---|
| [Authentication Overview](dashboards/authentication-overview.xml) | Login monitoring & brute force detection | Failed login heatmap, logon types, brute force timeline |
| [Endpoint Process Activity](dashboards/endpoint-process-activity.xml) | Suspicious process execution | LOLBins, encoded PowerShell, LSASS access, process chains |
| [Network Connections](dashboards/network-connections.xml) | Outbound traffic & DNS monitoring | Connections by process, DNS volume, non-standard ports |
| [Persistence Mechanisms](dashboards/persistence-mechanisms.xml) | System change tracking | New services, registry run keys, scheduled tasks, new accounts |
| [Alert Summary](dashboards/alert-summary.xml) | SOC operator overview | Alert severity, trends, top rules, recent criticals |

## Attack Simulations

| Scenario | ATT&CK Techniques | Validates |
|---|---|---|
| [Credential Dumping](simulations/01-credential-dumping.md) | T1003.001, T1003.003, T1003.006 | 4 credential access detections |
| [Lateral Movement](simulations/02-lateral-movement.md) | T1021.001, T1570, T1047 | 3 lateral movement detections |
| [Persistence & Evasion](simulations/03-persistence-evasion.md) | T1543.003, T1547.001, T1053.005, T1070.001 | 4 persistence + evasion detections |

## Alert Tuning Results

| Rule | Before | After | FP Reduction | Report |
|---|---|---|---|---|
| LSASS Memory Access | 47 alerts/day (8.5% TP) | 6 alerts/day (66.7% TP) | **87%** | [Report](tuning/lsass-access-tuning.md) |
| Brute Force Detection | 120 alerts/day (15% TP) | 32 alerts/day (56.3% TP) | **73%** | [Report](tuning/brute-force-tuning.md) |
| New Service Created | 85 alerts/day (8.2% TP) | 12 alerts/day (58.3% TP) | **86%** | [Report](tuning/service-creation-tuning.md) |

See [Tuning Methodology](docs/05-Tuning-Methodology.md) for the full approach.

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

### Step 3: Verify and Detect

1. Open Splunk Web at `http://localhost:8000` (Docker) or `http://<splunk-server>:8000` (manual)
2. Import dashboards from `dashboards/` directory
3. Copy detection rules from `detections/` into Splunk Saved Searches
4. Run attack simulations from `simulations/` to validate

## Study Path (For Learners)

This project is designed to be studied as well as built. If you're learning SOC skills, follow this path:

```
Step 1          Step 2          Step 3           Step 4          Step 5
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ Learn    │──▶│ Build    │──▶│ Detect   │──▶│ Attack   │──▶│ Tune     │
│ Concepts │   │ the Lab  │   │ Threats  │   │ & Hunt   │   │ & Report │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
```

| Step | What To Do | Guide |
|---|---|---|
| 1 | **Learn the concepts** — Understand what a SIEM is, how Sysmon works, what MITRE ATT&CK means, and how detection rules work | [Learning Guide](docs/00-Learning-Guide.md) + [Glossary](docs/GLOSSARY.md) |
| 2 | **Build the lab** — Deploy Splunk, configure forwarders, verify log ingestion | [Splunk Setup](docs/01-Splunk-Setup.md) |
| 3 | **Understand your data** — Study each log source, learn critical Event IDs, run verification queries | [Log Sources](docs/02-Log-Sources.md) |
| 4 | **Study detection rules** — Read each `.spl` file (they have learning comments!), understand the SPL syntax and what each rule catches | [Detection Rules](docs/03-Detection-Rules.md) |
| 5 | **Run attack simulations** — Execute the scenarios, watch alerts fire, practice investigation queries | [Attack Simulations](docs/04-Attack-Simulations.md) |
| 6 | **Practice tuning** — Read the tuning reports, understand why false positives happen, learn how to reduce noise | [Tuning Methodology](docs/05-Tuning-Methodology.md) |
| 7 | **Challenge yourself** — Write your own detection rule for a technique not covered here | [MITRE ATT&CK](https://attack.mitre.org/) |

> Each detection rule file includes `# LEARNING:` comments that explain the security concept and SPL syntax step by step. Read them like a textbook.

## Documentation

| Guide | Description |
|---|---|
| [Learning Guide](docs/00-Learning-Guide.md) | Start here — foundational concepts explained for beginners |
| [Glossary](docs/GLOSSARY.md) | SOC/SIEM terminology reference |
| [Splunk Setup](docs/01-Splunk-Setup.md) | Server installation, configuration, and troubleshooting |
| [Log Sources](docs/02-Log-Sources.md) | What logs are ingested, critical event IDs, verification queries |
| [Detection Rules](docs/03-Detection-Rules.md) | Rule index, file format, deployment instructions |
| [Attack Simulations](docs/04-Attack-Simulations.md) | How to run scenarios, expected detections, investigation workflows |
| [Tuning Methodology](docs/05-Tuning-Methodology.md) | Alert tuning process, report template, quantified results |

## Project Structure

```
SIEM-Detection-Lab/
├── README.md                           # This file
├── diagrams/                           # Architecture diagrams
├── setup/                              # Deployment scripts
│   ├── 01-Install-Splunk.sh           #   Splunk server setup (Ubuntu)
│   ├── 02-Configure-Inputs.sh         #   Index and input configuration
│   ├── 03-Deploy-Forwarder.ps1        #   Splunk UF for Windows endpoints
│   └── configs/                       #   Splunk configuration files
├── detections/                         # SPL detection rules by ATT&CK tactic
│   ├── credential-access/             #   T1003.001, T1003.003, T1003.006
│   ├── lateral-movement/              #   T1021.001, T1047, T1570
│   ├── persistence/                   #   T1543.003, T1547.001
│   ├── privilege-escalation/          #   T1053.005, T1078.002
│   └── defense-evasion/               #   T1055, T1070.001
├── sigma/                              # Sigma YAML versions (SIEM-portable)
├── dashboards/                         # Splunk Simple XML dashboard exports
├── simulations/                        # Attack scenarios with playbooks
├── tuning/                             # Alert tuning reports with metrics
├── screenshots/                        # Dashboard and alert screenshots
└── docs/                               # Setup guides and methodology
```

## Related Projects

- [AD-Lab-Setup](https://github.com/develku/AD-Lab-Setup) — Active Directory infrastructure this lab monitors
- [Help-Desk-Ticketing-Lab](https://github.com/develku/Help-Desk-Ticketing-Lab) — osTicket ITSM system for ticket workflows
