#!/usr/bin/env bash
# ==============================================================================
# Author: Pradeep Singh
# License: Apache-2.0
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
PROJECT_ID="${PROJECT_ID:-}"
ZONE="${ZONE:-}"

usage() {
    echo "Usage: ./deprovision_vm.sh [--project|-p <PROJECT_ID>] [--zone|-z <ZONE>] [-y|--yes]"
    echo ""
    echo "Options:"
    echo "  -p, --project <PROJECT_ID>  Target Google Cloud Project ID (if omitted, displays an interactive numbered list)"
    echo "  -z, --zone <ZONE>           Compute Engine Zone (auto-detected if VM exists)"
    echo "  -y, --yes                   Skip confirmation prompt"
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
        -y|--yes)
            AUTO_APPROVE=true
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
echo "🧹 ApexFin Global Bank — GCP Demo VM Deprovisioning & Teardown"
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

# Auto-detect existing VM zone if not explicitly set
DETECTED_VM_ZONE=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$VM_NAME" --format="value(zone)" 2>/dev/null | head -n 1 || true)

if [[ -z "${ZONE:-}" ]]; then
    if [[ -n "$DETECTED_VM_ZONE" ]]; then
        ZONE="$DETECTED_VM_ZONE"
        echo "   • Detected active VM zone: $ZONE"
    elif [[ -t 0 && "$AUTO_APPROVE" == false ]]; then
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

# Step 4: Delete Dedicated Service Account & IAM Policy Bindings
echo ""
echo "🔒 [3/3] Checking dedicated demo service account: $SA_EMAIL..."
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
    echo "   Revoking 'roles/aiplatform.user' IAM binding for '$SA_EMAIL'..."
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/aiplatform.user" \
        --condition=None \
        --quiet &>/dev/null || true
    echo "   Deleting service account '$SA_EMAIL'..."
    gcloud iam service-accounts delete "$SA_EMAIL" \
        --project="$PROJECT_ID" \
        --quiet
    echo "   ✅ Dedicated demo service account deleted successfully."
else
    echo "   ℹ️ Service account '$SA_EMAIL' was not found or already deleted."
fi

# Clean up any lingering tombstone IAM bindings for deleted instances of the demo service account
DELETED_SA_MEMBERS=$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.role=roles/aiplatform.user AND bindings.members~^deleted:serviceAccount:${SA_EMAIL}" \
    --format="value(bindings.members)" 2>/dev/null || true)

if [[ -n "$DELETED_SA_MEMBERS" ]]; then
    while IFS= read -r member; do
        if [[ -n "$member" ]]; then
            echo "   Cleaning up orphaned IAM binding: $member..."
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="$member" \
                --role="roles/aiplatform.user" \
                --condition=None \
                --quiet &>/dev/null || true
        fi
    done <<< "$DELETED_SA_MEMBERS"
    echo "   ✅ Cleaned up orphaned IAM bindings for '$SA_EMAIL'."
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
