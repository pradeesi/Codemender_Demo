# CodeMender Customer Demo: SQL Injection Remediation

This project is a lightweight, easy-to-explain Python (Flask) web application designed specifically to showcase **Google Cloud CodeMender**'s three-stage agentic workflow: **Find**, **Verify**, and **Fix**.

---

## 🎯 Files in this Directory

* **[`app.py`](app.py)** (Main File): Interactive Flask web application with a search UI and REST API containing a SQL injection vulnerability.
* **[`app_annotated.py`](app_annotated.py)**: Annotated reference version containing detailed threat models, exploits, and remediation details for your own reference.
* **[`test_app.py`](test_app.py)**: Unit tests verifying baseline functionality (used by CodeMender for regression checks).
* **[`requirements.txt`](requirements.txt)**: Minimal project dependencies (`flask`).

---

## 🔍 Vulnerability Present in [`app.py`](app.py)

| Endpoint | Vulnerability | CWE | What it Does | Expected Exploit |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` and `GET /api/user?username=` | **SQL Injection** | [CWE-89](https://cwe.mitre.org/data/definitions/89.html) | Direct string formatting into SQLite query: `f"SELECT ... WHERE username = '{username}'"` | `alice' OR '1'='1` dumps unauthorized user records. |

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

### 1.4 Interactive Web Application (Browser)
Open your browser or Cloud Shell web preview on port `5000`:
* **Home Page**: `http://127.0.0.1:5000/`
* Use the built-in search box or click the one-click quick test buttons:
  1. **Normal Search**: Searches for `alice` (returns 1 legitimate record).
  2. **Exploit**: Injects `alice' OR '1'='1` (bypasses check, dumps all 3 records, and highlights the executed SQL query).

### 1.5 Command Line (curl)
```bash
# Legitimate user lookup
curl "http://127.0.0.1:5000/api/user?username=alice"

# SQL Injection exploit
curl "http://127.0.0.1:5000/api/user?username=alice'%20OR%20'1'='1"
```

---

## 🤖 2. Exact CodeMender CLI Commands

### 2.1 Prerequisites & Authentication
Ensure your Google Cloud credentials and environment are configured:

```bash
# Authenticate using Google Cloud Application Default Credentials (ADC)
gcloud auth application-default login

# Ensure 'cm' CLI binary is in your PATH
export PATH="$HOME/.local/bin:$PATH"
cm --version
```

---

### 2.2 Step 1: Scan and Discover (`cm find`)
Scan the codebase to find vulnerabilities using CodeMender:

```bash
cd /home/admin_/Codemender_Demo

# Scan current directory with rolling status line
cm find . --compact

# Or target specific file directly
cm find ./app.py --compact
```

> **Talking Point for Customer**: Unlike legacy static analysis tools that flood teams with theoretical warnings, CodeMender pinpoints exact context and explains the exploit vector.

---

### 2.3 Step 2: Actively Prove Exploitability (`cm verify`)
Have CodeMender construct test cases and verify whether the findings are actually exploitable:

```bash
cm verify . --compact
```

> **Talking Point for Customer**: CodeMender builds the code and safely attempts reproduction in a local process sandbox. This drastically reduces false positives so engineers only spend time on real, exploitable threats.

---

### 2.4 Step 3: Autonomous Remediation (`cm fix`)
Ask CodeMender to generate language-compatible patches and validate that tests still pass:

```bash
cm fix . --compact
```

> **Talking Point for Customer**: CodeMender writes the secure patch (parameterizing the SQL query with placeholders), runs [`test_app.py`](test_app.py) to prevent regressions, and displays the git diff for review before accepting.
