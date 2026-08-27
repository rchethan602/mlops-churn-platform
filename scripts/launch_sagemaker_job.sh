#!/bin/bash
set -euo pipefail

REGION="eu-central-1"
JOB_NAME="mlops-churn-train-$(date +%s)"
CONFIG_TEMPLATE="scripts/training-job-config.json"
CONFIG_RENDERED="/tmp/training-job-config-rendered.json"

# Inject the unique job name into the JSON template - sed is available
# everywhere, no jq dependency required either.
sed "s/PLACEHOLDER-SET-BY-SCRIPT/${JOB_NAME}/" "${CONFIG_TEMPLATE}" > "${CONFIG_RENDERED}"

echo "Launching training job: ${JOB_NAME}"

aws sagemaker create-training-job \
  --region "${REGION}" \
  --cli-input-json "file://${CONFIG_RENDERED}"

echo "Job launched. Console:"
echo "https://${REGION}.console.aws.amazon.com/sagemaker/home?region=${REGION}#/jobs/${JOB_NAME}"