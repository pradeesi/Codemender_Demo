"""
Purpose: Database initialization, connection management, and sample data seeding for ApexFin Banking Portal.
Architecture/Context: Data access layer managing SQLite storage for banking accounts and transactions.
Dependencies/Side Effects: Interacts with the local file system (SQLite database file specified via DATABASE_PATH).
"""

import os
import sqlite3
import logging
from typing import List, Dict, Any

# Configure structured semantic logging
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("apexfin.database")

DEFAULT_DB_PATH = os.getenv("DATABASE_PATH", "apexfin.db")


def get_db_connection(db_path: str = DEFAULT_DB_PATH) -> sqlite3.Connection:
    """
    Establish a connection to the SQLite banking database.

    Parameters:
        db_path (str): File system path to the SQLite database file.

    Returns:
        sqlite3.Connection: Active database connection configured with Row factory.

    Exceptions/Errors:
        sqlite3.Error: Raised if the database connection fails or file cannot be opened.
    """
    conn = sqlite3.connect(db_path)
    # Enable dict-like column access for template and JSON serializability
    conn.row_factory = sqlite3.Row
    return conn


def init_db(db_path: str = DEFAULT_DB_PATH) -> None:
    """
    Create banking schema tables and populate realistic seed data for customer demos.

    Parameters:
        db_path (str): File system path to initialize.

    Returns:
        None

    Exceptions/Errors:
        sqlite3.Error: Raised if DDL execution fails.
    """
    logger.info("Initializing ApexFin banking database at %s", db_path)
    conn = get_db_connection(db_path)
    cursor = conn.cursor()

    # Create banking accounts table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_number TEXT UNIQUE NOT NULL,
        customer_name TEXT NOT NULL,
        email TEXT NOT NULL,
        account_type TEXT NOT NULL,
        balance REAL NOT NULL,
        is_confidential INTEGER DEFAULT 0,
        status TEXT DEFAULT 'ACTIVE'
    )
    """)

    # Create wire transfers table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS wire_transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reference_id TEXT UNIQUE NOT NULL,
        sender_account TEXT NOT NULL,
        recipient_name TEXT NOT NULL,
        recipient_iban TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'USD',
        status TEXT NOT NULL DEFAULT 'COMPLETED',
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )
    """)

    # Seed initial accounts if table is empty
    cursor.execute("SELECT COUNT(*) AS cnt FROM accounts")
    if cursor.fetchone()["cnt"] == 0:
        logger.info("Seeding initial accounts and wire transactions...")
        sample_accounts = [
            ("ACC-10001", "Alice Johnson", "alice.j@corp.apexfin.com", "Commercial Checking", 452500.00, 0, "ACTIVE"),
            ("ACC-10002", "Bob Vance", "bob.vance@refrigeration.com", "Business Savings", 128450.50, 0, "ACTIVE"),
            ("ACC-10003", "Carol Danvers", "c.danvers@apexfin.com", "Personal Premier", 89400.00, 0, "ACTIVE"),
            ("ACC-10004", "David Miller", "dmiller@capitalventures.io", "Treasury Liquidity", 2750000.00, 0, "ACTIVE"),
            ("ACC-99999", "Executive Confidential Reserve", "board@apexfin-vault.internal", "Restricted Offshore", 48500000.00, 1, "CLASSIFIED"),
            ("ACC-88888", "SWIFT Nostro Settlement", "settlement@swift.apexfin.com", "Central Reserve", 912000000.00, 1, "CLASSIFIED")
        ]
        cursor.executemany("""
        INSERT INTO accounts (account_number, customer_name, email, account_type, balance, is_confidential, status)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, sample_accounts)

        sample_transfers = [
            ("WT-94812", "ACC-10001", "Acme Supplies International", "DE89370400440532013000", 25000.00, "USD", "COMPLETED"),
            ("WT-94813", "ACC-10002", "Midwest Logistics LLC", "US64SVBK12345678901234", 14350.25, "USD", "COMPLETED"),
            ("WT-94814", "ACC-10004", "EuroHedge Partners SA", "LU980001234567891234", 450000.00, "EUR", "COMPLETED"),
            ("WT-99999", "ACC-99999", "Cayman Secure Escrow Ltd", "KY12CBLE00000001234567", 5000000.00, "USD", "SETTLED")
        ]
        cursor.executemany("""
        INSERT INTO wire_transfers (reference_id, sender_account, recipient_name, recipient_iban, amount, currency, status)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, sample_transfers)

    conn.commit()
    conn.close()
    logger.info("Database initialization completed successfully.")


if __name__ == "__main__":
    init_db()
