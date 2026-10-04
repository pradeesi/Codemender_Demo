# 🏦 ApexFin Global Bank — AI Security Remediation Demo Portal

> **Designed for Google Cloud AI Customer Engineers (CEs) to demonstrate Google Cloud CodeMender's autonomous vulnerability discovery, sandbox verification, and patch generation capabilities to enterprise customers.**

---

## Table of Contents
1. [Executive Summary & Demo Narrative](#executive-summary--demo-narrative)
2. [Frontend UI Exploit Walkthrough (CE Demo Playbook)](#frontend-ui-exploit-walkthrough-ce-demo-playbook)
3. [Vulnerability Identification & Remediation (CodeMender vs Manual)](#vulnerability-identification--remediation-codemender-vs-manual)
4. [Application Architecture](#application-architecture)
5. [Project Directory Structure](#project-directory-structure)
6. [Frameworks & Libraries](#frameworks--libraries)
7. [Environment Variables](#environment-variables)
8. [Local Execution Instructions](#local-execution-instructions)
9. [Automated Deployment & Reset Scripts](#automated-deployment--reset-scripts)
10. [Temporary GCP Demo VM (Provision & Deprovision)](#temporary-gcp-demo-vm-provision--deprovision)
11. [Cloud Deployment Playbooks (Cloud Run & GKE)](#cloud-deployment-playbooks-cloud-run--gke)

---

## Executive Summary & Demo Narrative

Modern enterprises face a critical challenge: traditional Static Application Security Testing (SAST) tools generate thousands of alerts with high false-positive rates, overwhelming security and development teams.

**CodeMender** is Google Cloud's autonomous AI code security agent powered by fine-tuned Gemini models that transforms this paradigm:
1. **Find**: Scans codebases using agentic AST and semantic reasoning to discover deep software vulnerabilities (e.g., OWASP Top 10).
2. **Verify**: Rather than guessing, CodeMender constructs and executes proof-of-concept (PoC) exploits inside an **isolated local OS sandbox** (`exebox`) to mathematically prove or disprove exploitability, eliminating false positives.
3. **Fix**: Generates idiomatic, secure source code patches, applies them in the sandbox, runs existing regression test suites (`build.command`), and re-executes the PoC exploit to confirm complete remediation without breaking existing application logic.

This demo application simulates **ApexFin Global Bank**, a financial services portal containing realistic, high-consequence vulnerabilities in customer account management and banking gateway diagnostics.

---

## Frontend UI Exploit Walkthrough (CE Demo Playbook)

During your presentation with customer CISOs, AppSec Directors, and Lead Architects, use the realistic, clean web interface to demonstrate vulnerability impact, then fix the code via CodeMender on the VM shell, and finally return to the UI to verify remediation.

### Vulnerability 1: SQL Injection (CWE-89) &mdash; Classified Account Exfiltration

* **Module**: Customer Accounts Registry (`/accounts`)
* **Vulnerable Source**: [`app.py`](app.py) &rarr; `accounts_view()` and `api_accounts()`
* **Business Risk**: Unauthenticated or low-privilege users can bypass confidentiality flags, exfiltrating secret offshore reserve accounts and SWIFT Nostro settlement balances totaling over **$960,000,000**.

#### Step-by-Step UI Demonstration:
1. Open your browser and navigate to the application dashboard: [http://localhost:5000](http://localhost:5000) (or your VM's public IP / Cloud Shell URL).
2. Click **Customer Accounts** in the top navigation bar.
3. Notice that normal searches (e.g. searching for `Alice` or `Checking`) return only authorized commercial accounts.
4. Now, enter the SQL injection payload directly into the **Search** input box:
   ```sql
   ' OR 1=1 --
   ```
5. Click **Search**.
6. **Observed Impact**: The query condition breaks out of the intended customer filter. The confidential multi-million dollar banking reserves are exposed in the accounts table:
   * `ACC-99999` &mdash; *Executive Confidential Reserve* &mdash; **$48,500,000.00** (Restricted)
   * `ACC-88888` &mdash; *SWIFT Nostro Settlement* &mdash; **$912,000,000.00** (Restricted)
7. *(Optional Advanced Query)*: Enter a UNION SELECT payload:
   ```sql
   ' UNION SELECT id, account_number, customer_name, email, account_type, balance, status, is_confidential FROM accounts WHERE is_confidential=1 --
   ```

---

### Vulnerability 2: OS Command Injection (CWE-78) &mdash; Remote Server Takeover

* **Module**: Banking Network Gateway Diagnostics (`/system-diagnostics`)
* **Vulnerable Source**: [`app.py`](app.py) &rarr; `diagnostics_view()` and `api_ping()`
* **Business Risk**: Remote Code Execution (RCE). An attacker with access to the diagnostics portal can execute arbitrary shell commands under the web server's host/container process privileges.

#### Step-by-Step UI Demonstration:
1. From the top navigation bar, click **Gateway Diagnostics**.
2. Normal usage: Entering `127.0.0.1` executes an ICMP ping probe (`ping -c 2 127.0.0.1`) and displays standard network latency.
3. Now, demonstrate command injection by chaining shell operators in the **Target Host** input box:
   ```bash
   127.0.0.1; whoami; id; uname -a
   ```
4. Click **Run Diagnostic Probe**.
5. **Observed Impact**: The dark console output stream renders the output of `whoami`, `id`, and system kernel telemetry directly below the ping statistics.
6. Now demonstrate arbitrary file read on host assets:
   ```bash
   127.0.0.1; cat /etc/passwd | head -n 5
   ```
7. Point out to the customer: If this service were running in Kubernetes or a production VM, the attacker could dump environment variables, exfiltrate Google Cloud Service Account tokens from metadata endpoints, and achieve full lateral movement.

---

## Vulnerability Identification & Remediation (CodeMender vs Manual)

Show the customer the difference between traditional manual triage and CodeMender's agentic lifecycle:

### Phase 1: Autonomous Vulnerability Discovery (`cm find`)

Run CodeMender to scan the codebase:

```bash
# Set your active GCP project (whitelisted for CodeMender)
export GOOGLE_CLOUD_PROJECT="maf-testing-387011"

# Initialize CodeMender workspace tracking
cm init

# Scan the repository
cm find ./app.py
```

**What CodeMender does**:
* Identifies untrusted input from `request.args.get("q")` flowing into SQL string interpolation `query = f"SELECT ... {search_term} ..."` (CWE-89).
* Identifies untrusted form data from `request.form.get("host")` concatenated into `subprocess.run(f"ping -c 2 {target_host}", shell=True)` (CWE-78).
* Records findings in the local state database (`state.db`) with unique Finding IDs.

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
* Launches an isolated, lightweight process-level sandbox container (`exebox`) on the local workstation.
* Autonomously authors and runs a proof-of-concept exploit against the local codebase.
* If the exploit succeeds, it proves the vulnerability is **exploitable** and promotes the status from unverified to `OPEN (VERIFIED)`.
* If the exploit fails or the path is unreachable, CodeMender dismisses the false positive without burdening your engineering team.

---

### Phase 3: Autonomous Remediation & Test Verification (`cm fix`)

Instruct CodeMender to produce and apply a verified fix:

```bash
cm fix <FINDING_ID>
```

**What CodeMender does**:
1. **Generates Patch Candidate**:
   * For **SQLi**: Replaces dynamic f-string formatting with parameterized SQLite queries:
     ```python
     # Remediated
     cursor.execute(
         "SELECT ... FROM accounts WHERE is_confidential = 0 AND (customer_name LIKE ? OR account_number LIKE ?)",
         (f"%{search_term}%", f"%{search_term}%")
     )
     ```
   * For **Command Injection**: Disables `shell=True` and executes arguments as a sanitized list:
     ```python
     # Remediated
     proc = subprocess.run(["ping", "-c", "2", target_host], shell=False, capture_output=True, text=True)
     ```
2. **Applies to Sandbox Copy**: Isolates patch testing so your working tree is untouched until verified.
3. **Runs Regression Test Suite**: Executes the command configured in [`config.yaml`](config.yaml):
   ```bash
   python3 -m unittest test_app.py
   ```
4. **Re-runs PoC Exploit**: Verifies that the previous exploit payload now fails safely.
5. **Applies Patch**: Stages the verified diff cleanly in Git.

Inspect the resulting diff:
```bash
cm vcs diff
```

---

### Phase 4: Re-testing from the Web UI (Verification of Fix)

After CodeMender generates and applies the verified patches in `/opt/apexfin`:

1. **Automatic Reload**: The application service running on the VM immediately reloads the updated code (or run `sudo systemctl restart apexfin.service` if needed).
2. **Re-test SQL Injection on Customer Accounts**:
   * Navigate back to **Customer Accounts** in your browser.
   * Enter `' OR 1=1 --` into the **Search** field and click **Search**.
   * **Observed Result**: The exploit is neutralized. SQLite executes the query using parameterized bindings, treating the entire payload as a literal string. The confidential offshore accounts remain completely protected and hidden.
3. **Re-test Command Injection on Gateway Diagnostics**:
   * Navigate back to **Gateway Diagnostics** in your browser.
   * Enter `127.0.0.1; whoami; id` into the **Target Host** field and click **Run Diagnostic Probe**.
   * **Observed Result**: The shell metacharacters (`;`) are no longer interpreted by an OS shell. The system executes the ping binary safely without executing `whoami` or `id`.

---

## Application Architecture

The ApexFin Banking Portal is structured around a local-first, lightweight 3-tier architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                       Client Browser                        │
│   (Bootstrap 5 UI, Live Exploit Injector, SWIFT Ledger)     │
└──────────────────────────────┬──────────────────────────────┘
                               │ HTTP / JSON
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 Flask Application (app.py)                  │
│  ┌────────────────────────┐     ┌────────────────────────┐  │
│  │    Accounts Engine     │     │  Gateway Diagnostics   │  │
│  │  (CWE-89 SQLi Vector)  │     │   (CWE-78 RCE Vector)  │  │
│  └───────────┬────────────┘     └───────────┬────────────┘  │
└──────────────┼──────────────────────────────┼───────────────┘
               │                              │
               ▼                              ▼
┌─────────────────────────────┐  ┌────────────────────────────┐
│ SQLite Database (apexfin.db)│  │ Operating System Subprocess│
│ (Accounts & Wire Transfers) │  │   (ping /bin/sh invocation)│
└─────────────────────────────┘  └────────────────────────────┘
```

* **Presentation Layer**: HTML5 + Bootstrap 5 responsive templates with built-in Customer Engineer interactive demo payloads.
* **Controller Layer**: Flask 3.x web application exposing standard web views and REST API endpoints.
* **Persistence Layer**: SQLite 3 database (`apexfin.db`) with schema separation between commercial accounts and classified executive reserves.
* **Testing Layer**: Python `unittest` test suite in [`test_app.py`](test_app.py) validating core business workflows.

---

## Project Directory Structure

```
CodeMender/
├── .env.example             # Template for required environment variables
├── .gitignore               # Strict exclusion rules for secrets, DBs, and venvs
├── config.yaml              # CodeMender scan and build verification configuration
├── Dockerfile               # Container manifest for Google Cloud Run & GKE
├── requirements.txt         # Core Python dependencies (Flask, Gunicorn)
├── deploy.sh                # Automated local venv & Cloud Run deployment script
├── reset_demo.sh            # Complete environment rollback script for re-running demos
├── provision_vm.sh          # Automated temporary GCP VM sandbox provisioning script
├── deprovision_vm.sh        # Teardown script to wipe VM & firewall after customer demos
├── app.py                   # Main Flask application with intentional demo vulnerabilities
├── database.py              # SQLite schema creation and financial sample seed data
├── test_app.py              # Regression test suite invoked by CodeMender build.command
├── templates/               # Jinja2 HTML templates
│   ├── base.html            # Master layout with navbar and Exploit Cheat Sheet modal
│   ├── index.html           # Main banking overview dashboard
│   ├── accounts.html        # Customer account registry (SQL Injection demo)
│   ├── transfer.html        # Outbound wire transfer dispatch ledger
│   └── diagnostics.html     # Banking gateway ping utility (Command Injection demo)
└── static/                  # Static assets
    ├── css/
    │   └── style.css        # Custom styling extending Bootstrap 5
    └── js/
        └── main.js          # Client-side 1-click exploit injection and copy helpers
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

All configuration is externalized. Set these variables in your shell or copy [`.env.example`](.env.example) to `.env`:

| Variable Key | Type | Default Value | Description | Example |
| :--- | :--- | :--- | :--- | :--- |
| `PORT` | Integer | `5000` | Port on which the application listens | `PORT=5000` |
| `HOST` | String | `0.0.0.0` | Network binding interface | `HOST=0.0.0.0` |
| `FLASK_ENV` | String | `development` | Flask runtime environment (`development` / `production`) | `FLASK_ENV=production` |
| `FLASK_DEBUG` | Integer | `0` | Debug mode switch (`1` enables interactive debugger) | `FLASK_DEBUG=0` |
| `SECRET_KEY` | String | *Generated* | Session cookie signing key | `SECRET_KEY=custom-key-3918` |
| `DATABASE_PATH` | String | `apexfin.db` | File path for SQLite database | `DATABASE_PATH=apexfin.db` |
| `LOG_LEVEL` | String | `INFO` | Semantic logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`) | `LOG_LEVEL=INFO` |
| `GOOGLE_CLOUD_PROJECT` | String | *Unset* | Target Google Cloud Project for CodeMender / Cloud Run | `GOOGLE_CLOUD_PROJECT=maf-testing-387011` |

---

## Local Execution Instructions

Execute these copy-paste commands on any Linux or macOS machine:

### 1. Automated Setup & Launch
Simply run the automated deployment script:
```bash
chmod +x deploy.sh reset_demo.sh
./deploy.sh
```

This will automatically create `.venv`, install packages, seed the database, run the test suite, and launch the server in the background at **`http://127.0.0.1:5000`**.

### 2. Manual Step-by-Step Setup
If you prefer running commands manually:

```bash
# 1. Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# 2. Install dependencies
pip install --upgrade pip
pip install -r requirements.txt

# 3. Seed the SQLite banking database
python3 database.py

# 4. Verify test suite
python3 -m unittest test_app.py

# 5. Launch application
python3 app.py
```

Access the portal in your browser at `http://localhost:5000`.

---

## Automated Deployment & Reset Scripts

### 1. Deploy Script (`./deploy.sh`)
* **Local Mode**:
  ```bash
  ./deploy.sh
  ```
  Deploys locally, manages virtualenv, verifies tests, and records PID in `.app.pid`.
* **Cloud Run Mode**:
  ```bash
  ./deploy.sh --cloud-run
  ```
  Builds and deploys the container directly to Google Cloud Run in the configured project.

### 2. Reset / Rollback Script (`./reset_demo.sh`)
When you finish presenting to one customer and need to wipe all code changes and database entries before the next presentation:

```bash
./reset_demo.sh
```

**What it accomplishes**:
* Stops running application processes and frees port 5000.
* Reverts all source code modifications applied by CodeMender (`git checkout HEAD -- .`).
* Deletes any temporary candidate branches (`cm-*`) generated during `cm fix`.
* Re-seeds a pristine SQLite banking database.
* Cleans local CodeMender caches and state databases.
* Runs the unit test suite to verify 100% baseline readiness.

---

## Temporary GCP Demo VM (Provision & Deprovision)

Because this application contains realistic, exploitable security vulnerabilities (CWE-89 and CWE-78), running it inside a **temporary, disposable Compute Engine Linux VM** on Google Cloud is the recommended best practice for Customer Engineers. This isolates exploit execution away from your local workstation and allows anyone on the customer call to access the live demo UI over a public URL or Cloud Shell Web Preview.

### Security Isolation Architecture

To ensure zero risk to customer cloud environments:
* **Dedicated Least-Privilege Identity**: The VM does **NOT** attach the default Compute Engine service account (which often has broad Editor rights). Instead, a dedicated service account `apexfin-demo-sa` is created and granted strictly `roles/aiplatform.user` (needed solely for CodeMender AI reasoning). It has **zero access** to Google Cloud Storage buckets, BigQuery datasets, other VMs, or Secret Manager.
* **Tag-Scoped Firewall Isolation**: The firewall rule `apexfin-demo-allow-5000` is strictly targeted to instances with the network tag `apexfin-demo-server`. No other instances, subnets, or services in your VPC are exposed or modified.
* **Zero-Impact Teardown Guarantee**: Deprovisioning targets *strictly* `apexfin-demo-vm`, `apexfin-demo-allow-5000`, and `apexfin-demo-sa`. Existing instances, networks, databases, and IAM policies in the project remain completely untouched.

---

### 1. Automated Provisioning (`./provision_vm.sh`)

Run the automated provisioning script:

```bash
chmod +x provision_vm.sh deprovision_vm.sh
./provision_vm.sh
```

*(Or non-interactively with auto-recreation: `./provision_vm.sh --recreate`)*

**Interactive Prompts & Behavior**:
1. **GCP Project ID Selection**:
   The script inspects your active `gcloud` configuration and presents the current project ID as default (e.g. `maf-testing-387011`). You can press **Enter** to accept the default or type a different Project ID (e.g. `pradeesi-ai-demo`).
2. **Compute Zone Selection**:
   Defaults to `us-central1-a` (or press Enter).
3. **Automated Infrastructure Provisioning**:
   * Auto-detects available regional VPC networks (e.g. `default-vpc` or `default`).
   * Configures the dedicated, least-privilege service account `apexfin-demo-sa` with `roles/aiplatform.user`.
   * Configures the tag-scoped VPC ingress firewall rule (`apexfin-demo-allow-5000`) for TCP port 5000.
   * Provisions an `e2-standard-2` (2 vCPUs, 8 GB RAM) Ubuntu 22.04 LTS Compute Engine VM (`apexfin-demo-vm`).
   * Executes an automated startup script on the VM that:
     * Installs Python 3, pip, venv, git, curl, unzip, and `iputils-ping`.
     * Pre-installs the **CodeMender CLI (`cm`)** binary in `/usr/local/bin/cm` directly from Google's Artifact Registry.
     * Deploys the ApexFin banking application code into `/opt/apexfin`.
     * Sets up a dedicated Python virtualenv, installs requirements, seeds `apexfin.db`, and initializes Git.
     * Creates and starts a managed `systemd` daemon (`apexfin.service`) bound to port 5000.
4. **Access Endpoints Output**:
   The script automatically resolves the external IP and provides:
   * **Direct Public Web URL**:
     ```text
     http://<EXTERNAL_IP>:5000
     ```
     *(Accessible immediately in any browser from anywhere during the customer presentation)*.
   * **Cloud Shell / Local Port Forwarding**:
     ```bash
     gcloud compute ssh apexfin-demo-vm --zone=us-central1-a --project=YOUR_PROJECT_ID -- -L 5000:localhost:5000
     ```
     *(Allows viewing the demo in Cloud Shell Web Preview or localhost:5000 if customer network policies block port 5000)*.
   * **SSH Access to Run CodeMender on the VM**:
     ```bash
     gcloud compute ssh apexfin-demo-vm --zone=us-central1-a --project=YOUR_PROJECT_ID
     ```
     Inside the VM:
     ```bash
     cd /opt/apexfin
     cm find ./app.py
     cm verify <FINDING_ID>
     cm fix <FINDING_ID>
     ```

---

### 2. Automated Deprovisioning & Teardown (`./deprovision_vm.sh`)

Once your customer presentation or workshop is complete, clean up all cloud assets with a single command:

```bash
./deprovision_vm.sh
```

*(Or auto-confirm with `./deprovision_vm.sh -y`)*

**What the script does**:
1. Prompts for the Project ID (defaulting to your current active project).
2. Confirms deletion with a safety prompt (`y/N`).
3. Deletes the Compute Engine instance `apexfin-demo-vm` and its boot disk.
4. Deletes the VPC firewall rule `apexfin-demo-allow-5000`.
5. Deletes the isolated service account `apexfin-demo-sa`.
6. Cleans up any local temporary bundles.
7. Guarantees **zero dangling cloud infrastructure, zero ongoing charges, and zero side effects to other project resources**.

---

## Cloud Deployment Playbooks (Cloud Run & GKE)

### Target 1: Google Cloud Run (Recommended for Serverless Demos)

1. **Authenticate and set project**:
   ```bash
   gcloud auth login
   gcloud config set project maf-testing-387011
   ```

2. **Deploy directly from source**:
   ```bash
   gcloud run deploy apexfin-banking-portal \
       --source . \
       --region us-central1 \
       --platform managed \
       --allow-unauthenticated \
       --port 5000
   ```

3. **Verify Deployment**:
   ```bash
   gcloud run services describe apexfin-banking-portal --region us-central1 --format='value(status.url)'
   ```

---

### Target 2: Google Kubernetes Engine (GKE)

1. **Build and push container image using Cloud Build**:
   ```bash
   export PROJECT_ID=$(gcloud config get-value project)
   gcloud builds submit --tag gcr.io/$PROJECT_ID/apexfin-banking-portal:v1 .
   ```

2. **Deploy Kubernetes Manifest**:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: apexfin-banking-deployment
     labels:
       app: apexfin-banking
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: apexfin-banking
     template:
       metadata:
         labels:
           app: apexfin-banking
       spec:
         containers:
         - name: apexfin-app
           image: gcr.io/PROJECT_ID/apexfin-banking-portal:v1
           ports:
           - containerPort: 5000
           livenessProbe:
             httpGet:
               path: /healthz
               port: 5000
             initialDelaySeconds: 10
             periodSeconds: 15
           resources:
             limits:
               cpu: "500m"
               memory: "512Mi"
             requests:
               cpu: "100m"
               memory: "128Mi"
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: apexfin-banking-service
   spec:
     type: LoadBalancer
     selector:
       app: apexfin-banking
     ports:
     - port: 80
       targetPort: 5000
   ```

3. **Apply manifest**:
   ```bash
   kubectl apply -f deployment.yaml
   ```
