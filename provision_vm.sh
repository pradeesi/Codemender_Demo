#!/usr/bin/env bash
# ==============================================================================
# Author: Pradeep Singh
# License: Apache-2.0
# Purpose: Automated provisioning script for deploying ApexFin Banking Portal
#          and the CodeMender CLI onto a temporary, isolated Google Compute Engine VM.
# Architecture/Context: GCP Infrastructure-as-Code automation script for Customer Engineers (CEs)
#                       to run live security demos in an isolated cloud sandbox.
# Dependencies/Side Effects: Interacts with gcloud CLI, creates isolated service account,
#                            creates Compute Engine VM, VPC firewall rules, and provisions app.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VM_NAME="apexfin-demo-vm"
NETWORK_TAG="apexfin-demo-server"
FIREWALL_RULE="apexfin-demo-allow-5000"
SA_NAME="apexfin-demo-sa"
MACHINE_TYPE="e2-standard-2"
DEFAULT_ZONE="us-central1-a"

AUTO_RECREATE=false
PROJECT_ID="${PROJECT_ID:-}"
ZONE="${ZONE:-}"
REGION="${REGION:-}"

usage() {
    echo "Usage: ./provision_vm.sh [--project|-p <PROJECT_ID>] [--zone|-z <ZONE>] [--region|-r <REGION>] [--recreate|-y]"
    echo ""
    echo "Options:"
    echo "  -p, --project <PROJECT_ID>  Target Google Cloud Project ID (if omitted, displays an interactive numbered list)"
    echo "  -z, --zone <ZONE>           Compute Engine Zone (default: $DEFAULT_ZONE)"
    echo "  -r, --region <REGION>       Compute Engine Region (auto-resolves zone if specified)"
    echo "  -y, --yes, --recreate       Automatically recreate VM if it already exists"
    echo "  -h, --help                  Show this help message"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Error: --project requires a Google Cloud Project ID."
                exit 1
            fi
            PROJECT_ID="$2"
            shift 2
            ;;
        -z|--zone)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Error: --zone requires a Compute Engine zone."
                exit 1
            fi
            ZONE="$2"
            shift 2
            ;;
        -r|--region)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Error: --region requires a Compute Engine region."
                exit 1
            fi
            REGION="$2"
            shift 2
            ;;
        -y|--yes|--recreate)
            AUTO_RECREATE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "❌ Unknown option: $1"
            usage
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

echo "================================================================================"
echo "🏦 ApexFin Global Bank — Automated GCP Demo VM Provisioning (Isolated Sandbox)"
echo "================================================================================"

# Verify active gcloud authentication
ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n 1 || true)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
    echo "❌ Error: No active gcloud authentication detected."
    echo "   Please run 'gcloud auth login' in Cloud Shell first."
    exit 1
fi
echo "👤 Authenticated GCP Account: $ACTIVE_ACCOUNT"

# Step 1: Resolve Project ID via CLI option or interactive numbered list of all available GCP projects
select_gcp_project() {
    echo ""
    echo "🔍 Fetching available Google Cloud Projects for $ACTIVE_ACCOUNT..."
    mapfile -t PROJECT_LINES < <(gcloud projects list --sort-by=projectId --format="value[separator='|'](projectId,name)" 2>/dev/null || true)

    if [[ ${#PROJECT_LINES[@]} -eq 0 ]]; then
        echo "❌ Error: No accessible Google Cloud Projects found for account '$ACTIVE_ACCOUNT'."
        exit 1
    fi

    CURRENT_GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    declare -a PROJECT_IDS=()

    echo ""
    echo "📋 Available Google Cloud Projects:"
    echo "--------------------------------------------------------------------------------"
    local idx=1
    for line in "${PROJECT_LINES[@]}"; do
        local pid="${line%%|*}"
        local pname="${line#*|}"
        PROJECT_IDS+=("$pid")
        local active_marker=""
        if [[ "$pid" == "$CURRENT_GCP_PROJECT" ]]; then
            active_marker=" [current gcloud project]"
        fi
        printf "   [%2d] %-32s (%s)%s\n" "$idx" "$pid" "$pname" "$active_marker"
        ((idx++))
    done
    echo "--------------------------------------------------------------------------------"

    while true; do
        if ! read -r -p "Select the project number [1-${#PROJECT_IDS[@]}] (or enter Project ID): " SELECTION; then
            echo ""
            echo "❌ Error: No project selection received."
            exit 1
        fi
        SELECTION="${SELECTION#"${SELECTION%%[![:space:]]*}"}"
        SELECTION="${SELECTION%"${SELECTION##*[![:space:]]}"}"

        if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
            if (( SELECTION >= 1 && SELECTION <= ${#PROJECT_IDS[@]} )); then
                PROJECT_ID="${PROJECT_IDS[$((SELECTION - 1))]}"
                break
            else
                echo "⚠️ Invalid selection. Please enter a number between 1 and ${#PROJECT_IDS[@]}."
            fi
        elif [[ -n "$SELECTION" ]]; then
            PROJECT_ID="$SELECTION"
            break
        else
            echo "⚠️ Please enter a valid project number [1-${#PROJECT_IDS[@]}]."
        fi
    done
}

if [[ -z "$PROJECT_ID" ]]; then
    select_gcp_project
fi

if [[ -z "$PROJECT_ID" ]]; then
    echo "❌ Error: Project ID cannot be empty."
    exit 1
fi

echo "✅ Selected Target Project: $PROJECT_ID"

# Normalize Region and Zone
if [[ -n "${REGION:-}" ]]; then
    if [[ "${REGION,,}" =~ ^(belgium|europe-west1)$ ]]; then
        REGION="europe-west1"
    fi
    if [[ -z "${ZONE:-}" || "${ZONE}" != "${REGION}"* ]]; then
        ZONE="${REGION}-b"
    fi
fi

if [[ -z "${ZONE:-}" ]]; then
    if [[ -t 0 ]]; then
        echo ""
        read -r -p "Enter Compute Engine Zone (press Enter for default [$DEFAULT_ZONE]): " INPUT_ZONE
        ZONE="${INPUT_ZONE:-$DEFAULT_ZONE}"
    else
        ZONE="$DEFAULT_ZONE"
    fi
fi
REGION="${ZONE%-*}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Step 2: Auto-detect available VPC Network and Subnet in target region
echo "🔍 Resolving VPC network and regional subnet in $PROJECT_ID ($REGION)..."
DETECTED_NETWORK=""
AVAILABLE_NETWORKS=$(gcloud compute networks list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || true)

# Prioritize default or default-vpc, otherwise first available network
for net_candidate in default default-vpc; do
    if echo "$AVAILABLE_NETWORKS" | grep -Fxq "$net_candidate"; then
        DETECTED_NETWORK="$net_candidate"
        break
    fi
done

if [[ -z "$DETECTED_NETWORK" ]]; then
    DETECTED_NETWORK=$(echo "$AVAILABLE_NETWORKS" | head -n 1)
fi

if [[ -z "$DETECTED_NETWORK" ]]; then
    echo "❌ Error: No VPC network found in project $PROJECT_ID."
    exit 1
fi

# Detect subnet in the chosen region
DETECTED_SUBNET=$(gcloud compute networks subnets list \
    --project="$PROJECT_ID" \
    --network="$DETECTED_NETWORK" \
    --filter="region:($REGION)" \
    --format="value(name)" 2>/dev/null | head -n 1 || true)

echo "   • Detected Network: $DETECTED_NETWORK"
if [[ -n "$DETECTED_SUBNET" ]]; then
    echo "   • Regional Subnet:  $DETECTED_SUBNET"
fi

echo ""
echo "--------------------------------------------------------------------------------"
echo "📋 Deployment Configuration:"
echo "   • Project ID:          $PROJECT_ID"
echo "   • Zone / Region:       $ZONE ($REGION)"
echo "   • Instance Name:       $VM_NAME"
echo "   • Machine Type:        $MACHINE_TYPE (2 vCPUs, 8 GB RAM)"
echo "   • VPC Network:         $DETECTED_NETWORK"
echo "   • Dedicated Identity:  $SA_EMAIL"
echo "   • Target Port:         5000 (HTTP)"
echo "   • Isolation Model:     Dedicated least-privilege SA + tag-scoped firewall"
echo "--------------------------------------------------------------------------------"

# Step 3: Ensure Required GCP APIs are enabled
echo "🔍 Ensuring required APIs are active on $PROJECT_ID..."
gcloud services enable compute.googleapis.com aiplatform.googleapis.com \
    --project="$PROJECT_ID" --quiet

# Step 4: Create Dedicated Least-Privilege Service Account (Isolation Best Practice)
echo "🔒 Ensuring isolated, least-privilege service account ($SA_NAME)..."
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
    gcloud iam service-accounts create "$SA_NAME" \
        --project="$PROJECT_ID" \
        --display-name="ApexFin Demo Sandbox Service Account" \
        --description="Isolated least-privilege identity for temporary CodeMender demo VM" \
        --quiet
    echo "   ✅ Created dedicated service account: $SA_EMAIL"
    
    sleep 2
    # Grant strictly roles/aiplatform.user (only required for CodeMender AI reasoning engine)
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/aiplatform.user" \
        --condition=None \
        --quiet &>/dev/null
    echo "   ✅ Granted strictly 'roles/aiplatform.user' (zero access to storage, compute, or secrets)"
else
    echo "   ℹ️ Service account '$SA_EMAIL' already exists."
fi

# Step 5: Configure VPC Firewall Rule for Port 5000 (Strictly Tag-Scoped)
echo "🛡️ Configuring tag-scoped VPC firewall rule ($FIREWALL_RULE)..."
if ! gcloud compute firewall-rules describe "$FIREWALL_RULE" --project="$PROJECT_ID" &>/dev/null; then
    gcloud compute firewall-rules create "$FIREWALL_RULE" \
        --project="$PROJECT_ID" \
        --network="$DETECTED_NETWORK" \
        --direction=INGRESS \
        --priority=1000 \
        --action=ALLOW \
        --rules=tcp:5000 \
        --source-ranges=0.0.0.0/0 \
        --target-tags="$NETWORK_TAG" \
        --description="Allow public ingress on port 5000 strictly for ApexFin demo server" \
        --quiet
    echo "   ✅ Firewall rule created (isolated to tag: $NETWORK_TAG in network: $DETECTED_NETWORK)."
else
    echo "   ℹ️ Firewall rule '$FIREWALL_RULE' already exists."
fi

# Step 6: Bundle local application code
echo "📦 Packaging local application files..."
ARCHIVE_PATH="/tmp/apexfin_app_bundle.tar.gz"
tar --exclude='.git' --exclude='.venv' --exclude='*.db' --exclude='app.log' \
    -czf "$ARCHIVE_PATH" -C "$SCRIPT_DIR" .

APP_BUNDLE_B64=$(base64 -w 0 "$ARCHIVE_PATH")
rm -f "$ARCHIVE_PATH"

# Step 7: Construct VM Startup Script
STARTUP_SCRIPT=$(cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
export HOME=/root

echo "=== [1/6] Installing system dependencies and tools ==="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    unzip \
    iputils-ping

echo "=== [2/6] Installing CodeMender CLI ('cm') ==="
METADATA_TOKEN=\$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4 || echo '')
if [[ -n "\$METADATA_TOKEN" ]]; then
    curl -H "Authorization: Bearer \$METADATA_TOKEN" -L -o /tmp/cm-linux-amd64.zip "https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3Astable%3Acm-linux-amd64.zip:download?alt=media" || true
else
    curl -L -o /tmp/cm-linux-amd64.zip "https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3Astable%3Acm-linux-amd64.zip:download?alt=media" || true
fi

if [[ -f "/tmp/cm-linux-amd64.zip" ]]; then
    unzip -q -o /tmp/cm-linux-amd64.zip -d /tmp/cm_bin 2>/dev/null || true
    if [[ -f "/tmp/cm_bin/cm" ]]; then
        chmod +x /tmp/cm_bin/cm
        mv /tmp/cm_bin/cm /usr/local/bin/cm
        rm -rf /tmp/cm-linux-amd64.zip /tmp/cm_bin
        echo "CodeMender CLI installed at /usr/local/bin/cm"
    fi
fi

echo "=== [3/6] Unpacking ApexFin Banking Application ==="
APP_DIR="/opt/apexfin"
mkdir -p "\$APP_DIR"
cd "\$APP_DIR"

echo "${APP_BUNDLE_B64}" | base64 -d | tar -xz -C "\$APP_DIR"

echo "=== [4/6] Setting up Python virtual environment ==="
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Initialize database
python3 database.py

# Initialize git repository for CodeMender diff tracking
git config --system --add safe.directory "\$APP_DIR"
git config --global --add safe.directory "\$APP_DIR"
git config --global user.name "ApexFin Demo Ops"
git config --global user.email "demo-ops@apexfin.internal"
git init "\$APP_DIR"
git -C "\$APP_DIR" add -A
git -C "\$APP_DIR" commit -m "Baseline: ApexFin Banking Portal with intentional demo vulnerabilities" || true
chmod -R 777 "\$APP_DIR"

echo "=== [5/6] Creating systemd service for ApexFin Portal ==="
cat << 'SERVICE_EOF' > /etc/systemd/system/apexfin.service
[Unit]
Description=ApexFin Banking Portal Demo Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/apexfin
Environment="PATH=/opt/apexfin/.venv/bin:/usr/local/bin:/usr/bin"
Environment="PORT=5000"
Environment="HOST=0.0.0.0"
Environment="FLASK_ENV=production"
Environment="FLASK_DEBUG=0"
Environment="GOOGLE_CLOUD_PROJECT=${PROJECT_ID}"
ExecStart=/opt/apexfin/.venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --threads 4 --timeout 60 --reload app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "export GOOGLE_CLOUD_PROJECT=\"${PROJECT_ID}\"" > /etc/profile.d/codemender.sh
chmod 644 /etc/profile.d/codemender.sh

systemctl daemon-reload
systemctl enable apexfin.service
systemctl restart apexfin.service

echo "=== [6/6] ApexFin Startup Completed Successfully ==="
EOF
)

# Step 8: Create or Recreate the Compute Engine VM
echo "🚀 Provisioning Compute Engine VM ($VM_NAME) in $ZONE..."
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
    echo "   ⚠️ An instance named '$VM_NAME' already exists."
    if [[ "$AUTO_RECREATE" == true ]]; then
        RECREATE="y"
    elif [[ -t 0 ]]; then
        read -r -p "Do you want to delete and recreate it? (y/N): " RECREATE
    else
        RECREATE="y"
    fi
    if [[ "${RECREATE,,}" == "y" || "${RECREATE,,}" == "yes" ]]; then
        echo "   🛑 Deleting existing VM..."
        gcloud compute instances delete "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet
    else
        echo "Exiting without changes."
        exit 0
    fi
fi

SUBNET_ARG=()
if [[ -n "$DETECTED_SUBNET" ]]; then
    SUBNET_ARG=(--subnet="$DETECTED_SUBNET")
fi

gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="ubuntu-2204-lts" \
    --image-project="ubuntu-os-cloud" \
    --boot-disk-size="30GB" \
    --boot-disk-type="pd-balanced" \
    --network="$DETECTED_NETWORK" \
    "${SUBNET_ARG[@]}" \
    --service-account="$SA_EMAIL" \
    --scopes="https://www.googleapis.com/auth/cloud-platform" \
    --tags="$NETWORK_TAG" \
    --metadata=startup-script="$STARTUP_SCRIPT" \
    --description="Temporary isolated sandbox VM for CodeMender customer demo" \
    --quiet

# Step 9: Wait for Public IP and Display URLs
echo ""
echo "⏳ Waiting for VM public IP allocation..."
EXTERNAL_IP=""
for i in {1..15}; do
    EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
    if [[ -n "$EXTERNAL_IP" ]]; then
        break
    fi
    sleep 3
done

if [[ -z "$EXTERNAL_IP" ]]; then
    echo "⚠️ Failed to resolve external IP automatically. Querying gcloud instances list:"
    gcloud compute instances list --filter="name=$VM_NAME" --project="$PROJECT_ID"
    exit 0
fi

echo "================================================================================"
echo "🎉 DEMO VM SUCCESSFULLY PROVISIONED & DEPLOYED!"
echo "================================================================================"
echo "🌐 Direct Public URL (Browser Access from Anywhere):"
echo "   http://${EXTERNAL_IP}:5000"
echo ""
echo "🔐 Cloud Shell Port Forwarding (If corporate firewall blocks port 5000):"
echo "   gcloud compute ssh ${VM_NAME} --zone=${ZONE} --project=${PROJECT_ID} -- -L 5000:localhost:5000"
echo "   Then open in Cloud Shell Web Preview (Port 5000): http://localhost:5000"
echo ""
echo "--------------------------------------------------------------------------------"
echo "💻 CLOUD SHELL COMMAND TO LOGIN TO THE VM & RUN CODEMENDER ('cm'):"
echo "--------------------------------------------------------------------------------"
echo "   gcloud compute ssh ${VM_NAME} --zone=${ZONE} --project=${PROJECT_ID}"
echo ""
echo "   Once logged into the VM, run:"
echo "   $ cd /opt/apexfin"
echo "   $ cm init"
echo "   $ cm find ./app.py"
echo "   $ cm verify <FINDING_ID>"
echo "   $ cm fix <FINDING_ID>"
echo "--------------------------------------------------------------------------------"
echo ""
echo "🧹 Deprovisioning / Teardown Command (Run in Cloud Shell after demo):"
echo "   ./deprovision_vm.sh --project ${PROJECT_ID}"
echo "   (or run './deprovision_vm.sh' to pick from the interactive project list)"
echo "================================================================================"
