# Storage classes are created via kubectl using kubernetes manifests after cluster creation
# See: k8s/storage/storage-class.yaml

# This avoids chicken-and-egg problem where Terraform's Kubernetes provider
# needs cluster credentials that don't exist until after cluster creation.

# Storage classes will be created by the deployment script after running:
# gcloud container clusters get-credentials <cluster-name> --zone <zone-name>

# To create storage classes manually:
# kubectl apply -f gke/storage/storage-class.yaml