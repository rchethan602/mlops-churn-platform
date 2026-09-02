#!/bin/bash
set -euo pipefail

MLFLOW_URI="http://mlflow.mlflow.svc.cluster.local:5000"
MODEL_NAME="vehicle-predictive-maintenance"

if ! command -v jq &> /dev/null; then
  curl -sL -o /usr/local/bin/jq \
    https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
  chmod +x /usr/local/bin/jq
fi
if ! command -v kubectl &> /dev/null; then
  curl -sL -o /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

echo "Looking up 'previous-production' version..."
PREV=$(curl -s -G "${MLFLOW_URI}/api/2.0/mlflow/registered-models/alias" \
  --data-urlencode "name=${MODEL_NAME}" \
  --data-urlencode "alias=previous-production")

PREV_VERSION=$(echo "$PREV" | jq -r '.model_version.version // empty')
PREV_SOURCE=$(echo "$PREV" | jq -r '.model_version.source // empty')

if [ -z "$PREV_VERSION" ]; then
  echo "No 'previous-production' alias found - nothing to roll back to."
  exit 1
fi

echo "Rolling back to version ${PREV_VERSION} (${PREV_SOURCE})"

echo "Moving 'production' alias back to version ${PREV_VERSION}..."
curl -s -X POST "${MLFLOW_URI}/api/2.0/mlflow/registered-models/alias" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${MODEL_NAME}\", \"alias\": \"production\", \"version\": \"${PREV_VERSION}\"}"

echo "Redeploying KServe with the rolled-back version..."
kubectl patch inferenceservice vehicle-predictive-maintenance -n mlops-serving \
  --type merge \
  -p "{\"spec\":{\"predictor\":{\"model\":{\"storageUri\":\"${PREV_SOURCE}\"}}}}"

kubectl wait --for=condition=Ready inferenceservice/vehicle-predictive-maintenance \
  -n mlops-serving --timeout=180s

echo "=== Rollback complete ==="
echo "Production is now serving version ${PREV_VERSION}"