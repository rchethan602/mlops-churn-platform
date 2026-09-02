#!/bin/bash
set -euo pipefail

MLFLOW_URI="http://mlflow.mlflow.svc.cluster.local:5000"
MODEL_NAME="vehicle-predictive-maintenance"
METRIC_NAME="roc_auc"
THRESHOLD="${PROMOTION_THRESHOLD:-0.85}"

# jq isn't available on the runner (see earlier apt/proxy issues) - pull a
# static binary directly rather than relying on a package manager.
if ! command -v jq &> /dev/null; then
  echo "jq not found - downloading static binary"
  curl -sL -o /usr/local/bin/jq \
    https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
  chmod +x /usr/local/bin/jq
fi

echo "Finding latest version of '${MODEL_NAME}'..."
LATEST=$(curl -s -G "${MLFLOW_URI}/api/2.0/mlflow/model-versions/search" \
  --data-urlencode "filter=name='${MODEL_NAME}'" \
  --data-urlencode "order_by=version_number DESC" \
  --data-urlencode "max_results=1")

echo "Raw API response: ${LATEST}"

VERSION=$(echo "$LATEST" | jq -r '.model_versions[0].version')
RUN_ID=$(echo "$LATEST" | jq -r '.model_versions[0].run_id')
SOURCE=$(echo "$LATEST" | jq -r '.model_versions[0].source')

if [ "$VERSION" == "null" ] || [ -z "$VERSION" ]; then
  echo "No registered versions found for ${MODEL_NAME}"
  exit 1
fi

echo "Candidate: version ${VERSION} (run ${RUN_ID})"

echo "Fetching metrics for run ${RUN_ID}..."
RUN_DATA=$(curl -s -G "${MLFLOW_URI}/api/2.0/mlflow/runs/get" \
  --data-urlencode "run_id=${RUN_ID}")

METRIC_VALUE=$(echo "$RUN_DATA" | jq -r --arg m "$METRIC_NAME" \
  '.run.data.metrics[] | select(.key == $m) | .value')

echo "${METRIC_NAME} = ${METRIC_VALUE} (threshold: ${THRESHOLD})"

# Quality gate - simple numeric comparison via awk (no bc dependency needed)
PASSES=$(awk -v val="$METRIC_VALUE" -v thresh="$THRESHOLD" 'BEGIN { print (val >= thresh) ? "1" : "0" }')

if [ "$PASSES" != "1" ]; then
  echo "FAILED quality gate: ${METRIC_NAME} (${METRIC_VALUE}) is below threshold (${THRESHOLD})"
  echo "Version ${VERSION} will NOT be promoted."
  exit 1
fi

echo "Passed quality gate. Recording current production version for rollback reference..."
CURRENT_PROD=$(curl -s -G "${MLFLOW_URI}/api/2.0/mlflow/registered-models/alias" \
  --data-urlencode "name=${MODEL_NAME}" \
  --data-urlencode "alias=production" | jq -r '.model_version.version // "none"')
echo "Current production version (before this promotion): ${CURRENT_PROD}"

if [ "$CURRENT_PROD" != "none" ] && [ "$CURRENT_PROD" != "$VERSION" ]; then
  echo "Setting 'previous-production' alias on version ${CURRENT_PROD} for rollback..."
  curl -s -X POST "${MLFLOW_URI}/api/2.0/mlflow/registered-models/alias" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${MODEL_NAME}\", \"alias\": \"previous-production\", \"version\": \"${CURRENT_PROD}\"}"
fi

echo "Promoting version ${VERSION} to 'production' alias..."
curl -s -X POST "${MLFLOW_URI}/api/2.0/mlflow/registered-models/alias" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${MODEL_NAME}\", \"alias\": \"production\", \"version\": \"${VERSION}\"}"

echo "Redeploying KServe InferenceService to serve version ${VERSION}..."
if ! command -v kubectl &> /dev/null; then
  echo "kubectl not found - downloading static binary"
  curl -fSL -o /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

kubectl patch inferenceservice vehicle-predictive-maintenance -n mlops-serving \
  --type merge \
  -p "{\"spec\":{\"predictor\":{\"model\":{\"storageUri\":\"${SOURCE}\"}}}}"

echo "Waiting for InferenceService to become Ready..."
kubectl wait --for=condition=Ready inferenceservice/vehicle-predictive-maintenance \
  -n mlops-serving --timeout=180s

echo ""
echo "=== Promotion complete ==="
echo "Model: ${MODEL_NAME}"
echo "Promoted version: ${VERSION}"
echo "Previous production version: ${CURRENT_PROD}"
echo "S3 artifact path: ${SOURCE}"
echo "(Use this path to update inference/kserve/inferenceservice.yaml's storageUri in Phase 8)"

# Emit for downstream GitHub Actions steps
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "promoted_version=${VERSION}" >> "$GITHUB_OUTPUT"
  echo "previous_version=${CURRENT_PROD}" >> "$GITHUB_OUTPUT"
  echo "model_source_uri=${SOURCE}" >> "$GITHUB_OUTPUT"
fi