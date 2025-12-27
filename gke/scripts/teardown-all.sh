#!/usr/bin/env bash
# Teardown script to remove GKE + Kubernetes resources

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
NAMESPACE="iot-pipeline"
PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"

echo "⚠️  WARNING"
echo "This script will:"
echo "  - Delete Kubernetes namespace: ${NAMESPACE}"
echo "  - Destroy all Terraform-managed GKE infrastructure"
echo "  - Delete unattached GCE disks (PVC leftovers)"
echo
read -p "Type 'yes' to continue: " CONFIRM
echo

if [[ "${CONFIRM}" != "yes" ]]; then
  echo "❌ Aborted"
  exit 1
fi

# ------------------------------------------------------------------
# Set project explicitly (important)
# ------------------------------------------------------------------
echo "🔧 Setting GCP project to ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# ------------------------------------------------------------------
# Delete Kubernetes namespace (wait until fully removed)
# ------------------------------------------------------------------
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "🧹 Deleting namespace ${NAMESPACE}"
  kubectl delete namespace "${NAMESPACE}" --wait=true
  echo "✅ Namespace ${NAMESPACE} deleted"
else
  echo "ℹ️ Namespace ${NAMESPACE} not found, skipping"
fi

# ------------------------------------------------------------------
# Destroy Terraform-managed infrastructure (GKE cluster, VPC, etc.)
# ------------------------------------------------------------------
echo "🔥 Destroying Terraform infrastructure"
cd "${PROJECT_ROOT}/gke/terraform"
terraform destroy -auto-approve
echo "✅ Terraform infrastructure destroyed"

# ------------------------------------------------------------------
# Cleanup leftover unattached persistent disks (very common with GKE)
# ------------------------------------------------------------------
echo "🧹 Cleaning up unattached persistent disks (PVC leftovers)"

DISKS=$(gcloud compute disks list \
  --filter="-users:*" \
  --format="value(name,zone)")

if [[ -z "${DISKS}" ]]; then
  echo "✅ No unattached disks found"
else
  echo "${DISKS}" | while read -r DISK ZONE; do
    echo "Deleting disk ${DISK} in zone ${ZONE}"
    gcloud compute disks delete "${DISK}" \
      --zone="${ZONE}" \
      --quiet
  done
  echo "✅ Unattached disks deleted"
fi

echo
echo "🎉 GKE cleanup completed successfully"
