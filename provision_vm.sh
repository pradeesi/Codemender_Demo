#!/usr/bin/env bash
# ==============================================================================
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
for arg in "$@"; do
    if [[ "$arg" == "-y" || "$arg" == "--yes" || "$arg" == "--recreate" ]]; then
        AUTO_RECREATE=true
    fi
done

echo "================================================================================"
echo "🏦 ApexFin Global Bank — Automated GCP Demo VM Provisioning (Isolated Sandbox)"
echo "================================================================================"

# Step 1: Resolve Project ID with interactive prompt and fallback default
CURRENT_GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$CURRENT_GCP_PROJECT" ]]; then
    CURRENT_GCP_PROJECT="maf-testing-387011"
fi

if [[ -z "${PROJECT_ID:-}" ]]; then
    if [[ -t 0 ]]; then
        echo ""
        echo "Select the target Google Cloud Project for this temporary demo VM."
        echo "Default/Current: [${CURRENT_GCP_PROJECT}]"
        read -r -p "Enter Google Cloud Project ID (press Enter to accept default): " INPUT_PROJECT
        PROJECT_ID="${INPUT_PROJECT:-$CURRENT_GCP_PROJECT}"
    else
        PROJECT_ID="$CURRENT_GCP_PROJECT"
    fi
fi

if [[ -z "$PROJECT_ID" ]]; then
    echo "❌ Error: Project ID cannot be empty."
    exit 1
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
git config --global --add safe.directory "\$APP_DIR"
git config --global user.name "ApexFin Demo Ops"
git config --global user.email "demo-ops@apexfin.internal"
git init "\$APP_DIR"
git -C "\$APP_DIR" add -A
git -C "\$APP_DIR" commit -m "Baseline: ApexFin Banking Portal with intentional demo vulnerabilities" || true

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
echo "🔐 Cloud Shell / Local Port Forwarding (If corporate firewall blocks port 5000):"
echo "   gcloud compute ssh ${VM_NAME} --zone=${ZONE} --project=${PROJECT_ID} -- -L 5000:localhost:5000"
echo "   Then open in browser or Cloud Shell Web Preview: http://localhost:5000"
echo ""
echo "💻 SSH Access to Run CodeMender ('cm') Inside the Sandbox VM:"
echo "   gcloud compute ssh ${VM_NAME} --zone=${ZONE} --project=${PROJECT_ID}"
echo "   Inside the VM, navigate to the codebase:"
echo "   $ cd /opt/apexfin"
echo "   $ cm find ./app.py"
echo "   $ cm verify <FINDING_ID>"
echo "   $ cm fix <FINDING_ID>"
echo ""
echo "🧹 Deprovisioning / Teardown Instructions (Run after customer demo):"
echo "   ./deprovision_vm.sh"
echo "================================================================================"
