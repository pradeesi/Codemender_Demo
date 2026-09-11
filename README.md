# CodeMender Customer Demo: Vulnerability Remediation

This project is a lightweight, easy-to-explain Python (Flask) service designed specifically to showcase **Google Cloud CodeMender**'s three-stage agentic workflow: **Find**, **Verify**, and **Fix**.

---

## 🎯 Files in this Directory

* **[`app.py`](app.py)** (Main File): Clean application (~60 lines) without comments detailing vulnerabilities. Use this for the live scanning test.
* **[`app_annotated.py`](app_annotated.py)**: Annotated reference version containing detailed threat models, exploits, and remediation details for your own reference.
* **[`test_app.py`](test_app.py)**: Unit tests verifying baseline functionality (used by CodeMender for regression checks).
* **[`requirements.txt`](requirements.txt)**: Minimal project dependencies (`flask`).

---

## 🔍 Vulnerabilities Present in [`app.py`](app.py)

| Endpoint | Vulnerability | CWE | What it Does | Expected Exploit |
| :--- | :--- | :--- | :--- | :--- |
| `GET /api/user?username=` | **SQL Injection** | [CWE-89](https://cwe.mitre.org/data/definitions/89.html) | Direct string formatting into SQLite query: `f"SELECT ... WHERE username = '{username}'"` | `alice' OR '1'='1` dumps unauthorized user records. |
| `GET /api/ping?host=` | **OS Command Injection** | [CWE-78](https://cwe.mitre.org/data/definitions/78.html) | Direct string formatting into `subprocess.check_output(..., shell=True)` | `127.0.0.1; whoami` executes arbitrary OS commands. |

---

## 💻 1. Commands to Run and Test the Application

### 1.1 Install Dependencies
```bash
cd /home/admin_/Codemender_Demo
pip install -r requirements.txt
```

### 1.2 Run Unit Tests
Verify baseline functionality passes:
```bash
python3 test_app.py
```

### 1.3 Start the Flask Server
```bash
python3 app.py
```
*(The server will start on `http://127.0.0.1:5000`)*

### 1.4 Test Legitimate Requests (in another terminal)
```bash
# Legitimate user lookup
curl "http://127.0.0.1:5000/api/user?username=alice"

# Legitimate network ping
curl "http://127.0.0.1:5000/api/ping?host=127.0.0.1"
```

### 1.5 Demonstrate the Vulnerabilities (Before CodeMender)
Show the customer how these vulnerabilities can be actively exploited:

```bash
# 1. SQL Injection: Bypass query logic to leak all users in the database
curl "http://127.0.0.1:5000/api/user?username=alice'%20OR%20'1'='1"

# 2. Command Injection: Inject arbitrary shell commands (e.g., whoami, id)
curl "http://127.0.0.1:5000/api/ping?host=127.0.0.1;whoami"
```

---

## 🤖 2. Exact CodeMender CLI Commands

### 2.1 Prerequisites & Authentication
Ensure your Google Cloud credentials and environment are configured:

```bash
# Authenticate using Google Cloud Application Default Credentials (ADC)
gcloud auth application-default login

# Ensure 'cm' CLI binary is in your PATH (e.g., if unzipped from cm-linux-amd64.zip)
export PATH="$HOME/.local/bin:$PATH"
cm --version
```

---

### 2.2 Step 1: Scan and Discover (`cm find`)
Scan the codebase to find vulnerabilities using CodeMender's DeepMind security-specialized prompts:

```bash
cd /home/admin_/Codemender_Demo

# Scan current directory with rolling status line
cm find . --compact

# Optional: explicitly specify model (default: gemini-3.7-flash)
cm find . --compact --model gemini-3.7-flash

# Or target specific file directly
cm find ./app.py --compact
```

> **Talking Point for Customer**: Unlike legacy static analysis tools that flood teams with theoretical warnings, CodeMender pinpoints exact context and explains the exploit vector.

---

### 2.3 Step 2: Actively Prove Exploitability (`cm verify`)
Have CodeMender attempt to construct test cases and verify whether the findings are actually exploitable inside the local sandbox:

```bash
# Actively verify discovered vulnerabilities
cm verify . --compact

# Target specific file
cm verify ./app.py --compact
```

> **Talking Point for Customer**: CodeMender builds the code and safely attempts reproduction in a local process sandbox. This drastically reduces false positives so engineers only spend time on real, exploitable threats.

---

### 2.4 Step 3: Autonomous Remediation (`cm fix`)
Ask CodeMender to generate language-compatible patches and validate that tests still pass:

```bash
# Fix and patch verified vulnerabilities
cm fix . --compact

# Target specific file
cm fix ./app.py --compact
```

> **Talking Point for Customer**: CodeMender does not just give generic advice—it writes the secure patch (parameterizing the SQL query and eliminating `shell=True`), runs [`test_app.py`](test_app.py) to prevent regressions, and displays the git diff for review before accepting.

---

### 2.5 Optional: Resuming Sessions
If a scan or fix operation was paused or interrupted:

```bash
# Resume an existing CodeMender session
cm session resume --compact
```
