"""
Unit Tests for CodeMender Demo Application
Author: Pradeep Singh

DISCLAIMER:
This is demonstration code designed exclusively for educational and testing
purposes. It is provided "AS IS", WITHOUT WARRANTY OF ANY KIND, express or
implied.
"""

import os
import unittest
import json
from app import app, init_db, DB_FILE


class AppTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Remove any leftover demo db
        if os.path.exists(DB_FILE):
            os.remove(DB_FILE)
        init_db()

    def setUp(self):
        self.client = app.test_client()

    def test_web_index(self):
        """Test home page loads with search form."""
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Employee Directory", response.data)
        self.assertIn(b"Quick tests", response.data)

    def test_web_search(self):
        """Test search query on web UI."""
        response = self.client.get("/?username=alice")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"alice@example.com", response.data)

    def test_get_valid_user_api(self):
        """Test legitimate user lookup via API."""
        response = self.client.get("/api/user?username=alice")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["users"][0]["username"], "alice")

    def test_missing_user_param_api(self):
        """Test missing username returns 400."""
        response = self.client.get("/api/user")
        self.assertEqual(response.status_code, 400)

    def test_sql_injection_exploit_api(self):
        """Test that SQL injection leaks all database users."""
        response = self.client.get("/api/user?username=alice'%20OR%20'1'='1")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data["count"], 3)


if __name__ == "__main__":
    unittest.main()
