#!/usr/bin/env bash
# ==============================================================================
# Purpose: Environment rollback and reset script for ApexFin Banking Portal demo.
# Architecture/Context: Restores the codebase, database, and running processes to a clean,
#                       pristine state ready for subsequent customer demonstrations.
# Dependencies/Side Effects: Kills running app processes, resets SQLite database, cleans
#                            CodeMender session artifacts, and discards uncommitted Git changes.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_PID_FILE="$SCRIPT_DIR/.app.pid"
PORT="${PORT:-5000}"

echo "============================================================"
echo "🔄 ApexFin Global Bank - Customer Demo Environment Rollback"
echo "============================================================"

# Step 1: Stop Running Application Instance
echo "🛑 Stopping any running application processes..."
if [[ -f "$APP_PID_FILE" ]]; then
    PID=$(cat "$APP_PID_FILE" 2>/dev/null || true)
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        echo "   Terminating PID: $PID..."
        kill "$PID" || true
        sleep 1
    fi
    rm -f "$APP_PID_FILE"
fi

# Fallback: kill any orphaned python process listening on target PORT
if command -v lsof &>/dev/null; then
    ORPHAN_PIDS=$(lsof -ti :"$PORT" 2>/dev/null || true)
    if [[ -n "$ORPHAN_PIDS" ]]; then
        echo "   Clearing orphaned listeners on port $PORT (PIDs: $ORPHAN_PIDS)..."
        echo "$ORPHAN_PIDS" | xargs kill -9 2>/dev/null || true
    fi
fi

# Step 2: Reset Git Code Modifications (Discard Patches Applied by CodeMender)
if [[ -d ".git" ]]; then
    echo "🧹 Discarding uncommitted Git modifications and CodeMender patches..."
    git checkout HEAD -- . 2>/dev/null || true
    git clean -fd -e .venv 2>/dev/null || true

    # Delete any temporary CodeMender candidate branches created during 'cm fix'
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    if git branch | grep -q "cm-"; then
        echo "   Deleting temporary CodeMender branches..."
        git branch | grep "cm-" | xargs git branch -D 2>/dev/null || true
    fi
fi

# Step 3: Reset SQLite Database & Seed Clean Data
echo "🗄️ Resetting banking database..."
rm -f apexfin.db test_apexfin.db

if [[ -f ".venv/bin/python3" ]]; then
    .venv/bin/python3 database.py
elif command -v python3 &>/dev/null; then
    python3 database.py
fi

# Step 4: Clean CodeMender State & Findings Cache (if present)
echo "🧹 Cleaning local CodeMender execution state..."
if command -v cm &>/dev/null; then
    cm clean --yes 2>/dev/null || true
fi
rm -rf .codemender .cm_project ~/.codemender/artifacts/* 2>/dev/null || true
rm -f app.log

# Step 5: Verify Environment Health
echo "🧪 Running unit tests to verify pristine state..."
if [[ -f ".venv/bin/python3" ]]; then
    .venv/bin/python3 -m unittest test_app.py
elif command -v python3 &>/dev/null; then
    python3 -m unittest test_app.py
fi

echo "============================================================"
echo "✅ Environment successfully rolled back to pristine baseline!"
echo "🎯 The application and codebase are 100% ready for the next customer demo."
echo "💡 Run './deploy.sh' when you are ready to start the presentation."
echo "============================================================"
