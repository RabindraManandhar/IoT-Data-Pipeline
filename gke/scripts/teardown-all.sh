#!/bin/sh
# Teardown script to remove all resources

set -e

NAMESPACE="iot-pipeline"

echo "⚠️  WARNING: This will delete all resources in namespace ${NAMESPACE}"
read -p "Are you sure? (type 'yes' and press ENTER to confirm) " -r
echo

if [[ $REPLY == "yes" ]]; then
    echo "Deleting all resources..."
    kubectl delete --force namespace ${NAMESPACE}
    echo "✅ All Kubernetes resources deleted"

    echo "Deleting all GKE infrastructures..."
    terraform destroy -auto-approve
    echo "✅ All GKE infrastructure deleted"
else
    echo "Aborted"
fi