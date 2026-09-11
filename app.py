import sqlite3
import subprocess
from flask import Flask, request, jsonify

app = Flask(__name__)
DB_FILE = "demo.db"


def init_db():
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


@app.route("/api/user", methods=["GET"])
def get_user():
    username = request.args.get("username", "")
    if not username:
        return jsonify({"error": "Missing 'username' parameter"}), 400

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    query = f"SELECT id, username, email, role FROM users WHERE username = '{username}'"
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    users = [{"id": r[0], "username": r[1], "email": r[2], "role": r[3]} for r in rows]
    return jsonify({"count": len(users), "users": users}), 200


@app.route("/api/ping", methods=["GET"])
def ping_host():
    host = request.args.get("host", "")
    if not host:
        return jsonify({"error": "Missing 'host' parameter"}), 400

    command = f"ping -c 1 -W 1 {host}"
    try:
        output = subprocess.check_output(command, shell=True, stderr=subprocess.STDOUT, text=True)
        return jsonify({"status": "success", "output": output}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"status": "failed", "output": e.output}), 500


if __name__ == "__main__":
    init_db()
    app.run(host="127.0.0.1", port=5000, debug=False)
