"""
Purpose: Core Flask web application for the ApexFin Banking Portal demonstration.
Architecture/Context: Enterprise banking portal with web front-end routes and backend REST APIs.
Dependencies/Side Effects: Interacts with SQLite database via database.py; invokes system ping commands for gateway diagnostics.
"""

import os
import sqlite3
import subprocess
import logging
from typing import Tuple, Dict, Any, Union
from flask import Flask, render_template, request, jsonify, redirect, url_for, flash
from database import get_db_connection, init_db, DEFAULT_DB_PATH

# Configure structured semantic logging
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("apexfin.app")

app = Flask(__name__)
# Secret key loaded securely from environment variable
app.secret_key = os.getenv("SECRET_KEY", "apexfin-dev-secret-key-391823901")

# Ensure database exists upon application start
init_db()


@app.route("/")
def index() -> str:
    """
    Render main banking portal dashboard with overview statistics and recent transactions.

    Parameters:
        None

    Returns:
        str: Rendered HTML template for dashboard.

    Exceptions/Errors:
        sqlite3.Error: Handled by returning empty datasets if database access fails.
    """
    logger.info("Serving banking overview dashboard")
    conn = get_db_connection()
    cursor = conn.cursor()

    # Query public commercial accounts summary
    cursor.execute("SELECT COUNT(*) AS total_accounts, SUM(balance) AS total_assets FROM accounts WHERE is_confidential = 0")
    stats = cursor.fetchone()

    # Query recent wire transfers
    cursor.execute("SELECT * FROM wire_transfers ORDER BY id DESC LIMIT 5")
    recent_wires = cursor.fetchall()
    conn.close()

    return render_template("index.html", stats=stats, recent_wires=recent_wires)


@app.route("/accounts")
def accounts_view() -> str:
    """
    Render account search page and execute user-supplied filter query.

    VULNERABILITY NOTE (FOR CODEMENDER DEMO):
    Contains CWE-89 (SQL Injection) via direct string concatenation in query construction.
    An attacker can inject SQL syntax to bypass is_confidential=0 filters and extract classified bank reserves.

    Parameters:
        None (Reads query parameters: 'q' and 'type')

    Returns:
        str: Rendered HTML template displaying filtered bank accounts.
    """
    search_term = request.args.get("q", "").strip()
    account_type = request.args.get("type", "ALL").strip()

    conn = get_db_connection()
    cursor = conn.cursor()

    # Intentional CWE-89 Vulnerability:
    # Direct f-string formatting into SQL statement allows SQL injection payloads
    # e.g., ' OR '1'='1' --
    if search_term:
        # Intentional CWE-89 Vulnerability:
        # String concatenation allows SQL injection to break out and comment out the confidentiality clause
        query = f"SELECT id, account_number, customer_name, email, account_type, balance, status, is_confidential FROM accounts WHERE customer_name LIKE '%{search_term}%' AND is_confidential = 0"
        logger.warning("Executing dynamic search query: %s", query)
    elif account_type and account_type != "ALL":
        query = f"SELECT id, account_number, customer_name, email, account_type, balance, status, is_confidential FROM accounts WHERE is_confidential = 0 AND account_type = '{account_type}'"
        logger.warning("Executing dynamic type query: %s", query)
    else:
        query = "SELECT id, account_number, customer_name, email, account_type, balance, status, is_confidential FROM accounts WHERE is_confidential = 0"

    try:
        cursor.execute(query)
        accounts = cursor.fetchall()
    except sqlite3.OperationalError as e:
        logger.error("SQL operational error during query execution: %s", str(e))
        flash(f"Database Query Error: {str(e)}", "danger")
        accounts = []

    conn.close()
    return render_template("accounts.html", accounts=accounts, search_term=search_term, account_type=account_type)


@app.route("/api/accounts", methods=["GET"])
def api_accounts() -> Tuple[Any, int]:
    """
    REST API endpoint for accounts lookup with filter options.

    VULNERABILITY NOTE (FOR CODEMENDER DEMO):
    Contains CWE-89 (SQL Injection) in REST API query string formatting.

    Parameters:
        None (Reads query parameter 'search')

    Returns:
        Tuple[Response, int]: JSON list of matching accounts and HTTP status code.
    """
    search_query = request.args.get("search", "")

    conn = get_db_connection()
    cursor = conn.cursor()

    # Intentional CWE-89 Vulnerability in REST API
    sql = f"SELECT account_number, customer_name, account_type, balance, status FROM accounts WHERE is_confidential = 0 AND customer_name LIKE '%{search_query}%'"
    try:
        cursor.execute(sql)
        rows = [dict(row) for row in cursor.fetchall()]
        return jsonify({"count": len(rows), "accounts": rows}), 200
    except sqlite3.Error as e:
        return jsonify({"error": str(e), "executed_query": sql}), 500
    finally:
        conn.close()


@app.route("/transfer", methods=["GET", "POST"])
def transfer_view() -> Union[str, Any]:
    """
    Render wire transfer dispatch page and process outbound payments.

    Parameters:
        None (Reads POST form data: sender, recipient, iban, amount, currency)

    Returns:
        Union[str, Response]: Rendered template on GET, redirect on successful POST.
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    if request.method == "POST":
        sender_acc = request.form.get("sender_account", "").strip()
        recipient_name = request.form.get("recipient_name", "").strip()
        recipient_iban = request.form.get("recipient_iban", "").strip()
        amount_str = request.form.get("amount", "0").strip()
        currency = request.form.get("currency", "USD").strip()

        try:
            amount = float(amount_str)
            if amount <= 0:
                raise ValueError("Amount must be positive.")

            # Generate synthetic wire transfer reference
            ref_id = f"WT-{os.urandom(3).hex().upper()}"

            cursor.execute("""
            INSERT INTO wire_transfers (reference_id, sender_account, recipient_name, recipient_iban, amount, currency, status)
            VALUES (?, ?, ?, ?, ?, ?, 'COMPLETED')
            """, (ref_id, sender_acc, recipient_name, recipient_iban, amount, currency))

            # Deduct balance from sender account
            cursor.execute("UPDATE accounts SET balance = balance - ? WHERE account_number = ?", (amount, sender_acc))
            conn.commit()

            flash(f"Wire transfer {ref_id} of {currency} {amount:,.2f} to {recipient_name} successfully dispatched!", "success")
            return redirect(url_for("transfer_view"))
        except ValueError as val_err:
            flash(f"Invalid transfer parameter: {str(val_err)}", "warning")
        except sqlite3.Error as db_err:
            flash(f"Database error recording transfer: {str(db_err)}", "danger")

    # Fetch available source accounts for dropdown
    cursor.execute("SELECT account_number, customer_name, balance FROM accounts WHERE is_confidential = 0")
    source_accounts = cursor.fetchall()

    cursor.execute("SELECT * FROM wire_transfers ORDER BY id DESC LIMIT 10")
    transfers = cursor.fetchall()
    conn.close()

    return render_template("transfer.html", source_accounts=source_accounts, transfers=transfers)


@app.route("/system-diagnostics", methods=["GET", "POST"])
def diagnostics_view() -> str:
    """
    Render banking infrastructure gateway diagnostics tool.

    VULNERABILITY NOTE (FOR CODEMENDER DEMO):
    Contains CWE-78 (OS Command Injection).
    The host parameter is directly concatenated into a shell command and executed using shell=True.
    An attacker can append shell operators (e.g., '; id', '| whoami', '& cat /etc/passwd')
    to gain remote code execution on the underlying host or container.

    Parameters:
        None (Reads POST form data: host)

    Returns:
        str: Rendered HTML template displaying ping diagnostics results.
    """
    command_output = ""
    target_host = "127.0.0.1"

    if request.method == "POST":
        target_host = request.form.get("host", "127.0.0.1").strip()

        # Intentional CWE-78 Vulnerability:
        # String concatenation directly into shell=True invocation
        cmd = f"ping -c 2 {target_host}"
        logger.warning("Executing system diagnostic command: %s", cmd)

        try:
            # shell=True combined with unescaped input triggers command injection
            proc = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=10
            )
            command_output = proc.stdout if proc.stdout else proc.stderr
        except subprocess.TimeoutExpired:
            command_output = "Diagnostic execution timed out after 10 seconds."
        except Exception as e:
            command_output = f"Execution error: {str(e)}"

    return render_template("diagnostics.html", output=command_output, target_host=target_host)


@app.route("/api/ping", methods=["GET"])
def api_ping() -> Tuple[Any, int]:
    """
    REST API endpoint for automated banking gateway connectivity probes.

    VULNERABILITY NOTE (FOR CODEMENDER DEMO):
    Contains CWE-78 (OS Command Injection) via request query parameters.

    Parameters:
        None (Reads query parameter 'host')

    Returns:
        Tuple[Response, int]: JSON response with command output and status code.
    """
    host = request.args.get("host", "127.0.0.1")

    # Intentional CWE-78 Command Injection in API
    cmd = f"ping -c 1 {host}"
    try:
        output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, text=True, timeout=5)
        return jsonify({"host": host, "status": "REACHABLE", "output": output}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"host": host, "status": "UNREACHABLE", "output": e.output}), 502
    except subprocess.TimeoutExpired:
        return jsonify({"host": host, "status": "TIMEOUT", "output": "Probe timed out"}), 504


@app.route("/healthz")
def healthz() -> Tuple[Any, int]:
    """
    Standard liveness and readiness probe endpoint for Cloud Run and GKE.

    Parameters:
        None

    Returns:
        Tuple[Response, int]: Health status JSON and HTTP 200 code.
    """
    return jsonify({"status": "HEALTHY", "service": "apexfin-banking-portal"}), 200


if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    host = os.getenv("HOST", "0.0.0.0")
    debug_mode = os.getenv("FLASK_DEBUG", "0") == "1"
    logger.info("Starting ApexFin Banking Portal on %s:%d (debug=%s)", host, port, debug_mode)
    app.run(host=host, port=port, debug=debug_mode)
