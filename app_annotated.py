"""
Vulnerable Demo Application for CodeMender (Annotated Version)
==============================================================
This is a lightweight Flask application built to demonstrate CodeMender's
agentic capabilities: discovering, verifying, and patching security flaws.

Vulnerability Included:
- CWE-89: SQL Injection (in both the Web UI and /api/user)
"""

import os
import sqlite3
from flask import Flask, request, jsonify, render_template_string

app = Flask(__name__)
DB_FILE = "demo.db"


def init_db():
    """Initializes a simple SQLite database with seed data."""
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


HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SQL Injection Demo - User Lookup</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
        body { background: #f0f2f5; color: #1c1e21; padding: 30px 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        .card { background: white; border-radius: 12px; padding: 28px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); margin-bottom: 24px; }
        h1 { font-size: 24px; margin-bottom: 8px; color: #1a73e8; }
        p.subtitle { color: #5f6368; font-size: 14px; margin-bottom: 24px; }
        .search-box { display: flex; gap: 10px; margin-bottom: 16px; }
        input[type="text"] { flex: 1; padding: 12px 16px; font-size: 15px; border: 1px solid #dadce0; border-radius: 8px; outline: none; }
        input[type="text"]:focus { border-color: #1a73e8; box-shadow: 0 0 0 2px rgba(26,115,232,0.2); }
        button { background: #1a73e8; color: white; border: none; padding: 12px 24px; border-radius: 8px; font-size: 15px; font-weight: 500; cursor: pointer; }
        button:hover { background: #1557b0; }
        .quick-tests { display: flex; gap: 10px; align-items: center; margin-bottom: 20px; flex-wrap: wrap; }
        .quick-tests span { font-size: 13px; font-weight: 600; color: #70757a; }
        .btn-test { background: #e8f0fe; color: #1967d2; padding: 6px 14px; border-radius: 20px; font-size: 13px; text-decoration: none; font-weight: 500; transition: background 0.2s; }
        .btn-test:hover { background: #d2e3fc; }
        .btn-exploit { background: #fce8e6; color: #c5221f; }
        .btn-exploit:hover { background: #fad2cf; }
        .sql-box { background: #202124; color: #e8eaed; border-radius: 8px; padding: 16px; margin: 20px 0; font-family: 'Courier New', Courier, monospace; font-size: 14px; overflow-x: auto; }
        .sql-label { font-size: 12px; color: #9aa0a6; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #e0e0e0; font-size: 14px; }
        th { background: #f8f9fa; color: #5f6368; font-weight: 600; }
        .badge { padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: 600; text-transform: uppercase; }
        .badge-admin { background: #fce8e6; color: #c5221f; }
        .badge-dev { background: #e8f0fe; color: #1967d2; }
        .badge-analyst { background: #e6f4ea; color: #137333; }
        .alert { padding: 14px 18px; border-radius: 8px; font-size: 14px; margin: 16px 0; }
        .alert-warning { background: #fef7e0; border-left: 4px solid #f9ab00; color: #7c4a00; }
        .alert-success { background: #e6f4ea; border-left: 4px solid #137333; color: #137333; }
        .alert-info { background: #e8f0fe; border-left: 4px solid #1a73e8; color: #1967d2; }
        .explain-card h2 { font-size: 18px; margin-bottom: 12px; color: #202124; }
        .explain-card p { font-size: 14px; line-height: 1.6; color: #3c4043; margin-bottom: 12px; }
        .code-snippet { background: #f8f9fa; border: 1px solid #dadce0; border-radius: 6px; padding: 12px; font-family: monospace; font-size: 13px; color: #202124; margin: 8px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>Employee Directory</h1>
            <p class="subtitle">Demonstration of SQL Injection (CWE-89) in Python Flask</p>

            <form method="GET" action="/" class="search-box">
                <input type="text" name="username" placeholder="Search by username (e.g. alice)" value="{{ username }}">
                <button type="submit">Search</button>
            </form>

            <div class="quick-tests">
                <span>Quick tests:</span>
                <a href="/?username=alice" class="btn-test">1. Normal Search (alice)</a>
                <a href="/?username=bob" class="btn-test">2. Normal Search (bob)</a>
                <a href="/?username=alice%27+OR+%271%27%3D%271" class="btn-test btn-exploit">3. Exploit (alice' OR '1'='1)</a>
            </div>

            {% if username %}
                <div class="sql-box">
                    <div class="sql-label">Behind the scenes &mdash; Executed SQL Query</div>
                    <code>SELECT id, username, email, role FROM users WHERE username = '{{ username }}'</code>
                </div>

                {% if is_exploit %}
                    <div class="alert alert-warning">
                        <strong>⚠️ SQL Injection Successful!</strong> The input <code>' OR '1'='1</code> broke out of the string quotes. Because <code>'1'='1'</code> is always True, the database returned <strong>all {{ users|length }} records</strong> instead of just Alice.
                    </div>
                {% elif users|length == 1 %}
                    <div class="alert alert-success">
                        <strong>✓ Legitimate Query:</strong> Found 1 record matching username <code>{{ username }}</code>.
                    </div>
                {% else %}
                    <div class="alert alert-info">
                        Found {{ users|length }} record(s).
                    </div>
                {% endif %}

                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Username</th>
                            <th>Email</th>
                            <th>Role</th>
                        </tr>
                    </thead>
                    <tbody>
                        {% for user in users %}
                        <tr>
                            <td>{{ user.id }}</td>
                            <td><strong>{{ user.username }}</strong></td>
                            <td>{{ user.email }}</td>
                            <td>
                                {% if user.role == 'admin' %}
                                    <span class="badge badge-admin">{{ user.role }}</span>
                                {% elif user.role == 'developer' %}
                                    <span class="badge badge-dev">{{ user.role }}</span>
                                {% else %}
                                    <span class="badge badge-analyst">{{ user.role }}</span>
                                {% endif %}
                            </td>
                        </tr>
                        {% endfor %}
                    </tbody>
                </table>
            {% endif %}
        </div>

        <div class="card explain-card">
            <h2>💡 How does this SQL Injection work?</h2>
            <p>In <code>app.py</code>, user input is concatenated directly into the SQL query using Python string formatting:</p>
            <div class="code-snippet">
                query = f"SELECT ... WHERE username = '{username}'"
            </div>
            <p>When someone enters <code>alice' OR '1'='1</code>, the single quote closes the username field, turning the condition into an "OR true", forcing SQLite to return every record in the table.</p>
            <p><strong>The Fix:</strong> Use parameterized queries (prepared statements) with <code>?</code> placeholders:</p>
            <div class="code-snippet">
                cursor.execute("SELECT ... WHERE username = ?", (username,))
            </div>
        </div>
    </div>
</body>
</html>
"""


# ==============================================================================
# VULNERABILITY: SQL Injection (CWE-89)
# ==============================================================================
# Flaw:
#   The user-provided 'username' query parameter is concatenated directly into
#   the SQL query string using Python string formatting (f-string).
#
# Threat / Exploit:
#   An attacker can supply input such as:
#       alice' OR '1'='1
#   which alters the SQL logic, bypassing access controls and leaking all records.
#
# Safe Remediation (How CodeMender should fix this):
#   Use parameterized queries with placeholders:
#       cursor.execute("SELECT id, username, email, role FROM users WHERE username = ?", (username,))
# ==============================================================================
@app.route("/", methods=["GET"])
def index():
    """Web interface for searching users and demonstrating SQL injection."""
    username = request.args.get("username", "")
    users = []
    is_exploit = False

    if username:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()

        # VULNERABLE: Direct string formatting allows SQL Injection
        query = f"SELECT id, username, email, role FROM users WHERE username = '{username}'"
        cursor.execute(query)
        rows = cursor.fetchall()
        conn.close()

        users = [{"id": r[0], "username": r[1], "email": r[2], "role": r[3]} for r in rows]
        is_exploit = ("OR" in username.upper() or "1=1" in username or "'='") and len(users) > 1

    return render_template_string(HTML_TEMPLATE, username=username, users=users, is_exploit=is_exploit)


@app.route("/api/user", methods=["GET"])
def get_user():
    """REST API endpoint for user search (demonstrates SQL Injection)."""
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
    return jsonify({"count": len(users), "users": users, "query": query}), 200


if __name__ == "__main__":
    init_db()
    app.run(host="127.0.0.1", port=5000, debug=False)
