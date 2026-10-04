#!/usr/bin/env bash
# ==============================================================================
# Purpose: Automated deprovisioning and teardown script for the temporary ApexFin
#          demo VM and associated GCP cloud resources.
# Architecture/Context: Ensures zero lingering cloud infrastructure costs and wipes
#                       all vulnerable demo resources after a customer presentation,
#                       without touching or altering any other project configuration.
# Dependencies/Side Effects: Deletes Compute Engine VM instance, VPC firewall rule,
#                            and isolated service account via gcloud CLI.
# ==============================================================================

set -euo pipefail

VM_NAME="apexfin-demo-vm"
FIREWALL_RULE="apexfin-demo-allow-5000"
SA_NAME="apexfin-demo-sa"
DEFAULT_ZONE="us-central1-a"

AUTO_APPROVE=false
for arg in "$@"; do
    if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
        AUTO_APPROVE=true
    fi
done

echo "================================================================================"
echo "🧹 ApexFin Global Bank — GCP Demo VM Deprovisioning & Teardown"
echo "================================================================================"

# Step 1: Resolve Project ID with interactive prompt and fallback default
CURRENT_GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$CURRENT_GCP_PROJECT" ]]; then
    CURRENT_GCP_PROJECT="maf-testing-387011"
fi

if [[ -z "${PROJECT_ID:-}" ]]; then
    if [[ -t 0 && "$AUTO_APPROVE" == false ]]; then
        echo ""
        echo "Select the Google Cloud Project to deprovision resources from."
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
    if [[ -t 0 && "$AUTO_APPROVE" == false ]]; then
        echo ""
        read -r -p "Enter Compute Engine Zone (press Enter for default [$DEFAULT_ZONE]): " INPUT_ZONE
        ZONE="${INPUT_ZONE:-$DEFAULT_ZONE}"
    else
        ZONE="$DEFAULT_ZONE"
    fi
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo ""
echo "--------------------------------------------------------------------------------"
echo "⚠️  Strict Targeted Teardown: ONLY the following demo assets will be deleted from $PROJECT_ID:"
echo "   • Compute Engine Instance: $VM_NAME (Zone: $ZONE)"
echo "   • VPC Firewall Rule:       $FIREWALL_RULE"
echo "   • Dedicated IAM Account:   $SA_EMAIL"
echo "   (All other VMs, networks, databases, and project configs remain untouched)"
echo "--------------------------------------------------------------------------------"

if [[ "$AUTO_APPROVE" == false ]]; then
    read -r -p "Are you sure you want to permanently delete these demo resources? (y/N): " CONFIRM
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        echo "Aborting deprovisioning. No resources were deleted."
        exit 0
    fi
fi

# Step 2: Delete Compute Engine Instance
echo ""
echo "🛑 [1/3] Checking Compute Engine VM: $VM_NAME..."
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
    echo "   Deleting VM instance '$VM_NAME' in zone $ZONE..."
    gcloud compute instances delete "$VM_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --quiet
    echo "   ✅ VM instance '$VM_NAME' deleted successfully."
else
    echo "   ℹ️ VM instance '$VM_NAME' was not found or already deleted."
fi

# Step 3: Delete Tag-Scoped VPC Firewall Rule
echo ""
echo "🛡️ [2/3] Checking VPC firewall rule: $FIREWALL_RULE..."
if gcloud compute firewall-rules describe "$FIREWALL_RULE" --project="$PROJECT_ID" &>/dev/null; then
    echo "   Deleting firewall rule '$FIREWALL_RULE'..."
    gcloud compute firewall-rules delete "$FIREWALL_RULE" \
        --project="$PROJECT_ID" \
        --quiet
    echo "   ✅ Firewall rule '$FIREWALL_RULE' deleted successfully."
else
    echo "   ℹ️ Firewall rule '$FIREWALL_RULE' was not found or already deleted."
fi

# Step 4: Delete Dedicated Service Account
echo ""
echo "🔒 [3/3] Checking dedicated demo service account: $SA_EMAIL..."
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
    echo "   Deleting service account '$SA_EMAIL'..."
    gcloud iam service-accounts delete "$SA_EMAIL" \
        --project="$PROJECT_ID" \
        --quiet
    echo "   ✅ Dedicated demo service account deleted successfully."
else
    echo "   ℹ️ Service account '$SA_EMAIL' was not found or already deleted."
fi

# Step 5: Clean up any local temporary archives
rm -f /tmp/apexfin_app_bundle.tar.gz

echo ""
echo "================================================================================"
echo "✅ DEPROVISIONING COMPLETE!"
echo "🎯 All temporary demo compute, network, and IAM resources have been terminated."
echo "💰 No lingering cloud charges will accrue for this demo session."
echo "🛡️ Zero impact to any other resources or configurations in project '$PROJECT_ID'."
echo "================================================================================"
