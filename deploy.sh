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

MODE=""
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="apexfin-banking-portal"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm)
            MODE="vm"
            shift
            ;;
        --cloud-run|--run)
            MODE="cloud-run"
            shift
            ;;
        --local)
            MODE="local"
            shift
            ;;
        --project|-p)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region|-r)
            REGION="$2"
            shift 2
            ;;
        -*)
            echo "❌ Unknown option: $1"
            echo "Usage: ./deploy.sh [--vm | --cloud-run | --local] [--project <PROJECT_ID>] [--region <REGION>]"
            exit 1
            ;;
        *)
            if [[ -z "$PROJECT_ID" ]]; then
                PROJECT_ID="$1"
            fi
            shift
            ;;
    esac
done

# If project ID is provided or GCP environment is present, default to isolated VM
if [[ -z "$MODE" ]]; then
    if [[ -n "$PROJECT_ID" ]]; then
        MODE="vm"
    else
        MODE="local"
    fi
fi

# Delegate to VM provisioning (default for GCP deployments)
if [[ "$MODE" == "vm" ]]; then
    echo "🖥️ Deploying application to isolated Google Compute Engine Linux VM..."
    PROJECT_ID="$PROJECT_ID" REGION="$REGION" exec ./provision_vm.sh
fi

# Handle Cloud Run deployment
if [[ "$MODE" == "cloud-run" ]]; then
    DEFAULT_PROJECT="$(gcloud config get-value project 2>/dev/null || echo '')"
    if [[ -z "$PROJECT_ID" ]]; then
        if [[ -n "$DEFAULT_PROJECT" ]]; then
            read -r -p "Enter Google Cloud Project ID [$DEFAULT_PROJECT]: " USER_INPUT
            PROJECT_ID="${USER_INPUT:-$DEFAULT_PROJECT}"
        else
            read -r -p "Enter Google Cloud Project ID: " PROJECT_ID
        fi
    fi

    if [[ -z "$PROJECT_ID" ]]; then
        echo "❌ Error: Google Cloud Project ID is required for Cloud Run deployment."
        exit 1
    fi

    echo "🚀 Deploying to Google Cloud Run in project: $PROJECT_ID ($REGION)..."
    gcloud run deploy "$SERVICE_NAME" \
        --source . \
        --project "$PROJECT_ID" \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --port 5000 \
        --quiet

    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format="value(status.url)")

    echo ""
    echo "============================================================"
    echo "✅ Cloud Run deployment complete!"
    echo "🌐 Public Web UI URL: $SERVICE_URL"
    echo "============================================================"
    echo "💡 To deprovision or delete the Cloud Run service, run:"
    echo "   gcloud run services delete $SERVICE_NAME --project $PROJECT_ID --region $REGION --quiet"
    echo "============================================================"
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
