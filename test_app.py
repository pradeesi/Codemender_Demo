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

    def test_get_valid_user(self):
        """Test legitimate user lookup."""
        response = self.client.get("/api/user?username=alice")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["users"][0]["username"], "alice")

    def test_missing_user_param(self):
        """Test missing username returns 400."""
        response = self.client.get("/api/user")
        self.assertEqual(response.status_code, 400)

    def test_missing_ping_param(self):
        """Test missing host returns 400."""
        response = self.client.get("/api/ping")
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
