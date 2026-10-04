#!/usr/bin/env bash
# ==============================================================================
# Purpose: Automated deployment script for ApexFin Banking Portal.
# Architecture/Context: Orchestrates local Python virtual environment, dependencies,
#                       database initialization, and service startup (with optional Cloud Run flag).
# Dependencies/Side Effects: Creates/modifies .venv, creates apexfin.db, launches Flask on PORT.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${PORT:-5000}"
HOST="${HOST:-0.0.0.0}"
APP_PID_FILE="$SCRIPT_DIR/.app.pid"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "============================================================"
echo "🏦 ApexFin Global Bank - Automated Deployment"
echo "============================================================"

# Handle optional Cloud Run deployment
if [[ "${1:-}" == "--cloud-run" ]]; then
    PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}"
    if [[ -z "$PROJECT_ID" ]]; then
        echo "❌ Error: Google Cloud Project ID not set. Set GOOGLE_CLOUD_PROJECT or run 'gcloud config set project <ID>'."
        exit 1
    fi
    REGION="${REGION:-us-central1}"
    SERVICE_NAME="apexfin-banking-portal"

    echo "🚀 Deploying to Google Cloud Run in project: $PROJECT_ID ($REGION)..."
    gcloud run deploy "$SERVICE_NAME" \
        --source . \
        --project "$PROJECT_ID" \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --port 5000
    echo "✅ Cloud Run deployment complete."
    exit 0
fi

# Step 1: Ensure Python 3 is installed
if ! command -v python3 &>/dev/null; then
    echo "❌ Error: python3 is required but not installed."
    exit 1
fi

# Step 2: Virtual Environment Setup
if [[ ! -d "$VENV_DIR" ]]; then
    echo "📦 Creating Python virtual environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

echo "🔄 Activating virtual environment..."
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# Step 3: Install Dependencies
echo "📥 Installing application dependencies..."
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

# Step 4: Seed Database
echo "🗄️ Initializing SQLite database and seeding financial records..."
python3 database.py

# Step 5: Run Baseline Unit Tests
echo "🧪 Running unit test suite to verify baseline health..."
python3 -m unittest test_app.py

# Step 6: Stop any existing running instance
if [[ -f "$APP_PID_FILE" ]]; then
    OLD_PID=$(cat "$APP_PID_FILE" 2>/dev/null || true)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "🛑 Terminating previously running instance (PID: $OLD_PID)..."
        kill "$OLD_PID" || true
        sleep 1
    fi
    rm -f "$APP_PID_FILE"
fi

# Step 7: Launch Application
echo "🚀 Starting ApexFin Banking Portal on http://127.0.0.1:$PORT..."
nohup python3 app.py > app.log 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$APP_PID_FILE"

# Wait a brief moment and verify process is running
sleep 1.5
if kill -0 "$NEW_PID" 2>/dev/null; then
    echo "============================================================"
    echo "✅ Application successfully deployed and running!"
    echo "🌐 URL: http://127.0.0.1:$PORT"
    echo "🆔 PID: $NEW_PID (saved in .app.pid)"
    echo "📄 Logs: $SCRIPT_DIR/app.log"
    echo "============================================================"
    echo "💡 To stop or reset the demo for the next customer, run: ./reset_demo.sh"
else
    echo "❌ Server failed to start. Showing last log entries:"
    tail -n 20 app.log
    exit 1
fi
