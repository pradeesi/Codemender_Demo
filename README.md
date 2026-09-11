# CodeMender Customer Demo: SQL Injection Remediation

This project is a lightweight, easy-to-explain Python (Flask) web application designed specifically to showcase **Google Cloud CodeMender**'s three-stage agentic workflow: **Find**, **Verify**, and **Fix**.

**Author**: Pradeep Singh  
**Disclaimer**: *This repository contains intentionally vulnerable demonstration code created exclusively for educational and testing purposes. It is provided "AS IS", without warranty of any kind, express or implied. Do not deploy or use this code in production environments.*

---

## 🎯 Files in this Directory

* **[`app.py`](app.py)** (Main File): Interactive Flask web application with a search UI and REST API containing an intentional SQL injection vulnerability.
* **[`app_annotated.py`](app_annotated.py)**: Annotated reference version containing detailed threat models, exploits, and remediation details for your own reference.
* **[`test_app.py`](test_app.py)**: Unit tests verifying baseline functionality (used by CodeMender for regression checks).
* **[`requirements.txt`](requirements.txt)**: Minimal project dependencies (`flask`).

---

## 🔍 Vulnerability Present in [`app.py`](app.py)

| Endpoint | Vulnerability | CWE | What it Does | Expected Exploit |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` and `GET /api/user?username=` | **SQL Injection** | [CWE-89](https://cwe.mitre.org/data/definitions/89.html) | Direct string formatting into SQLite query: `f"SELECT ... WHERE username = '{username}'"` | `alice' OR '1'='1` dumps unauthorized user records. |

---

## 🚀 Step-by-Step Customer Demo Guide

Follow these steps during a live customer presentation or demo.

### Step 0: Prerequisites & Setup

Run these commands in your Cloud Shell terminal:

```bash
cd /home/admin_/Codemender_Demo

# 1. Install dependencies
pip install -r requirements.txt

# 2. Verify baseline tests pass
python3 test_app.py

# 3. Authenticate with Google Cloud Application Default Credentials (ADC)
gcloud auth application-default login

# 4. Verify CodeMender CLI is installed
cm --version

# 5. Initialize CodeMender workspace (one-time setup)
cm init
```

---

### Step 1: Start the Web Application & Show the Live Vulnerability (The Hook)

Start the Flask server:
```bash
python3 app.py
```
*(The server will start on `http://127.0.0.1:5000`)*

#### In the Browser:
1. Open Cloud Shell **Web Preview** on port `5000` (or visit `http://127.0.0.1:5000/`).
2. Click **`1. Normal Search (alice)`**:
   * Returns only Alice's record (1 row) with a green status alert.
3. Click **`3. Exploit (alice' OR '1'='1')`**:
   * Triggers the SQL injection and dumps all 3 database records (Alice, Bob, Charlie).
   * Point out the **"Behind the scenes"** box displaying the unescaped query:
     ```sql
     SELECT id, username, email, role FROM users WHERE username = 'alice' OR '1'='1'
     ```

> **🎙️ Talking Point for the Customer:**  
> *"Dynamic string concatenation in SQL queries remains one of the most common web security vulnerabilities (CWE-89). Now let's see how CodeMender autonomously discovers and proves this vulnerability without noisy static alerts."*

---

### Step 2: Discover the Vulnerability (`cm find`)

Open a new terminal tab and scan the codebase with CodeMender:

```bash
cd /home/admin_/Codemender_Demo
cm find . --compact
```
*(Or target the file directly: `cm find ./app.py --compact`)*

#### What the Customer Sees:
* CodeMender scans the project with DeepMind security-specialized LLMs.
* It pinpoints the exact file and line numbers in [`app.py`](app.py).
* Identifies **CWE-89: SQL Injection** and displays an explanation of the risk.

> **🎙️ Talking Point for the Customer:**  
> *"Traditional static analysis tools (SAST) flood developers with dozens of false positives and theoretical warnings. CodeMender understands code semantics and context, cutting out noise to highlight real vulnerabilities."*

---

### Step 3: Actively Prove Exploitability in Sandbox (`cm verify`)

This is the central differentiator of CodeMender:

```bash
cm verify . --compact
```
*(Or target the file directly: `cm verify ./app.py --compact`)*

#### What the Customer Sees:
* CodeMender spins up an isolated local sandbox.
* It synthesizes a proof-of-concept exploit payload (`' OR '1'='1`).
* It executes the exploit against the local application and captures the unauthorized database records.
* Marks the finding as **VERIFIED / EXPLOITABLE**.

> **🎙️ Talking Point for the Customer:**  
> *"This is CodeMender's key differentiator: **Active Proof of Exploitability**. CodeMender doesn't just guess—it safely constructs a reproduction payload inside an isolated sandbox to confirm if the vulnerability is truly exploitable before notifying security engineers."*

---

### Step 4 (Optional): Autonomous Remediation (`cm fix`)

If the customer asks *"Can it fix the issue for us?"*, explain how CodeMender repairs the code:

```bash
cm fix ./app.py --compact
```

#### What You Can Explain:
1. **Autonomous Patching**: CodeMender replaces string concatenation with parameterized queries (`WHERE username = ?`).
2. **Regression Testing**: It automatically runs [`test_app.py`](test_app.py) to guarantee the fix doesn't break existing functionality.
3. **Human in the Loop**: Displays a clean Git diff for developer review before anything is committed.

---

## 📋 Demo Cheat Sheet

| Step | Action / Command | What to Highlight |
| :--- | :--- | :--- |
| **0. Test** | `python3 test_app.py` | 5 unit tests pass cleanly |
| **1. Hook** | `http://127.0.0.1:5000/` | Interactive web UI: normal search vs `' OR '1'='1` exploit |
| **2. Find** | `cm find . --compact` | Pinpoints CWE-89 in [`app.py`](app.py) without noise |
| **3. Verify** | `cm verify . --compact` | Safely executes exploit payload in sandbox to confirm threat |
| **4. Fix** | `cm fix ./app.py --compact` | Parameterizes query, verifies unit tests pass, shows git diff |

---

## 🔄 Resetting the Demo for Another Customer

When you run `cm fix`, CodeMender modifies [`app.py`](app.py) to secure the code. To reset everything back to the vulnerable state for your next customer presentation:

```bash
cd /home/admin_/Codemender_Demo

# 1. Reset code back to the vulnerable baseline (via CodeMender or Git)
cm vcs reset --force
# (Or: git reset --hard origin/main)

# 2. Clear CodeMender's local findings cache and generated reports
cm clean

# 3. Restart the Flask app if needed
python3 app.py
```
Your workspace is now completely fresh and ready for the next demo!

