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
    echo "✅ All resources deleted"
else
    echo "Aborted"
fi