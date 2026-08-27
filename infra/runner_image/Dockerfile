# Base image - CONFIRM this matches your current runner pod's image exactly
# (run: kubectl get pod -n arc-systems -l 'actions.github.com/scale-set-name=mlflow-runner' -o jsonpath='{.items[0].spec.containers[*].image}')
FROM ghcr.io/actions/actions-runner:latest

USER root

# Baking these in at build time (on a machine with working internet/proxy)
# avoids any apt-get call from inside the cluster at job-runtime, which is
# blocked by the corporate transparent proxy (automotive-wan.com).
RUN apt-get update -qq \
    && apt-get install -y -qq python3 python3-pip curl unzip \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 - not available via apt, install the official bundle directly
RUN curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# boto3 baked in - training-trigger workflows need no pip install step at all
RUN pip3 install boto3 --break-system-packages

USER runner