# 🏦 ApexFin Global Bank — AI Security Remediation Demo Portal

> **Designed for Google Cloud AI Customer Engineers (CEs) to demonstrate Google Cloud CodeMender's autonomous vulnerability discovery, sandbox verification, and patch generation capabilities inside an isolated Google Compute Engine Linux VM provisioned from GCP Cloud Shell.**

---

## Table of Contents
1. [Executive Summary & Demo Narrative](#executive-summary--demo-narrative)
2. [GCP Cloud Shell Installation (Isolated Linux VM)](#gcp-cloud-shell-installation-isolated-linux-vm)
3. [Demo Reset & Rollback (`./reset_demo.sh`)](#demo-reset--rollback-reset_demosh)
4. [Uninstall & Deprovision Demo Resources from GCP Cloud Shell (`./deprovision_vm.sh`)](#3-uninstall--deprovision-demo-resources-from-gcp-cloud-shell-deprovision_vmsh)
5. [Frontend UI Exploit Walkthrough (CE Demo Playbook)](#frontend-ui-exploit-walkthrough-ce-demo-playbook)
6. [Vulnerability Identification & Remediation (CodeMender Lifecycle)](#vulnerability-identification--remediation-codemender-lifecycle)
7. [Application Architecture](#application-architecture)
8. [Project Directory Structure](#project-directory-structure)
9. [Frameworks & Libraries](#frameworks--libraries)
10. [Environment Variables](#environment-variables)

---

## Executive Summary & Demo Narrative

Modern enterprises face a critical challenge: traditional Static Application Security Testing (SAST) tools generate thousands of alerts with high false-positive rates, overwhelming security and development teams.

**CodeMender** is Google Cloud's autonomous AI code security agent powered by fine-tuned Gemini models that transforms this paradigm:
1. **Find**: Scans codebases using agentic AST and semantic reasoning to discover deep software vulnerabilities (e.g., OWASP Top 10).
2. **Verify**: Rather than guessing, CodeMender constructs and executes proof-of-concept (PoC) exploits inside an **isolated local OS sandbox** (`exebox`) to mathematically prove or disprove exploitability, eliminating false positives.
3. **Fix**: Generates idiomatic, secure source code patches, applies them in the sandbox, runs existing regression test suites (`build.command`), and re-executes the PoC exploit to confirm complete remediation without breaking existing application logic.

This demo application simulates **ApexFin Global Bank**, a financial services portal containing realistic, high-consequence vulnerabilities in customer account management and banking gateway diagnostics.

---

## GCP Cloud Shell Installation (Isolated Linux VM)

Because this application contains realistic, exploitable security vulnerabilities (CWE-89 and CWE-78), the default installation runs from **Google Cloud Shell** and deploys both the **ApexFin Banking Portal** and the **CodeMender CLI (`cm`)** onto a **temporary, isolated Compute Engine Linux VM**.

### Security Isolation Architecture

To ensure zero risk to your GCP environment:
* **Dedicated Least-Privilege Identity**: The VM does **NOT** attach the default Compute Engine service account. Instead, a dedicated service account (`apexfin-demo-sa`) is created and granted strictly `roles/aiplatform.user` (needed solely for CodeMender AI reasoning). It has **zero access** to Cloud Storage buckets, BigQuery datasets, other VMs, or Secret Manager.
* **Tag-Scoped Firewall Isolation**: The firewall rule (`apexfin-demo-allow-5000`) is strictly scoped to instances with the network tag `apexfin-demo-server`. No other instances, subnets, or services in your VPC are exposed or modified.
* **Zero-Impact Teardown Guarantee**: Deprovisioning removes *only* the resources created by the installation script (`apexfin-demo-vm`, `apexfin-demo-allow-5000`, and `apexfin-demo-sa` + its IAM binding). All other VMs, networks, databases, and IAM policies in the project remain untouched.

---

### 1. Clone the Repository in GCP Cloud Shell

1. Open **[Google Cloud Shell](https://shell.cloud.google.com/)** in your browser (or click **[Open directly in Cloud Shell](https://shell.cloud.google.com/?cloudshell_git_repo=https://github.com/pradeesi/Codemender_Demo)**).
2. Clone the repository and navigate into the project directory:

```bash
git clone https://github.com/pradeesi/Codemender_Demo.git
cd Codemender_Demo
chmod +x provision_vm.sh deprovision_vm.sh reset_demo.sh
```

---

### 2. Provision the Isolated Demo VM (`./provision_vm.sh`)

#### Option A: Interactive Project Selection (Default)
Run the installation script without specifying a project ID:

```bash
./provision_vm.sh
```

When no project ID is passed in the command, the script automatically queries all GCP projects accessible to your logged-in account and displays a numbered menu:

```text
👤 Authenticated GCP Account: your-email@domain.com

🔍 Fetching available Google Cloud Projects for your-email@domain.com...

📋 Available Google Cloud Projects:
--------------------------------------------------------------------------------
   [ 1] example-demo-project-01          (Customer Demo Sandbox) [current gcloud project]
   [ 2] example-security-lab-02          (AppSec Lab)
   [ 3] example-testing-env-03           (Testing Environment)
--------------------------------------------------------------------------------
Select the project number [1-3] (or enter Project ID):
```

Simply type the **number** corresponding to the project where you want to deploy the demo VM (e.g., `1`) and press **Enter**.

#### Option B: Provide the GCP Project ID Directly in the Command
If you already know the target GCP Project ID, pass it directly via `--project` (or `-p`):

```bash
./provision_vm.sh --project <YOUR_PROJECT_ID>
```

You can also specify the Compute Engine zone (`--zone` / `-z`) or region (`--region` / `-r`), and auto-recreate (`--recreate` / `-y`):

```bash
./provision_vm.sh --project <YOUR_PROJECT_ID> --zone us-central1-a --recreate
```

#### What the Installation Script Provisions:
1. Enables `compute.googleapis.com` and `aiplatform.googleapis.com` on the selected project.
2. Auto-detects the available VPC network and regional subnet.
3. Creates the least-privilege service account `apexfin-demo-sa@<YOUR_PROJECT_ID>.iam.gserviceaccount.com` with `roles/aiplatform.user`.
4. Creates the tag-scoped VPC firewall rule `apexfin-demo-allow-5000` (TCP port 5000 ingress for tag `apexfin-demo-server`).
5. Provisions an `e2-standard-2` (2 vCPUs, 8 GB RAM) Ubuntu 22.04 LTS VM (`apexfin-demo-vm`) and runs the startup script to:
   * Install Python 3, `venv`, `git`, `curl`, `unzip`, and `iputils-ping`.
   * Install the **CodeMender CLI (`cm`)** in `/usr/local/bin/cm`.
   * Deploy the ApexFin portal into `/opt/apexfin`, initialize Git and `apexfin.db`, and start the `apexfin.service` systemd daemon on port `5000`.
   * Configure `/etc/profile.d/codemender.sh` with `GOOGLE_CLOUD_PROJECT=<YOUR_PROJECT_ID>`.

#### Accessing the Demo UI & Sandbox VM:
Once provisioning completes, the script prints the access commands:

* **Direct Public Web URL**:
  ```text
  http://<EXTERNAL_IP>:5000
  ```
* **Cloud Shell Port Forwarding & Web Preview** *(if corporate firewall blocks port 5000)*:
  ```bash
  gcloud compute ssh apexfin-demo-vm --zone=<ZONE> --project=<YOUR_PROJECT_ID> -- -L 5000:localhost:5000
  ```
  Then click **Web Preview** in Cloud Shell and preview on **Port 5000**.
* **SSH into the VM from Cloud Shell to Run CodeMender (`cm`)**:
  ```bash
  gcloud compute ssh apexfin-demo-vm --zone=<ZONE> --project=<YOUR_PROJECT_ID>
  ```

---

## Demo Reset & Rollback (`./reset_demo.sh`)

If you want to reset the application state inside `/opt/apexfin` on the VM between back-to-back customer sessions without reprovisioning the VM:

```bash
cd /opt/apexfin
./reset_demo.sh
sudo systemctl restart apexfin.service
```

**What it accomplishes**:
* Reverts all source code modifications applied by CodeMender (`git checkout HEAD -- .`).
* Deletes temporary candidate branches (`cm-*`) generated during `cm fix`.
* Re-seeds a clean SQLite banking database (`apexfin.db`).
* Cleans local CodeMender state caches and runs the unit test suite (`test_app.py`).

---

### 3. Uninstall & Deprovision Demo Resources from GCP Cloud Shell (`./deprovision_vm.sh`)

After completing your customer demo, run the combined commands below from **GCP Cloud Shell** to remove all cloud demo resources and delete the cloned `Codemender_Demo` directory so your Cloud Shell disk space stays clean:

#### Option A: Interactive Project Selection (Default)
```bash
cd ~/Codemender_Demo
./deprovision_vm.sh
cd ~ && rm -rf Codemender_Demo
```
Displays the numbered list of all your GCP projects so you can select the project number to clean up, prompts for confirmation (`y/N`), and removes the local `Codemender_Demo` folder once finished.

#### Option B: Provide the GCP Project ID Directly in the Command
```bash
cd ~/Codemender_Demo
./deprovision_vm.sh --project <YOUR_PROJECT_ID>
cd ~ && rm -rf Codemender_Demo
```
*(Add `-y` or `--yes` to `./deprovision_vm.sh --project <YOUR_PROJECT_ID> -y` to skip the confirmation prompt.)*

**What the Uninstallation Workflow Removes**:
1. Compute Engine VM instance `apexfin-demo-vm` (and its attached boot disk).
2. Tag-scoped VPC firewall rule `apexfin-demo-allow-5000`.
3. Dedicated service account `apexfin-demo-sa@<YOUR_PROJECT_ID>.iam.gserviceaccount.com` and its `roles/aiplatform.user` IAM policy binding.
4. Cloned `Codemender_Demo` directory from your Cloud Shell home directory.
5. Leaves all other VMs, networks, firewall rules, service accounts, and configurations in the GCP project completely untouched.

---

## Frontend UI Exploit Walkthrough (CE Demo Playbook)

During your presentation with customer CISOs, AppSec Directors, and Lead Architects, use the web interface to demonstrate vulnerability impact, then remediate the code via CodeMender inside the VM SSH session, and finally return to the UI to verify the fix.

### Vulnerability 1: SQL Injection (CWE-89) &mdash; Classified Account Exfiltration

* **Module**: Customer Accounts Registry (`/accounts`)
* **Vulnerable Source**: [`app.py`](app.py) &rarr; `accounts_view()` and `api_accounts()`
* **Business Risk**: Unauthenticated or low-privilege users can bypass confidentiality flags, exfiltrating secret offshore reserve accounts and SWIFT Nostro settlement balances totaling over **$960,000,000**.

#### Step-by-Step UI Demonstration:
1. Open the ApexFin portal in your browser (`http://<EXTERNAL_IP>:5000` or via Cloud Shell Web Preview on port `5000`).
2. Click **Customer Accounts** in the top navigation bar.
3. Notice that normal searches (e.g. searching for `Alice` or `Checking`) return only authorized commercial accounts.
4. Copy the SQL injection payload below and paste it into the **Search** input box, then click **Search**:
   ```sql
   ' OR 1=1 --
   ```
5. **Observed Impact**: The query condition breaks out of the intended customer filter. Confidential multi-million dollar banking reserves are exposed in the accounts table:
   * `ACC-99999` &mdash; *Executive Confidential Reserve* &mdash; **$48,500,000.00** (Restricted)
   * `ACC-88888` &mdash; *SWIFT Nostro Settlement* &mdash; **$912,000,000.00** (Restricted)
6. *(Optional Advanced Query)*: Enter a `UNION SELECT` payload:
   ```sql
   ' UNION SELECT id, account_number, customer_name, email, account_type, balance, status, is_confidential FROM accounts WHERE is_confidential=1 --
   ```

---

### Vulnerability 2: OS Command Injection (CWE-78) &mdash; Remote Server Takeover

* **Module**: Banking Network Gateway Diagnostics (`/system-diagnostics`)
* **Vulnerable Source**: [`app.py`](app.py) &rarr; `diagnostics_view()` and `api_ping()`
* **Business Risk**: Remote Code Execution (RCE). An attacker with access to the diagnostics portal can execute arbitrary shell commands under the web server's OS privileges.

#### Step-by-Step UI Demonstration:
1. From the top navigation bar, click **Gateway Diagnostics**.
2. Normal usage: Entering `127.0.0.1` executes an ICMP ping probe (`ping -c 2 127.0.0.1`) and displays standard network latency.
3. Demonstrate command injection by chaining shell operators in the **Target Host** input box:
   ```bash
   127.0.0.1; whoami; id; uname -a
   ```
4. Click **Run Diagnostic Probe**.
5. **Observed Impact**: The console output stream renders the output of `whoami`, `id`, and system kernel telemetry directly below the ping statistics.
6. Demonstrate arbitrary file read on the VM host:
   ```bash
   127.0.0.1; cat /etc/passwd | head -n 5
   ```

---

## Vulnerability Identification & Remediation (CodeMender Lifecycle)

SSH into the sandbox VM from GCP Cloud Shell:

```bash
gcloud compute ssh apexfin-demo-vm --zone=<ZONE> --project=<YOUR_PROJECT_ID>
cd /opt/apexfin
```

### Phase 1: Autonomous Vulnerability Discovery (`cm find`)

Initialize CodeMender and scan the application code:

```bash
# Initialize CodeMender workspace tracking
cm init

# Scan the application source
cm find ./app.py
```

**What CodeMender does**:
* Identifies untrusted input from `request.args.get("q")` flowing into SQL string interpolation `query = f"SELECT ... {search_term} ..."` (CWE-89).
* Identifies untrusted form data from `request.form.get("host")` concatenated into `subprocess.run(f"ping -c 2 {target_host}", shell=True)` (CWE-78).
* Records findings in the local state database with unique Finding IDs.

To view the findings table:
```bash
cm report
```

---

### Phase 2: Autonomous Proof-of-Concept Exploit Verification (`cm verify`)

Run verification on a detected finding:

```bash
cm verify <FINDING_ID>
```

**What CodeMender does**:
* Launches an isolated, lightweight process-level sandbox container (`exebox`) on the VM.
* Autonomously authors and executes a proof-of-concept exploit against the application.
* If the exploit succeeds, it proves the vulnerability is **exploitable** and promotes the finding status to `OPEN (VERIFIED)`.

---

### Phase 3: Autonomous Remediation & Test Verification (`cm fix`)

Instruct CodeMender to produce and apply a verified fix:

```bash
cm fix <FINDING_ID>
```

**What CodeMender does**:
1. **Generates Patch Candidate**:
   * **SQLi (CWE-89)**: Replaces dynamic f-string formatting with parameterized SQLite queries (`?` placeholders).
   * **Command Injection (CWE-78)**: Disables `shell=True` and passes arguments as a sanitized argument list (`["ping", "-c", "2", target_host]`).
2. **Applies to Sandbox Copy**: Isolates patch testing so the working tree is untouched until verified.
3. **Runs Regression Test Suite**: Executes `python3 -m unittest test_app.py` (configured in [`config.yaml`](config.yaml)).
4. **Re-runs PoC Exploit**: Verifies that the previous exploit payload now fails safely.
5. **Applies Patch**: Applies the verified fix to `/opt/apexfin/app.py`.

Inspect the resulting diff:
```bash
cm vcs diff
```

---

### Phase 4: Re-testing from the Web UI (Verification of Fix)

1. Gunicorn (`--reload`) automatically reloads `/opt/apexfin/app.py` when modified (or run `sudo systemctl restart apexfin.service`).
2. **Re-test SQL Injection on Customer Accounts**:
   * Enter `' OR 1=1 --` into the **Search** field and click **Search**.
   * **Observed Result**: The exploit is neutralized. Confidential offshore accounts remain hidden.
3. **Re-test Command Injection on Gateway Diagnostics**:
   * Enter `127.0.0.1; whoami; id` into the **Target Host** field and click **Run Diagnostic Probe**.
   * **Observed Result**: Shell metacharacters (`;`) are no longer interpreted by a shell, preventing command execution.

---

## Application Architecture

The ApexFin Banking Portal runs inside the isolated Compute Engine Linux VM as a 3-tier Python web application:

```
┌─────────────────────────────────────────────────────────────┐
│                       Client Browser                        │
│        (Bootstrap 5 Banking Portal UI, SWIFT Ledger)        │
└──────────────────────────────┬──────────────────────────────┘
                               │ HTTP / JSON (Port 5000)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│        Isolated GCE Linux VM (apexfin-demo-vm :5000)        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Flask Application (app.py)               │  │
│  │  ┌──────────────────────┐   ┌──────────────────────┐  │  │
│  │  │   Accounts Engine    │   │ Gateway Diagnostics  │  │  │
│  │  │ (CWE-89 SQLi Vector) │   │ (CWE-78 RCE Vector)  │  │  │
│  │  └──────────┬───────────┘   └──────────┬───────────┘  │  │
│  └─────────────┼──────────────────────────┼──────────────┘  │
│                ▼                          ▼                 │
│  ┌───────────────────────────┐ ┌──────────────────────────┐ │
│  │SQLite Database(apexfin.db)│ │OS Subprocess (ping/sh)   │ │
│  └───────────────────────────┘ └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Project Directory Structure

```
CodeMender/
├── .env.example             # Template for environment variables
├── .gitignore               # Exclusion rules for secrets, DBs, and virtualenvs
├── config.yaml              # CodeMender scan and build verification configuration
├── requirements.txt         # Core Python dependencies (Flask, Gunicorn)
├── provision_vm.sh          # Cloud Shell installer: provisions isolated GCE Linux VM & CodeMender
├── deprovision_vm.sh        # Cloud Shell uninstaller: removes demo VM, firewall rule, and demo SA
├── reset_demo.sh            # Environment rollback script for resetting demo state on the VM
├── app.py                   # Main Flask application with intentional demo vulnerabilities
├── database.py              # SQLite schema creation and financial sample seed data
├── test_app.py              # Regression test suite invoked by CodeMender build.command
├── templates/               # Jinja2 HTML templates
│   ├── base.html            # Master banking portal layout with navigation bar and footer
│   ├── index.html           # Main banking overview dashboard
│   ├── accounts.html        # Commercial customer account registry
│   ├── transfer.html        # Outbound wire transfer dispatch ledger
│   └── diagnostics.html     # Banking gateway connectivity ping utility
└── static/                  # Static assets
    └── css/
        └── style.css        # Custom banking stylesheet extending Bootstrap 5
```

---

## Frameworks & Libraries

* **Backend Web Framework**: [Flask 3.0+](https://flask.palletsprojects.com/)
* **WSGI Production Server**: [Gunicorn 21.2+](https://gunicorn.org/)
* **Database Engine**: [SQLite 3](https://www.sqlite.org/) (Python standard library `sqlite3`)
* **Frontend UI Framework**: [Bootstrap 5.3.3](https://getbootstrap.com/) & [Bootstrap Icons 1.11](https://icons.getbootstrap.com/)
* **Testing Framework**: Python `unittest` (Standard Library)

---

## Environment Variables

All runtime configuration is externalized (see [`.env.example`](.env.example)):

| Variable Key | Type | Default Value | Description | Example |
| :--- | :--- | :--- | :--- | :--- |
| `PORT` | Integer | `5000` | Port on which the application listens | `PORT=5000` |
| `HOST` | String | `0.0.0.0` | Network binding interface | `HOST=0.0.0.0` |
| `FLASK_ENV` | String | `production` | Flask runtime environment (`development` / `production`) | `FLASK_ENV=production` |
| `FLASK_DEBUG` | Integer | `0` | Debug mode switch (`0` disabled on demo VM) | `FLASK_DEBUG=0` |
| `SECRET_KEY` | String | *Generated* | Session cookie signing key | `SECRET_KEY=custom-key-3918` |
| `DATABASE_PATH` | String | `apexfin.db` | File path for SQLite database | `DATABASE_PATH=apexfin.db` |
| `LOG_LEVEL` | String | `INFO` | Semantic logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`) | `LOG_LEVEL=INFO` |
| `GOOGLE_CLOUD_PROJECT` | String | *Selected Project* | Target Google Cloud Project ID for CodeMender CLI | `GOOGLE_CLOUD_PROJECT=my-gcp-project` |
