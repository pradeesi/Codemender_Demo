"""
Vulnerable Demo Application for CodeMender (Annotated Version)
==============================================================
This is a lightweight Flask application built to demonstrate CodeMender's
agentic capabilities: discovering, verifying, and patching security flaws.

Vulnerabilities Included:
1. CWE-89: SQL Injection (in /api/user)
2. CWE-78: OS Command Injection (in /api/ping)
"""

import os
import sqlite3
import subprocess
from flask import Flask, request, jsonify

app = Flask(__name__)
DB_FILE = "demo.db"


def init_db():
    """Initializes a simple in-memory or SQLite database with seed data."""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE,
            email TEXT,
            role TEXT
        )
    """)
    cursor.execute("SELECT COUNT(*) FROM users")
    if cursor.fetchone()[0] == 0:
        cursor.executemany(
            "INSERT INTO users (username, email, role) VALUES (?, ?, ?)",
            [
                ("alice", "alice@example.com", "admin"),
                ("bob", "bob@example.com", "developer"),
                ("charlie", "charlie@example.com", "analyst"),
            ]
        )
        conn.commit()
    conn.close()


# ==============================================================================
# VULNERABILITY 1: SQL Injection (CWE-89)
# ==============================================================================
# Flaw:
#   The user-provided 'username' query parameter is concatenated directly into
#   the SQL query string using Python string formatting (f-string).
#
# Threat / Exploit:
#   An attacker can supply input such as:
#       alice' OR '1'='1
#   which alters the SQL logic, bypassing access controls and leaking records.
#
# Safe Remediation (How CodeMender should fix this):
#   Use parameterized queries with placeholders:
#       cursor.execute("SELECT id, username, email, role FROM users WHERE username = ?", (username,))
# ==============================================================================
@app.route("/api/user", methods=["GET"])
def get_user():
    username = request.args.get("username", "")
    if not username:
        return jsonify({"error": "Missing 'username' parameter"}), 400

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    # VULNERABLE: Direct string interpolation into raw SQL query
    query = f"SELECT id, username, email, role FROM users WHERE username = '{username}'"
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    users = [{"id": r[0], "username": r[1], "email": r[2], "role": r[3]} for r in rows]
    return jsonify({"count": len(users), "users": users}), 200


# ==============================================================================
# VULNERABILITY 2: OS Command Injection (CWE-78)
# ==============================================================================
# Flaw:
#   The user-provided 'host' parameter is directly passed into a shell command
#   executed with `shell=True` in subprocess.check_output.
#
# Threat / Exploit:
#   An attacker can append arbitrary shell commands using semicolons or pipes:
#       8.8.8.8; whoami
#       8.8.8.8 && id
#   This allows arbitrary remote command execution (RCE) on the server.
#
# Safe Remediation (How CodeMender should fix this):
#   1. Validate the host format (e.g., using ipaddress or regex).
#   2. Avoid `shell=True`, passing arguments as a safe list:
#       subprocess.check_output(["ping", "-c", "1", "-W", "1", host])
# ==============================================================================
@app.route("/api/ping", methods=["GET"])
def ping_host():
    host = request.args.get("host", "")
    if not host:
        return jsonify({"error": "Missing 'host' parameter"}), 400

    # VULNERABLE: Untrusted user input passed directly to shell execution
    command = f"ping -c 1 -W 1 {host}"
    try:
        output = subprocess.check_output(command, shell=True, stderr=subprocess.STDOUT, text=True)
        return jsonify({"status": "success", "output": output}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"status": "failed", "output": e.output}), 500


if __name__ == "__main__":
    init_db()
    app.run(host="127.0.0.1", port=5000, debug=False)
