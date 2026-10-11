#!/usr/bin/env bash
# ==============================================================================
# Author: Pradeep Singh
# License: Apache-2.0
# Purpose: Automated deployment script for ApexFin Banking Portal.
# Architecture/Context: Runs from GCP Cloud Shell by default to provision an
#                       isolated Google Compute Engine Linux VM via provision_vm.sh.
# Dependencies/Side Effects: Delegates to provision_vm.sh by default (or sets up
#                            local Python venv and SQLite DB when --local is passed).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${PORT:-5000}"
HOST="${HOST:-0.0.0.0}"
APP_PID_FILE="$SCRIPT_DIR/.app.pid"
VENV_DIR="$SCRIPT_DIR/.venv"

MODE="vm"
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm)
            MODE="vm"
            shift
            ;;
        --local)
            MODE="local"
            shift
            ;;
        --project|-p)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Error: --project requires a Google Cloud Project ID."
                exit 1
            fi
            FORWARD_ARGS+=("--project" "$2")
            shift 2
            ;;
        --region|-r)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Error: --region requires a Compute Engine region."
                exit 1
            fi
            FORWARD_ARGS+=("--region" "$2")
            shift 2
            ;;
        --zone|-z)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Error: --zone requires a Compute Engine zone."
                exit 1
            fi
            FORWARD_ARGS+=("--zone" "$2")
            shift 2
            ;;
        -y|--yes|--recreate)
            FORWARD_ARGS+=("$1")
            shift
            ;;
        -h|--help)
            echo "Usage: ./deploy.sh [--project|-p <PROJECT_ID>] [--zone|-z <ZONE>] [--region|-r <REGION>] [--recreate|-y]"
            echo ""
            echo "Default mode provisions the isolated Linux VM from GCP Cloud Shell."
            echo "If --project is omitted, an interactive numbered list of all available GCP projects is displayed."
            exit 0
            ;;
        -*)
            echo "❌ Unknown option: $1"
            echo "Usage: ./deploy.sh [--project|-p <PROJECT_ID>] [--zone|-z <ZONE>] [--region|-r <REGION>] [--recreate|-y]"
            exit 1
            ;;
        *)
            FORWARD_ARGS+=("$1")
            shift
            ;;
    esac
done

# Default deployment target: Isolated Google Compute Engine Linux VM (run from GCP Cloud Shell)
if [[ "$MODE" == "vm" ]]; then
    exec "$SCRIPT_DIR/provision_vm.sh" "${FORWARD_ARGS[@]}"
fi

echo "============================================================"
echo "🏦 ApexFin Global Bank - Local Service Setup"
echo "============================================================"

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
