"""
Training entrypoint for the vehicle predictive-maintenance model.

Runs inside a SageMaker BYOC training job. SageMaker has already downloaded
the S3 dataset into SM_CHANNEL_TRAIN before this script starts - no S3 code
needed here. Model artifacts are written to SM_MODEL_DIR, which SageMaker
automatically tars and uploads to S3 as the job's output.

All experiment tracking (params, metrics, the model itself, and registry
promotion) goes to the MLflow server running on EKS via MLFLOW_TRACKING_URI.
"""

import os
import json
import argparse
import pandas as pd
import mlflow
import mlflow.sklearn
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    roc_auc_score,
)


def parse_args():
    parser = argparse.ArgumentParser()
    # SageMaker hyperparameters arrive as CLI args when using script-mode-style
    # invocation; defaults here let the script also run identically outside
    # SageMaker (e.g. a future local unit test) without any special-casing.
    parser.add_argument("--n-estimators", type=int, default=200)
    parser.add_argument("--max-depth", type=int, default=8)
    parser.add_argument("--random-state", type=int, default=42)
    parser.add_argument("--test-size", type=float, default=0.2)

    # SageMaker-provided directories (env vars are injected automatically
    # inside a real SageMaker training job; defaults match local/test runs)
    parser.add_argument(
        "--train-dir",
        type=str,
        default=os.environ.get("SM_CHANNEL_TRAIN", "/opt/ml/input/data/train"),
    )
    parser.add_argument(
        "--model-dir",
        type=str,
        default=os.environ.get("SM_MODEL_DIR", "/opt/ml/model"),
    )
    return parser.parse_args()


def load_dataset(train_dir: str) -> pd.DataFrame:
    csv_files = [f for f in os.listdir(train_dir) if f.endswith(".csv")]
    if not csv_files:
        raise FileNotFoundError(f"No CSV file found in {train_dir}")
    path = os.path.join(train_dir, csv_files[0])
    df = pd.read_csv(path)
    return df


def prepare_features(df: pd.DataFrame):
    # AI4I 2020 columns: UDI, Product ID, Type, Air temperature [K],
    # Process temperature [K], Rotational speed [rpm], Torque [Nm],
    # Tool wear [min], Machine failure, TWF, HDF, PWF, OSF, RNF
    df = df.drop(columns=["UDI", "Product ID"])

    # Binary target
    y = df["Machine failure"]
    X = df.drop(columns=["Machine failure", "TWF", "HDF", "PWF", "OSF", "RNF"])

    # Only one categorical column ("Type": L/M/H) - simple label encoding,
    # deliberately not one-hot to keep this a single, auditable transform
    # rather than a feature-engineering pipeline.
    le = LabelEncoder()
    X["Type"] = le.fit_transform(X["Type"])

    return X, y


def main():
    args = parse_args()

    mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
    mlflow.set_experiment("vehicle-predictive-maintenance")

    df = load_dataset(args.train_dir)
    X, y = prepare_features(df)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=args.test_size, random_state=args.random_state, stratify=y
    )

    with mlflow.start_run():
        params = {
            "n_estimators": args.n_estimators,
            "max_depth": args.max_depth,
            "random_state": args.random_state,
            "test_size": args.test_size,
        }
        mlflow.log_params(params)

        model = RandomForestClassifier(
            n_estimators=args.n_estimators,
            max_depth=args.max_depth,
            random_state=args.random_state,
            class_weight="balanced",  # dataset is imbalanced (few failures)
        )
        model.fit(X_train, y_train)

        y_pred = model.predict(X_test)
        y_proba = model.predict_proba(X_test)[:, 1]

        metrics = {
            "accuracy": accuracy_score(y_test, y_pred),
            "precision": precision_score(y_test, y_pred),
            "recall": recall_score(y_test, y_pred),
            "f1": f1_score(y_test, y_pred),
            "roc_auc": roc_auc_score(y_test, y_proba),
        }
        mlflow.log_metrics(metrics)
        print(json.dumps(metrics, indent=2))

        # Logs the model to MLflow's S3 artifact store AND registers a new
        # version under this name in the MLflow Model Registry in one call.
        mlflow.sklearn.log_model(
            sk_model=model,
            artifact_path="model",
            registered_model_name="vehicle-predictive-maintenance",
        )

        # Also satisfy SageMaker's own contract: anything written here gets
        # tarred and uploaded to S3 as the training job's output automatically.
        # MLflow's registry remains the source of truth for deployment (Phase 7+);
        # this is a secondary copy, useful for debugging a specific job's output
        # without going through MLflow.
        os.makedirs(args.model_dir, exist_ok=True)
        mlflow.sklearn.save_model(model, os.path.join(args.model_dir, "model"))

        print(f"Run ID: {mlflow.active_run().info.run_id}")


if __name__ == "__main__":
    main()