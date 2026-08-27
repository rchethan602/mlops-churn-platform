"""
Launches a SageMaker BYOC training job for the vehicle predictive-maintenance
model. Designed to be run manually now, and called from GitHub Actions
(trigger-training.yml) unchanged in Phase 5.

Requires AWS credentials in the environment (via IRSA on the ARC runner, or
your local AWS CLI profile) with sagemaker:CreateTrainingJob / DescribeTrainingJob
permissions, and iam:PassRole on sagemaker-execution-role.
"""

import time
import boto3

REGION = "eu-central-1"
ACCOUNT_ID = "907615197397"

TRAINING_IMAGE = f"{ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com/mlops-churn-train:v1"
EXECUTION_ROLE_ARN = f"arn:aws:iam::{ACCOUNT_ID}:role/sagemaker-execution-role"

S3_INPUT_URI = "s3://mlops-churn-dataset/raw/vehicle-predictive-maintenance/v1/"
S3_OUTPUT_URI = "s3://mlops-churn-dataset/output/"

MLFLOW_TRACKING_URI = "http://mlflow.int.itsconnectedcar.com"


def main():
    sm = boto3.client("sagemaker", region_name=REGION)

    job_name = f"mlops-churn-train-{int(time.time())}"

    response = sm.create_training_job(
        TrainingJobName=job_name,
        AlgorithmSpecification={
            "TrainingImage": TRAINING_IMAGE,
            "TrainingInputMode": "File",
        },
        RoleArn=EXECUTION_ROLE_ARN,
        InputDataConfig=[
            {
                "ChannelName": "train",
                "DataSource": {
                    "S3DataSource": {
                        "S3DataType": "S3Prefix",
                        "S3Uri": S3_INPUT_URI,
                        "S3DataDistributionType": "FullyReplicated",
                    }
                },
                "ContentType": "text/csv",
            }
        ],
        OutputDataConfig={"S3OutputPath": S3_OUTPUT_URI},
        ResourceConfig={
            "InstanceType": "ml.m5.large",
            "InstanceCount": 1,
            "VolumeSizeInGB": 5,
        },
        StoppingCondition={"MaxRuntimeInSeconds": 1800},  # 30 min hard cap - cost guardrail
        Environment={
            "MLFLOW_TRACKING_URI": MLFLOW_TRACKING_URI,
        },
        Tags=[
            {"Key": "project", "Value": "mlops-churn-platform"},
        ],
    )

    print(f"Launched training job: {job_name}")
    print(f"ARN: {response['TrainingJobArn']}")
    print(
        f"Console: https://{REGION}.console.aws.amazon.com/sagemaker/home"
        f"?region={REGION}#/jobs/{job_name}"
    )


if __name__ == "__main__":
    main()