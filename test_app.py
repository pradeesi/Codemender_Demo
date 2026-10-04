"""
Purpose: Unit and regression test suite for ApexFin Banking Portal.
Architecture/Context: Executed by CodeMender build verification step (build.command).
Dependencies/Side Effects: Initializes an in-memory/temporary test database to validate application routes.
"""

import os
import unittest
import json
from app import app
from database import init_db, get_db_connection

TEST_DB = "test_apexfin.db"


class ApexFinBankingTestCase(unittest.TestCase):
    """
    Test suite for validating core banking workflows, route stability, and API health.
    """

    @classmethod
    def setUpClass(cls) -> None:
        """
        Configure test environment and initialize test database.
        """
        os.environ["DATABASE_PATH"] = TEST_DB
        app.config["TESTING"] = True
        init_db(TEST_DB)

    @classmethod
    def tearDownClass(cls) -> None:
        """
        Clean up temporary test database artifacts.
        """
        if os.path.exists(TEST_DB):
            try:
                os.remove(TEST_DB)
            except OSError:
                pass

    def setUp(self) -> None:
        """
        Set up Flask test client.
        """
        self.client = app.test_client()

    def test_healthz_endpoint(self) -> None:
        """
        Validate that the healthz endpoint returns HTTP 200 and healthy status.
        """
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data.decode("utf-8"))
        self.assertEqual(data["status"], "HEALTHY")

    def test_dashboard_view(self) -> None:
        """
        Validate that the main dashboard loads successfully and renders banking stats.
        """
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"ApexFin Global", response.data)

    def test_account_search_legitimate(self) -> None:
        """
        Verify standard account search by legitimate customer name.
        """
        response = self.client.get("/accounts?q=Alice")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Alice Johnson", response.data)
        # Verify that confidential accounts are NOT visible in normal queries
        self.assertNotIn(b"Executive Confidential Reserve", response.data)

    def test_api_accounts_search(self) -> None:
        """
        Verify accounts REST API endpoint with search query.
        """
        response = self.client.get("/api/accounts?search=Bob")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data.decode("utf-8"))
        self.assertGreaterEqual(data["count"], 1)
        self.assertEqual(data["accounts"][0]["customer_name"], "Bob Vance")

    def test_wire_transfer_submission(self) -> None:
        """
        Validate valid wire transfer submission flow.
        """
        payload = {
            "sender_account": "ACC-10001",
            "recipient_name": "Test Vendor Corp",
            "recipient_iban": "DE1234567890",
            "amount": "500.00",
            "currency": "USD"
        }
        response = self.client.post("/transfer", data=payload, follow_redirects=True)
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"successfully dispatched", response.data)

    def test_diagnostics_page_load(self) -> None:
        """
        Verify that the system diagnostics view renders the diagnostic form.
        """
        response = self.client.get("/system-diagnostics")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Banking Gateway &amp; SWIFT Diagnostics", response.data)


if __name__ == "__main__":
    unittest.main()
